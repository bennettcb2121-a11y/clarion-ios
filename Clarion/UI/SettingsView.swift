import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SupabaseAuth

    var body: some View {
        List {
            Section("Account") {
                if let email = auth.session?.email {
                    LabeledContent("Signed in as", value: email)
                }
                Button("Sign out", role: .destructive) {
                    auth.signOut()
                }
            }

            Section("Health data") {
                // HealthKit read-permissions are managed in the system Health app.
                Link(
                    "Manage Health permissions",
                    destination: URL(string: "x-apple-health://")!
                )
                Text("Clarion only reads the metrics relevant to your goals, and never uses health data for advertising.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy & legal") {
                Link("Privacy policy", destination: Config.apiBase.appendingPathComponent("legal/privacy"))
                Link("Health data privacy", destination: Config.apiBase.appendingPathComponent("legal/health-data-privacy"))
                Link("Terms of service", destination: Config.apiBase.appendingPathComponent("terms"))
            }

            Section {
                // App Review requires account deletion be reachable in-app.
                // Phase 2: replace with a native flow calling /api/account/delete (+ SIWA
                // token revocation once Sign in with Apple ships).
                Link("Delete my account", destination: Config.apiBase.appendingPathComponent("settings"))
                    .foregroundStyle(.red)
            } footer: {
                Text("Deleting your account removes your labs, wearable data, and profile from Clarion.")
            }
        }
        .navigationTitle("Settings")
    }
}
