import SwiftUI
import StoreKit

/// The membership wall on the analysis surfaces (Report, Plan, Labs history, Biomarkers) for a
/// non-entitled account. Now a real, compliant paywall: Clarion+ is a DIGITAL subscription, so
/// it's sold through Apple In-App Purchase (Guideline 3.1.1) — buy buttons per plan + a required
/// Restore path. A secondary "already a member on the web?" link opens account settings (never a
/// web checkout). Physical goods (Shop) and the daily loop stay open regardless.
struct MembershipWall: View {
    /// Lowercase name of the surface being walled, e.g. "report", "plan".
    let surface: String

    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var subscription: SubscriptionStore
    @State private var opening = false

    var body: some View {
        VStack(spacing: Brand.s4) {
            Image(systemName: "lock")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.forest)
                .frame(width: 48, height: 48)
                .background(Color.forestWash, in: Circle())

            VStack(spacing: Brand.s2) {
                Eyebrow("Clarion+", color: .forest)
                Text("Unlock your \(surface) with Clarion+")
                    .font(.clarionDisplay(21))
                    .tracking(-0.015 * 21)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text("Clarion+ covers the analysis side of Clarion — your report, plan, labs history, and biomarker library, all matched to your bloodwork.")
                    .font(.clarionBody(14.5))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Purchase options — one button per plan, cheapest first.
            if subscription.products.isEmpty {
                // Products haven't loaded (offline, or not yet live in App Store Connect).
                Text("Membership options are loading…")
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
                    .padding(.vertical, Brand.s2)
            } else {
                VStack(spacing: Brand.s2 + 2) {
                    ForEach(subscription.products, id: \.id) { product in
                        Button {
                            Haptics.commit()
                            Task { await subscription.purchase(product) }
                        } label: {
                            HStack(spacing: 6) {
                                Text("\(planTitle(product)) · \(product.displayPrice)")
                                if let unit = periodLabel(product) {
                                    Text("/ \(unit)")
                                        .foregroundStyle(Color.forestInk.opacity(0.7))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(subscription.purchasing)
                    }
                }
            }

            if subscription.purchasing {
                ProgressView().controlSize(.small)
            }

            // Apple requires a restore path for subscriptions.
            Button("Restore purchases") {
                Haptics.tap()
                Task { await subscription.restore() }
            }
            .font(.clarionLabel(13))
            .foregroundStyle(Color.forest)
            .disabled(subscription.purchasing)

            // Secondary: existing web members manage their account (not a checkout).
            Button {
                Haptics.tap()
                Task { await openManage() }
            } label: {
                Text(opening ? "Opening…" : "Already a member? Manage account")
                    .font(.clarionBody(12.5))
                    .foregroundStyle(Color.ink3)
            }
            .disabled(opening)

            Text("Auto-renews until cancelled. Manage or cancel anytime in your Apple ID settings. Today's doses, vitals, and the shop stay available here.")
                .font(.clarionBody(11))
                .foregroundStyle(Color.ink4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Brand.s6)
        .frame(maxWidth: .infinity)
        .clarionCard()
        .padding(Brand.s5)
        .padding(.top, Brand.s6)
        .entrance(0)
        .task { await subscription.loadProducts() }
    }

    /// "Monthly" / "Annual" from the product (falls back to the display name).
    private func planTitle(_ product: Product) -> String {
        switch product.id {
        case SubscriptionStore.Plan.monthly.rawValue: return "Monthly"
        case SubscriptionStore.Plan.annual.rawValue: return "Annual"
        default: return product.displayName
        }
    }

    /// "month" / "year" from the subscription period.
    private func periodLabel(_ product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .day: return period.value == 7 ? "week" : "day"
        case .week: return "week"
        case .month: return period.value == 12 ? "year" : "month"
        case .year: return "year"
        @unknown default: return nil
        }
    }

    /// Signed-in handoff to account settings on the web (never a checkout page).
    private func openManage() async {
        opening = true
        defer { opening = false }
        await LibraryWeb.open(path: "/dashboard/settings", auth: auth)
    }
}
