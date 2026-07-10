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

    /// TODO(Phase 1.5): fetch the real persona from the web profile at sign-in
    /// (profile_type / menopause_stage / sex). Endurance is the founder-beachhead default.
    @AppStorage("clarion_persona") private var personaRaw = Persona.endurance.rawValue

    var persona: Persona { Persona(rawValue: personaRaw) ?? .general }

    var body: some View {
        if auth.isSignedIn {
            HomeView(persona: persona)
                .task {
                    // Re-register observers every launch — registrations don't survive relaunch.
                    HealthStore.shared.registerBackgroundSync(persona: persona) {
                        Task { await sync.sync() }
                    }
                }
        } else {
            SignInView()
        }
    }
}
