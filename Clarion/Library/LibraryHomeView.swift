import SwiftUI
import UIKit

/// One reference surface inside the Library. Also the deep-link vocabulary: Home's
/// destination tiles jump straight to a surface (never to the hub), with the hub
/// kept underneath as the container — back-swipe lands on the full list.
enum LibraryDestination: Hashable {
    case labs, biomarkers, dailyInputs, logbook, guides, faq
}

/// The Library front door — one screen linking the six reference surfaces:
/// Labs history, Biomarkers, Daily inputs, Logbook, Guides, and FAQ. Owns their
/// stores (built from the injected auth, mirroring RootView's pattern) so each
/// child loads lazily on first visit and survives navigation.
///
/// Wire-up note: instantiate as `LibraryHomeView(auth: auth)` from the app
/// chrome (a tab, a Home link, or a toolbar button); pass `deepLink:` to open
/// with a surface already pushed (Home's grid tiles do).
struct LibraryHomeView: View {
    private let auth: SupabaseAuth
    @StateObject private var labs: LabsHistoryStore
    @StateObject private var report: ReportStore
    @StateObject private var metrics: DailyMetricsStore
    @StateObject private var logbook: LogbookStore
    @State private var path: [LibraryDestination]

    init(auth: SupabaseAuth, deepLink: LibraryDestination? = nil) {
        self.auth = auth
        _labs = StateObject(wrappedValue: LabsHistoryStore(auth: auth))
        _report = StateObject(wrappedValue: ReportStore(auth: auth))
        _metrics = StateObject(wrappedValue: DailyMetricsStore(auth: auth))
        _logbook = StateObject(wrappedValue: LogbookStore(auth: auth))
        _path = State(initialValue: deepLink.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Brand.s3) {
                    row(.labs,
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Labs history",
                        caption: "Every panel on file, and how each marker moved between draws.",
                        index: 0)
                    row(.biomarkers,
                        icon: "drop",
                        title: "Biomarkers",
                        caption: "All your markers against personalized and standard lab ranges.",
                        index: 1)
                    row(.dailyInputs,
                        icon: "sun.max",
                        title: "Daily inputs",
                        caption: "Sleep, sunlight, hydration, training — the things a wearable can't know.",
                        index: 2)
                    row(.logbook,
                        icon: "calendar",
                        title: "Logbook",
                        caption: "Your day-by-day record: doses, lab days, and the next retest.",
                        index: 3)
                    row(.guides,
                        icon: "book",
                        title: "Guides",
                        caption: "Short, sourced reads on moving the markers that matter.",
                        index: 4)
                    row(.faq,
                        icon: "questionmark.circle",
                        title: "FAQ & support",
                        caption: "Quick answers, and how to reach a human when you need one.",
                        index: 5)
                }
                .padding(Brand.s5)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationDestination(for: LibraryDestination.self) { dest in
                destinationView(dest)
            }
        }
    }

    /// The shared destination builder — the hub rows and Home's deep-link tiles land here.
    /// The content-heavy reference surfaces (Labs history, Biomarkers, Guides) render the
    /// REAL signed-in web pages via ClarionWebSurface — LibraryHomeView already owns the
    /// NavigationStack, so the surface just supplies its title + back button. Daily inputs
    /// and the Logbook stay NATIVE: they write through the native metrics/log APIs, and
    /// their write-path must keep working. FAQ stays native (static content).
    @ViewBuilder
    private func destinationView(_ dest: LibraryDestination) -> some View {
        switch dest {
        case .labs: LabsHistoryView(store: labs, auth: auth)
        case .biomarkers: BiomarkersView(store: report)
        case .dailyInputs: DailyInputsView(store: metrics)
        case .logbook: LogbookView(store: logbook, report: report)
        case .guides: ClarionWebSurface(auth: auth, path: "/guides", title: "Guides")
        case .faq: FAQView()
        }
    }

    private func row(
        _ destination: LibraryDestination,
        icon: String,
        title: String,
        caption: String,
        index: Int
    ) -> some View {
        NavigationLink(value: destination) {
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
