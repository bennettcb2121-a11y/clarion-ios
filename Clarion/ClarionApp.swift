import SwiftUI

@main
struct ClarionApp: App {
    @StateObject private var auth: SupabaseAuth
    @StateObject private var sync: SyncCoordinator

    init() {
        let auth = SupabaseAuth()
        _auth = StateObject(wrappedValue: auth)
        _sync = StateObject(wrappedValue: SyncCoordinator(auth: auth))
        Self.applyBrandChrome()
        #if DEBUG
        // No test target in this project — the daily-loop logic verifies itself with
        // an assertion block on every debug launch (a failure crashes immediately).
        DailyLoopSelfTests.run()
        #endif
    }

    /// New York serif 600 (the display role) for a UIKit context, per clarion-tokens.json.
    private static func serifTitleFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Brand the system chrome once: display-serif large titles everywhere — the biggest
    /// glyphs on every screen should be the most Clarion.
    private static func applyBrandChrome() {
        let ink = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: 0xF3F6F4) : UIColor(hex: 0x16201C)
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [
            .font: serifTitleFont(size: 32),
            .foregroundColor: ink,
            .kern: -0.48, // -0.015em at 32pt, per the spec's display letterSpacing
        ]
        nav.titleTextAttributes = [
            .font: serifTitleFont(size: 17),
            .foregroundColor: ink,
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(sync)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var sync: SyncCoordinator
    @StateObject private var report: ReportStore
    @StateObject private var protocolLog: ProtocolLogStore

    init() {
        // These stores need auth; RootView is created inside the auth-provided environment, but
        // StateObject init can't read @EnvironmentObject, so build them from fresh SupabaseAuth
        // instances that share the same Keychain-persisted session.
        _report = StateObject(wrappedValue: ReportStore(auth: SupabaseAuth()))
        _protocolLog = StateObject(wrappedValue: ProtocolLogStore(auth: SupabaseAuth()))
    }

    /// Cached across launches so permission scoping is right before the network returns;
    /// refreshed from /api/account/persona on every sign-in.
    @AppStorage("clarion_persona") private var personaRaw = Persona.general.rawValue

    var persona: Persona { Persona(rawValue: personaRaw) ?? .general }

    /// DEBUG-only: launch with `UITEST_VITALS` to render the app shell (Vitals tab first) without
    /// a live session, so the dashboard can be screenshotted in the simulator (demo fallback).
    private var uiTestVitals: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("UITEST_VITALS")
        #else
        return false
        #endif
    }

    @State private var tab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if auth.isSignedIn || uiTestVitals {
            // Tab order (and the DEBUG `TAB=<n>` screenshot arg): 0 Home · 1 Vitals ·
            // 2 Report · 3 Plan · 4 Shop. Settings lives behind the gear in Home's nav
            // bar; the Library is a quiet entry card on Home.
            TabView(selection: $tab) {
                HomeView(persona: persona, report: report, log: protocolLog, tab: $tab)
                    .tabItem { Label("Home", systemImage: "house") }.tag(0)
                VitalsView(auth: auth)
                    .tabItem { Label("Vitals", systemImage: "waveform.path.ecg") }.tag(1)
                ReportView(store: report)
                    .tabItem { Label("Report", systemImage: "drop") }.tag(2)
                PlanView(store: report, log: protocolLog)
                    .tabItem { Label("Plan", systemImage: "pills") }.tag(3)
                ShopView(auth: auth)
                    .tabItem { Label("Shop", systemImage: "bag") }.tag(4)
            }
            // One consistent outline weight for every tab icon — no auto-fill on selection
            // (the mixed filled/outline set was the most persistent generic element).
            .environment(\.symbolVariants, .none)
            .tint(Color.forest)
            .onChange(of: tab) { _, _ in Haptics.selection() }
            .onChange(of: scenePhase) { _, phase in
                // Daily-freshness guarantee: whenever the app comes to the foreground and the
                // last sync is older than 6 hours, sync automatically — no button required.
                guard phase == .active, auth.isSignedIn else { return }
                let last = sync.lastSyncedAt ?? .distantPast
                if Date().timeIntervalSince(last) > 6 * 3600 {
                    Task { await sync.sync() }
                }
            }
            .onAppear {
                if uiTestVitals {
                    // Optional `TAB=<n>` launch arg picks the starting tab for screenshots
                    // (new order: 0 Home · 1 Vitals · 2 Report · 3 Plan · 4 Shop). The
                    // off-tab surfaces get their own args, handled inside HomeView:
                    // UITEST_SETTINGS / UITEST_LIBRARY (pushes) and UITEST_CHAT (sheet).
                    let tabArg = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("TAB=") }
                    tab = tabArg.flatMap { Int($0.dropFirst(4)) } ?? 1
                }
            }
            .task {
                await refreshPersona()
                // Re-register observers every launch — registrations don't survive relaunch.
                HealthStore.shared.registerBackgroundSync(persona: persona) {
                    Task { await sync.sync() }
                }
            }
        } else {
            SignInView()
        }
    }

    private func refreshPersona() async {
        guard let token = try? await auth.validAccessToken() else { return }
        let fetched = await ClarionAPI.fetchPersona(accessToken: token)
        personaRaw = fetched.rawValue
    }
}
