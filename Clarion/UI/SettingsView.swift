import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteError: String?

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
                Link("Manage Health permissions", destination: URL(string: "x-apple-health://")!)
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
                // App Review requires account deletion be INITIABLE in-app — this is the native
                // flow (POSTs /api/account/delete with the user's bearer token), not a web link.
                Button("Delete my account", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(deleting)
                if let deleteError {
                    Text(deleteError).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text("Permanently removes your labs, wearable data, and profile from Clarion. This can't be undone.")
            }
        }
        .navigationTitle("Settings")
        .overlay {
            if deleting { ProgressView("Deleting…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
        }
        .confirmationDialog(
            "Delete your Clarion account?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your labs, wearable data, and profile. It can't be undone.")
        }
    }

    private func deleteAccount() async {
        deleting = true
        deleteError = nil
        do {
            let token = try await auth.validAccessToken()
            try await ClarionAPI.deleteAccount(accessToken: token)
            auth.signOut() // account is gone; clear the local session
        } catch {
            deleteError = error.localizedDescription
        }
        deleting = false
    }
}
