import SwiftUI

@main
struct ClarionApp: App {
    @StateObject private var auth: SupabaseAuth
    @StateObject private var sync: SyncCoordinator

    init() {
        let auth = SupabaseAuth()
        _auth = StateObject(wrappedValue: auth)
        _sync = StateObject(wrappedValue: SyncCoordinator(auth: auth))
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

    init() {
        // ReportStore needs auth; RootView is created inside the auth-provided environment, but
        // StateObject init can't read @EnvironmentObject, so build it from a fresh SupabaseAuth
        // that shares the same Keychain-persisted session.
        _report = StateObject(wrappedValue: ReportStore(auth: SupabaseAuth()))
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
            TabView(selection: $tab) {
                HomeView(persona: persona)
                    .tabItem { Label("Home", systemImage: "house") }.tag(0)
                VitalsView(auth: auth)
                    .tabItem { Label("Vitals", systemImage: "waveform.path.ecg") }.tag(1)
                ReportView(store: report)
                    .tabItem { Label("Report", systemImage: "drop") }.tag(2)
                PlanView(store: report)
                    .tabItem { Label("Plan", systemImage: "pills") }.tag(3)
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
            }
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
                    // Optional `TAB=<n>` launch arg picks the starting tab for screenshots.
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
