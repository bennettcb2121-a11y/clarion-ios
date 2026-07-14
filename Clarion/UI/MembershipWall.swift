import SwiftUI

/// The membership wall — what a non-entitled account sees on the analysis surfaces
/// (Report, Plan, Labs history, Biomarkers). Deliberately NOT a paywall: no price,
/// no purchase button, no in-app checkout. Just an honest explanation and a plain
/// manage-account link out to clarionlabs.tech (App Store-compliant steering: a
/// manage link, nothing more). Physical goods (Shop) and the daily loop stay open.
struct MembershipWall: View {
    /// Lowercase name of the surface being walled, e.g. "report", "plan".
    let surface: String

    @EnvironmentObject private var auth: SupabaseAuth
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
                Text("Your \(surface) lives in Clarion+")
                    .font(.clarionDisplay(21))
                    .tracking(-0.015 * 21)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text("Clarion+ membership covers the analysis side of Clarion — your report, plan, labs history, and biomarker library. This account isn't showing an active membership right now.")
                    .font(.clarionBody(14.5))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Haptics.tap()
                Task { await openManage() }
            } label: {
                HStack(spacing: 5) {
                    Text(opening ? "Opening…" : "Manage on clarionlabs.tech")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(opening)

            Text("Today's doses, vitals, and the shop stay available here.")
                .font(.clarionBody(12))
                .foregroundStyle(Color.ink4)
                .multilineTextAlignment(.center)
        }
        .padding(Brand.s6)
        .frame(maxWidth: .infinity)
        .clarionCard()
        .padding(Brand.s5)
        .padding(.top, Brand.s6)
        .entrance(0)
    }

    /// Signed-in handoff to account settings on the web (never a checkout page).
    private func openManage() async {
        opening = true
        defer { opening = false }
        await LibraryWeb.open(path: "/dashboard/settings", auth: auth)
    }
}
