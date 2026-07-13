import SwiftUI
import UIKit

/// The Library front door — one screen linking the five reference surfaces:
/// Labs history, Biomarkers, Daily inputs, Logbook, and Guides. Owns their
/// stores (built from the injected auth, mirroring RootView's pattern) so each
/// child loads lazily on first visit and survives navigation.
///
/// Wire-up note: instantiate as `LibraryHomeView(auth: auth)` from the app
/// chrome (a tab, a Home link, or a toolbar button) — this file deliberately
/// does not touch ClarionApp/HomeView.
struct LibraryHomeView: View {
    private let auth: SupabaseAuth
    @StateObject private var labs: LabsHistoryStore
    @StateObject private var report: ReportStore
    @StateObject private var metrics: DailyMetricsStore
    @StateObject private var logbook: LogbookStore

    init(auth: SupabaseAuth) {
        self.auth = auth
        _labs = StateObject(wrappedValue: LabsHistoryStore(auth: auth))
        _report = StateObject(wrappedValue: ReportStore(auth: auth))
        _metrics = StateObject(wrappedValue: DailyMetricsStore(auth: auth))
        _logbook = StateObject(wrappedValue: LogbookStore(auth: auth))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Brand.s3) {
                    row(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Labs history",
                        caption: "Every panel on file, and how each marker moved between draws.",
                        index: 0
                    ) {
                        LabsHistoryView(store: labs, auth: auth)
                    }
                    row(
                        icon: "drop",
                        title: "Biomarkers",
                        caption: "All your markers against personalized and standard lab ranges.",
                        index: 1
                    ) {
                        BiomarkersView(store: report)
                    }
                    row(
                        icon: "sun.max",
                        title: "Daily inputs",
                        caption: "Sleep, sunlight, hydration, training — the things a wearable can't know.",
                        index: 2
                    ) {
                        DailyInputsView(store: metrics)
                    }
                    row(
                        icon: "calendar",
                        title: "Logbook",
                        caption: "Your day-by-day record: doses, lab days, and the next retest.",
                        index: 3
                    ) {
                        LogbookView(store: logbook, report: report)
                    }
                    row(
                        icon: "book",
                        title: "Guides",
                        caption: "Short, sourced reads on moving the markers that matter.",
                        index: 4
                    ) {
                        GuidesView(auth: auth)
                    }
                }
                .padding(Brand.s5)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Library")
        }
    }

    private func row<Destination: View>(
        icon: String,
        title: String,
        caption: String,
        index: Int,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Brand.s4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.forest)
                    .frame(width: 40, height: 40)
                    .background(Color.forestWash, in: RoundedRectangle(cornerRadius: Brand.rSM))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.clarionDisplay(17))
                        .tracking(-0.015 * 17)
                        .foregroundStyle(Color.ink)
                    Text(caption)
                        .font(.clarionBody(12.5))
                        .foregroundStyle(Color.ink3)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink4)
            }
            .padding(Brand.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard()
        }
        .buttonStyle(PressableStyle())
        .entrance(index)
    }
}

// MARK: - Web handoff

/// One shared web-opening helper for the Library surfaces, mirroring
/// HomeView.openWeb: /dashboard paths (no query) mint a one-time signed-in
/// login link; everything else — /labs/upload, /guides/*, query-string paths —
/// opens the plain production URL (the app-login-link whitelist only accepts
/// bare /dashboard sub-paths).
enum LibraryWeb {
    @MainActor
    static func open(path: String, auth: SupabaseAuth) async {
        let fallback = URL(string: Config.apiBase.absoluteString + path) ?? Config.apiBase
        let canMint = path.hasPrefix("/dashboard") && !path.contains("?")
        guard canMint, let token = try? await auth.validAccessToken() else {
            await UIApplication.shared.open(fallback)
            return
        }
        let url = (try? await ClarionAPI.dashboardLoginLink(path: path, accessToken: token)) ?? fallback
        await UIApplication.shared.open(url)
    }
}
