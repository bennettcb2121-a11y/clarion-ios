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

    /// Cached across launches so permission scoping is right before the network returns;
    /// refreshed from /api/account/persona on every sign-in.
    @AppStorage("clarion_persona") private var personaRaw = Persona.general.rawValue

    var persona: Persona { Persona(rawValue: personaRaw) ?? .general }

    var body: some View {
        if auth.isSignedIn {
            HomeView(persona: persona)
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
