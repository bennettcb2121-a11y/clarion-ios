import SwiftUI

/// Home is the daily front door — a readiness-first snapshot of just-synced persona metrics,
/// sync state, and the door onward. Pre-connect it earns the permission with a persona-scoped
/// primer above a preview of what's coming (never a blank void).
struct HomeView: View {
    let persona: Persona

    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var sync: SyncCoordinator
    @AppStorage("clarion_health_authorized") private var healthAuthorized = false
    @State private var requestingAuth = false
    @State private var openingDashboard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if !HealthStore.isAvailable {
                        card {
                            Text("Health data isn't available on this device.")
                                .foregroundStyle(Color.inkMuted)
                        }
                    } else if !healthAuthorized {
                        connectCard.entrance(0)
                        previewSkeleton.entrance(1)
                    } else {
                        todayCard.entrance(0)
                        syncRow.entrance(1)
                    }
                    webFooter.entrance(2)
                }
                .padding(20)
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Clarion")
            .refreshable {
                Haptics.touch()
                await sync.sync()
                Haptics.success()
            }
        }
    }

    // MARK: - Connect (permission primer BEFORE the system sheet)

    private var connectCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect Apple Health")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(Color.ink)
                Text(PersonaScopes.primerCopy(for: persona))
                    .font(.subheadline)
                    .foregroundStyle(Color.inkMuted)
                Button {
                    Task { await requestHealthAccess() }
                } label: {
                    if requestingAuth {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text("Connect").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(requestingAuth)
            }
        }
    }

    /// What's coming once they connect — greyed preview tiles instead of a blank screen.
    private var previewSkeleton: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("WHAT YOU'LL SEE")
                    .font(.system(size: 12, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(Color.inkMuted)
                HStack(spacing: 18) {
                    previewMetric("Readiness", "82")
                    previewMetric("HRV", "78 ms")
                    previewMetric("Sleep", "7h 20m")
                }
                Text("Your recovery, sleep, and training — connected to your bloodwork.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .opacity(0.75)
    }

    private func previewMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(Color.inkMuted)
                .redacted(reason: .placeholder)
            Text(label).font(.caption).foregroundStyle(Color.inkMuted)
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

    // MARK: - Today (the daily snapshot)

    private var todayCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Today")
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    if let last = sync.lastSyncedAt {
                        Text("synced \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                if let today = sync.lastSummary.last {
                    HStack(spacing: 22) {
                        bigMetric("Readiness", today.readinessScore.map { "\(Int($0))" })
                        bigMetric("HRV", today.hrv.map { "\(Int($0)) ms" })
                        bigMetric("Sleep", today.sleepDurationMin.map { formatMinutes($0) })
                    }
                    if persona == .menopause, let temp = today.skinTempDeviationC {
                        bigMetric("Overnight temp", String(format: "%+.2f °C vs baseline", temp))
                    }
                    if persona == .endurance, let vo2 = today.vo2Max {
                        bigMetric("VO₂max", String(format: "%.1f", vo2))
                    }
                } else {
                    Text("Pull to sync and see today's numbers.")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
    }

    private func bigMetric(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—")
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.inkMuted)
        }
    }

    private func formatMinutes(_ min: Double) -> String {
        let h = Int(min) / 60
        let m = Int(min) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: - Sync state (one quiet row, not a card of chrome)

    private var syncRow: some View {
        card {
            HStack(spacing: 10) {
                switch sync.status {
                case .idle:
                    Image(systemName: sync.lastSyncedAt == nil ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .foregroundStyle(Color.forest)
                    Text(sync.lastSyncedAt == nil ? "Not synced yet" : "Everything up to date")
                        .font(.subheadline).foregroundStyle(Color.inkMuted)
                case .syncing:
                    ProgressView().controlSize(.small)
                    Text("Syncing…").font(.subheadline).foregroundStyle(Color.inkMuted)
                case .done(let daily, let workouts, _):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.forest)
                    Text("Synced \(daily) days, \(workouts) workouts")
                        .font(.subheadline).foregroundStyle(Color.inkMuted)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.amber)
                    Text(message).font(.subheadline).foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Button("Sync") {
                    Haptics.commit()
                    Task { await sync.sync() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.forestInk)
                .buttonStyle(PressableStyle())
                .disabled(sync.status == .syncing)
            }
        }
    }

    // MARK: - The web, demoted to a quiet footer

    private var webFooter: some View {
        Button {
            Task { await openDashboard() }
        } label: {
            Text(openingDashboard ? "Opening…" : "Full analysis on clarionlabs.tech ↗")
                .font(.footnote)
                .foregroundStyle(Color.inkMuted)
        }
        .buttonStyle(PressableStyle())
        .disabled(openingDashboard)
        .padding(.top, 4)
    }

    private func openDashboard() async {
        openingDashboard = true
        defer { openingDashboard = false }
        let fallback = Config.apiBase.appendingPathComponent("dashboard/vitals")
        guard let token = try? await auth.validAccessToken() else {
            await UIApplication.shared.open(fallback)
            return
        }
        let url = (try? await ClarionAPI.dashboardLoginLink(path: "/dashboard/vitals", accessToken: token)) ?? fallback
        await UIApplication.shared.open(url)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .clarionCard()
    }
}
