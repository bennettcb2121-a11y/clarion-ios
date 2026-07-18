import Foundation
import SwiftUI
import StoreKit

/// Clarion+ entitlement + the native In-App Purchase flow. A user is entitled when EITHER:
///
///  A. the SERVER says so — the app-side mirror of the web's `hasDashboardShellAccess`
///     (src/lib/accessGate.ts): `analysis_purchased_at`, a Stripe subscription in
///     `active`/`trialing`/`past_due`, or a webhook-synced `plan_tier` of `full`/`lite`.
///     This keeps existing WEB purchasers entitled inside the app.
///  B. a verified STOREKIT transaction grants it — the Apple In-App Purchase of Clarion+
///     (Guideline 3.1.1: digital subscriptions bought in-app MUST use IAP, not Stripe).
///
/// The server leg FAILS OPEN (only a definitive "no" on every leg locks; network/404/decode
/// keep the last-known answer, cached in UserDefaults). The StoreKit leg is re-derived locally
/// from `Transaction.currentEntitlements` on launch and kept live via `Transaction.updates`.
@MainActor
final class SubscriptionStore: ObservableObject {

    /// Clarion+ products — these identifiers MUST match the auto-renewable subscriptions created
    /// in App Store Connect and the local Clarion.storekit test config.
    enum Plan: String, CaseIterable {
        case monthly = "tech.clarionlabs.clarion.plus.monthly"
        case annual  = "tech.clarionlabs.clarion.plus.annual"
    }
    static let productIDs = Set(Plan.allCases.map(\.rawValue))

    /// Whether the analysis surfaces (Report, Plan, Labs history, Biomarkers) render.
    /// Home, Vitals, Shop, and Settings never consult this.
    @Published private(set) var entitled: Bool
    /// The Clarion+ products, cheapest first. Empty until `loadProducts()` succeeds (or if the
    /// products aren't in App Store Connect yet) — MembershipWall degrades gracefully.
    @Published private(set) var products: [Product] = []
    /// A purchase or restore is in flight (drives the buy button's spinner + disabled state).
    @Published private(set) var purchasing = false

    /// The two legs, combined into `entitled` by `recompute()`.
    private var serverEntitled: Bool
    private var storeKitEntitled = false

    private let auth: SupabaseAuth
    private var updatesTask: Task<Void, Never>?
    private static let cacheKey = "clarion_entitled"

    /// GET /api/subscription/status (bearer-enabled). Snake-case field per the route.
    private struct StatusResponse: Decodable {
        var hasSubscription: Bool?
        var status: String?
        var analysisPurchasedAt: String?

        enum CodingKeys: String, CodingKey {
            case hasSubscription, status
            case analysisPurchasedAt = "analysis_purchased_at"
        }
    }

    init(auth: SupabaseAuth) {
        self.auth = auth
        // Seed the server leg from the last definitive answer; a fresh install starts open.
        let seed = UserDefaults.standard.object(forKey: Self.cacheKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.cacheKey)
        serverEntitled = seed
        entitled = seed
        #if DEBUG
        // Screenshot harness: force the membership wall without a real non-member account.
        if ProcessInfo.processInfo.arguments.contains("UITEST_LOCKED") {
            serverEntitled = false
            entitled = false
        }
        #endif
        // Keep the StoreKit leg current as transactions arrive — renewals, purchases made on
        // another device, and Ask-to-Buy approvals all surface here.
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refreshStoreKitEntitlement() }
    }

    deinit { updatesTask?.cancel() }

    /// The web's `subscriptionStatusGrantsAccess`, verbatim.
    static func statusGrantsAccess(_ status: String?) -> Bool {
        let s = (status ?? "").lowercased()
        return s == "active" || s == "trialing" || s == "past_due"
    }

    // MARK: - Server leg

    /// Refresh the SERVER entitlement. Call on launch and on foreground — cheap, and the answer
    /// usually doesn't change. Fails open (see type doc).
    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_LOCKED") {
            setServer(false)
            return
        }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") }) {
            setServer(true)
            return
        }
        #endif
        guard let token = try? await auth.validAccessToken() else { return } // fail open

        do {
            var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/subscription/status"))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return // 404 (route not on prod yet), 401, 5xx — fail open, keep last known
            }
            let decoded = try JSONDecoder().decode(StatusResponse.self, from: data)
            if decoded.analysisPurchasedAt != nil || Self.statusGrantsAccess(decoded.status) {
                setServer(true)
                return
            }
        } catch {
            return // network / decode — fail open, keep last known
        }

        // The subscription row said no — check the rule's third leg (webhook-synced
        // plan_tier, plus the profile's own analysis_purchased_at) before locking.
        do {
            let profile = try await ClarionAPI.fetchProfileSettings(accessToken: token)
            let tier = (profile?.planTier ?? "").lowercased()
            if tier == "full" || tier == "lite" || profile?.analysisPurchasedAt != nil {
                setServer(true)
            } else {
                setServer(false) // every server leg answered no
            }
        } catch {
            return // couldn't verify the last leg — fail open, keep last known
        }
    }

    private func setServer(_ value: Bool) {
        serverEntitled = value
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
        recompute()
    }

    // MARK: - StoreKit leg (In-App Purchase)

    /// Fetch the Clarion+ products from the App Store. Safe to call repeatedly; only fetches once.
    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            // Leave empty — MembershipWall shows the manage-account fallback.
        }
    }

    /// Buy a Clarion+ plan. Verifies the transaction, unlocks locally, mirrors to the backend.
    func purchase(_ product: Product) async {
        guard !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result {
                await handle(verification)
            }
            // .userCancelled / .pending (Ask to Buy) → no change; a pending purchase resolves
            // later through Transaction.updates.
        } catch {
            // Purchase failed — no state change.
        }
    }

    /// Restore purchases — Apple requires a restore path for non-consumables/subscriptions
    /// (Guideline 3.1.1). Re-syncs the App Store and re-derives the entitlement.
    func restore() async {
        guard !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        try? await AppStore.sync()
        await refreshStoreKitEntitlement()
    }

    private func refreshStoreKitEntitlement() async {
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let t) = result,
               Self.productIDs.contains(t.productID),
               t.revocationDate == nil {
                active = true
            }
        }
        storeKitEntitled = active
        recompute()
    }

    private func handle(_ verification: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = verification else { return } // ignore unverified
        if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
            storeKitEntitled = true
            recompute()
        } else {
            await refreshStoreKitEntitlement() // revocation / expiry / refund — re-derive
        }
        await mirror(transaction)
        await transaction.finish()
    }

    /// Best-effort: tell the backend about the verified purchase so the web dashboard and other
    /// devices reflect it. Non-fatal if the endpoint isn't live yet — the client already gates
    /// the UI locally from StoreKit.
    private func mirror(_ transaction: StoreKit.Transaction) async {
        guard let token = try? await auth.validAccessToken() else { return }
        await ClarionAPI.mirrorIAPPurchase(transactionJSON: transaction.jsonRepresentation, accessToken: token)
    }

    private func recompute() {
        entitled = serverEntitled || storeKitEntitled
    }
}
