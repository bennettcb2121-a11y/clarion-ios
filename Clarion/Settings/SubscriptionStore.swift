import Foundation
import SwiftUI

/// Clarion+ entitlement — the app-side mirror of the web's `hasDashboardShellAccess`
/// (src/lib/accessGate.ts): a user is entitled when ANY of the three legs holds —
///   1. `analysis_purchased_at` on the profile (the $49 / code analysis unlock),
///   2. a Stripe subscription in `active` / `trialing` / `past_due`
///      (past_due still grants access — the invoice may just be catching up),
///   3. webhook-synced `plan_tier` of `full` or `lite`.
///
/// The rule of the store is FAIL OPEN: only a definitive 200 that says "no" on all
/// three legs locks the analysis surfaces. Network errors, 404s (older prod), 401s,
/// and decode surprises keep the last-known answer — a paying member is never locked
/// out because prod lagged. The last definitive answer is cached in UserDefaults so
/// a cold offline launch behaves like the previous session.
@MainActor
final class SubscriptionStore: ObservableObject {

    /// Whether the analysis surfaces (Report, Plan, Labs history, Biomarkers) render.
    /// Home, Vitals, Shop, and Settings never consult this.
    @Published private(set) var entitled: Bool

    private let auth: SupabaseAuth
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
        // Seed from the last definitive answer; a fresh install starts open.
        if UserDefaults.standard.object(forKey: Self.cacheKey) == nil {
            entitled = true
        } else {
            entitled = UserDefaults.standard.bool(forKey: Self.cacheKey)
        }
        #if DEBUG
        // Screenshot harness: force the membership wall without a real non-member account.
        if ProcessInfo.processInfo.arguments.contains("UITEST_LOCKED") { entitled = false }
        #endif
    }

    /// The web's `subscriptionStatusGrantsAccess`, verbatim.
    static func statusGrantsAccess(_ status: String?) -> Bool {
        let s = (status ?? "").lowercased()
        return s == "active" || s == "trialing" || s == "past_due"
    }

    /// Refresh from the server. Call on launch and on foreground — cheap, and the
    /// answer usually doesn't change.
    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_LOCKED") {
            entitled = false
            return
        }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") }) {
            entitled = true
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
                set(true)
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
                set(true)
            } else {
                set(false) // every leg answered no — this is the one path that locks
            }
        } catch {
            return // couldn't verify the last leg — fail open, keep last known
        }
    }

    private func set(_ value: Bool) {
        entitled = value
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
    }
}
