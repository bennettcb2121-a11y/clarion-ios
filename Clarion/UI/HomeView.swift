import SwiftUI

/// The app: permission primer (first run), Today card of just-synced persona metrics
/// (guideline 4.2's "minimum functionality" defense AND the visible use of every requested
/// HealthKit type), sync status, and the door to the full dashboard on the web.
struct HomeView: View {
    let persona: Persona

    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var sync: SyncCoordinator
    @AppStorage("clarion_health_authorized") private var healthAuthorized = false
    @State private var requestingAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !HealthStore.isAvailable {
                        card {
                            Text("Health data isn't available on this device.")
                                .foregroundStyle(.secondary)
                        }
                    } else if !healthAuthorized {
                        connectCard
                    } else {
                        todayCard
                        syncCard
                    }
                    dashboardLink
                }
                .padding(20)
            }
            .navigationTitle("Clarion")
            .toolbar {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            .refreshable { await sync.sync() }
        }
    }

    // MARK: - Connect (permission primer BEFORE the system sheet)

    private var connectCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect Apple Health")
                    .font(.headline)
                Text(PersonaScopes.primerCopy(for: persona))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await requestHealthAccess() }
                } label: {
                    if requestingAuth {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Connect").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(requestingAuth)
            }
        }
    }

    private func requestHealthAccess() async {
        requestingAuth = true
        do {
            try await HealthStore.shared.requestAuthorization(persona: persona)
            healthAuthorized = true
            await sync.sync()
        } catch {
            // Read-authorization status is intentionally opaque in HealthKit; if the user
            // denied everything the sync simply finds no data — never hard-gate on the sheet.
            healthAuthorized = true
            await sync.sync()
        }
        requestingAuth = false
    }

    // MARK: - Today

    private var todayCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Today")
                    .font(.headline)
                if let today = sync.lastSummary.last {
                    HStack(spacing: 18) {
                        metric("HRV", today.hrv.map { "\(Int($0)) ms" })
                        metric("Resting HR", today.restingHeartRate.map { "\(Int($0)) bpm" })
                        metric("Sleep", today.sleepDurationMin.map { formatMinutes($0) })
                    }
                    if persona == .menopause, let temp = today.skinTempDeviationC {
                        metric("Overnight temp", String(format: "%+.2f °C vs baseline", temp))
                    }
                    if persona == .endurance, let vo2 = today.vo2Max {
                        metric("VO₂max", String(format: "%.1f", vo2))
                    }
                } else {
                    Text("Sync to see today's numbers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatMinutes(_ min: Double) -> String {
        let h = Int(min) / 60
        let m = Int(min) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: - Sync status

    private var syncCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                switch sync.status {
                case .idle:
                    if let last = sync.lastSyncedAt {
                        Label("Synced \(last.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Not synced yet", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    }
                case .syncing:
                    Label { Text("Syncing…") } icon: { ProgressView() }
                case .done(let daily, let workouts, let at):
                    Label(
                        "Synced \(daily) days, \(workouts) workouts · \(at.formatted(date: .omitted, time: .shortened))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                Button("Sync now") {
                    Task { await sync.sync() }
                }
                .buttonStyle(.bordered)
                .disabled(sync.status == .syncing)
            }
        }
    }

    // MARK: - Dashboard door

    private var dashboardLink: some View {
        // Opens REAL Safari (not SFSafariViewController — per-app isolated storage means an
        // in-app browser would NOT share the user's signed-in web session). Phase 2: replace
        // with a magic-link handoff endpoint so this lands signed-in every time.
        Button {
            UIApplication.shared.open(Config.apiBase.appendingPathComponent("dashboard/vitals"))
        } label: {
            Label("Full analysis on clarionlabs.tech", systemImage: "arrow.up.forward.app")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}
