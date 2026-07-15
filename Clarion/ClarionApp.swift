import SwiftUI

@main
struct ClarionApp: App {
    @StateObject private var auth: SupabaseAuth
    @StateObject private var sync: SyncCoordinator

    init() {
        let auth = SupabaseAuth()
        _auth = StateObject(wrappedValue: auth)
        _sync = StateObject(wrappedValue: SyncCoordinator(auth: auth))
        Fonts.registerBundled()   // must precede applyBrandChrome so nav titles get Fraunces
        Self.applyBrandChrome()
        #if DEBUG
        // No test target in this project — the daily-loop logic verifies itself with
        // an assertion block on every debug launch (a failure crashes immediately).
        DailyLoopSelfTests.run()
        #endif
    }

    /// Bundled Fraunces SemiBold (the display role) for a UIKit context — falls back to
    /// the system serif if the face didn't register. Per clarion-tokens.json.
    private static func serifTitleFont(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        Fonts.display(size)
    }

    /// Brand the system chrome once: display-serif large titles everywhere — the biggest
    /// glyphs on every screen should be the most Clarion — plus the tab bar's serif labels.
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

        applyTabBarChrome()
    }

    /// Tab bar, treatment B — "serif labels". The five tab titles carry the same New York serif
    /// face as the nav titles (via `.withDesign(.serif)`), small (10pt), so even the smallest
    /// chrome speaks in the brand voice. Selected = forest icon + forest serif label; inactive =
    /// muted ink. Kept in sync with the `.tint(.forest)` + `symbolVariants(.none)` on the TabView.
    private static func applyTabBarChrome() {
        let forest = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: 0x2A8C72) : UIColor(hex: 0x1F6F5B)
        }
        // ink3 — the muted caption tone (dark mode is an alpha of the light-ink foreground).
        let muted = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: 0xF3F6F4, alpha: 0.50) : UIColor(hex: 0x79827D)
        }
        let serif = serifTitleFont(size: 10, weight: .medium)

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        func style(_ item: UITabBarItemAppearance) {
            item.normal.iconColor = muted
            item.normal.titleTextAttributes = [.font: serif, .foregroundColor: muted]
            item.selected.iconColor = forest
            item.selected.titleTextAttributes = [.font: serif, .foregroundColor: forest]
        }
        style(appearance.stackedLayoutAppearance)
        style(appearance.inlineLayoutAppearance)
        style(appearance.compactInlineLayoutAppearance)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
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
    @StateObject private var subscription: SubscriptionStore

    init() {
        // These stores need auth; RootView is created inside the auth-provided environment, but
        // StateObject init can't read @EnvironmentObject, so build them from fresh SupabaseAuth
        // instances that share the same Keychain-persisted session.
        _report = StateObject(wrappedValue: ReportStore(auth: SupabaseAuth()))
        _protocolLog = StateObject(wrappedValue: ProtocolLogStore(auth: SupabaseAuth()))
        _subscription = StateObject(wrappedValue: SubscriptionStore(auth: SupabaseAuth()))
    }

    /// Cached across launches so permission scoping is right before the network returns;
    /// refreshed from /api/account/persona on every sign-in.
    @AppStorage("clarion_persona") private var personaRaw = Persona.general.rawValue

    var persona: Persona {
        #if DEBUG
        // Screenshot harness: `UITEST_PERSONA=endurance|strength|menopause|general` forces the
        // persona so Home's smart-default adaptivity can be captured without a live profile.
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("UITEST_PERSONA=") }),
           let forced = Persona(rawValue: String(arg.dropFirst("UITEST_PERSONA=".count))) {
            return forced
        }
        #endif
        return Persona(rawValue: personaRaw) ?? .general
    }

    /// DEBUG-only: launch with `UITEST_VITALS` to render the app shell (Vitals tab first) without
    /// a live session, so the dashboard can be screenshotted in the simulator (demo fallback).
    private var uiTestVitals: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("UITEST_VITALS")
        #else
        return false
        #endif
    }

    /// DEBUG-only: `UITEST_WEB` renders the app shell starting on the Report tab —
    /// a web surface — so it can be screenshotted in the simulator. Without a real
    /// device session it shows the web login/embed shell, which is expected.
    private var uiTestWeb: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("UITEST_WEB")
        #else
        return false
        #endif
    }

    @State private var tab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if auth.isSignedIn || uiTestVitals || uiTestWeb {
            // Tab order (and the DEBUG `TAB=<n>` screenshot arg): 0 Home · 1 Vitals ·
            // 2 Report · 3 Plan · 4 Shop. Settings lives behind the gear in Home's nav
            // bar; the Library is a destination grid on Home plus a toolbar icon.
            TabView(selection: $tab) {
                HomeView(persona: persona, report: report, log: protocolLog, tab: $tab)
                    .tabItem { Label("Home", systemImage: "house") }.tag(0)
                VitalsView(auth: auth)
                    .tabItem { Label("Vitals", systemImage: "waveform.path.ecg") }.tag(1)
                // Report / Plan / Shop are the REAL signed-in web pages in a WKWebView —
                // the native reconstructions drifted from the live site and failed to load
                // data. Each tab supplies its own NavigationStack so the web surface (which
                // only sets a title) gets a native nav bar. Home + Vitals stay native.
                NavigationStack {
                    ClarionWebSurface(auth: auth, path: "/dashboard/analysis", title: "Report")
                }
                .tabItem { Label("Report", systemImage: "doc.text") }.tag(2)
                NavigationStack {
                    ClarionWebSurface(auth: auth, path: "/dashboard/plan", title: "Plan")
                }
                .tabItem { Label("Plan", systemImage: "checklist") }.tag(3)
                NavigationStack {
                    ClarionWebSurface(auth: auth, path: "/dashboard/shop", title: "Shop")
                }
                .tabItem { Label("Shop", systemImage: "bag") }.tag(4)
            }
            // One consistent outline weight for every tab icon — no auto-fill on selection
            // (the mixed filled/outline set was the most persistent generic element).
            .environment(\.symbolVariants, .none)
            .environmentObject(subscription)
            .tint(Color.forest)
            .onChange(of: tab) { _, _ in Haptics.selection() }
            .onChange(of: scenePhase) { _, phase in
                // Daily-freshness guarantee: whenever the app comes to the foreground and the
                // last sync is older than 6 hours, sync automatically — no button required.
                guard phase == .active, auth.isSignedIn else { return }
                // Entitlement is cheap to re-check and fails open — every foreground.
                Task { await subscription.refresh() }
                let last = sync.lastSyncedAt ?? .distantPast
                if Date().timeIntervalSince(last) > 6 * 3600 {
                    Task { await sync.sync() }
                }
            }
            .onAppear {
                if uiTestWeb {
                    // Start on the Report tab (a web surface) unless TAB= overrides.
                    let tabArg = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("TAB=") }
                    tab = tabArg.flatMap { Int($0.dropFirst(4)) } ?? 2
                } else if uiTestVitals {
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
                await subscription.refresh()
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
