import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteError: String?

    private var email: String { auth.session?.email ?? "" }
    private var initials: String {
        let name = email.split(separator: "@").first.map(String.init) ?? "C"
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        List {
            // Identity first — a $200/yr membership should greet you by name, not with "Sign out".
            Section {
                HStack(spacing: 14) {
                    Text(initials)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Color.forestInk)
                        .frame(width: 52, height: 52)
                        .background(Color.forestWash, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email.isEmpty ? "Clarion member" : email)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text("Clarion member")
                            .font(.footnote)
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Link(destination: URL(string: "x-apple-health://")!) {
                    linkRow("Manage Health permissions", system: "heart.text.square")
                }
                Text("Clarion only reads the metrics relevant to your goals, and never uses health data for advertising.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkMuted)
            } header: {
                sectionHeader("Health data")
            }

            Section {
                Link(destination: Config.apiBase.appendingPathComponent("legal/privacy")) {
                    linkRow("Privacy policy", system: "lock")
                }
                Link(destination: Config.apiBase.appendingPathComponent("legal/health-data-privacy")) {
                    linkRow("Health data privacy", system: "cross.case")
                }
                Link(destination: Config.apiBase.appendingPathComponent("terms")) {
                    linkRow("Terms of service", system: "doc.text")
                }
            } header: {
                sectionHeader("Privacy & legal")
            }

            Section {
                Button("Sign out") {
                    Haptics.warning()
                    auth.signOut()
                }
                .foregroundStyle(Color.ink)
            } header: {
                sectionHeader("Account")
            }

            Section {
                Button("Delete my account", role: .destructive) {
                    Haptics.warning()
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
        .scrollContentBackground(.hidden)
        .background(Color.paper.ignoresSafeArea())
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

    /// External-link row: leading icon, ink label, trailing ↗ so it reads as a real row,
    /// not a web link pasted into a list.
    private func linkRow(_ title: String, system: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: system)
                .font(.system(size: 15))
                .foregroundStyle(Color.forest)
                .frame(width: 24)
            Text(title).foregroundStyle(Color.ink)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkMuted.opacity(0.6))
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Color.inkMuted)
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
