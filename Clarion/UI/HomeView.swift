import SwiftUI

/// Home is the daily front door: today's recovery snapshot, the single biggest lever from
/// your report, the next dose to take, and sync state. Pre-connect it earns the HealthKit
/// permission with a persona-scoped primer above a preview of what's coming.
struct HomeView: View {
    let persona: Persona
    @ObservedObject var report: ReportStore
    @ObservedObject var log: ProtocolLogStore
    @Binding var tab: Int

    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var sync: SyncCoordinator
    @AppStorage("clarion_health_authorized") private var healthAuthorized = false
    @State private var requestingAuth = false
    @State private var openingDashboard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Brand.s4) {
                    if !HealthStore.isAvailable {
                        card {
                            Text("Health data isn't available on this device.")
                                .font(.bodyFace(15))
                                .foregroundStyle(Color.ink3)
                        }
                    } else if !healthAuthorized {
                        connectCard.entrance(0)
                        previewSkeleton.entrance(1)
                    } else {
                        todayCard.entrance(0)
                        reportFlagCard.entrance(1)
                        nextDoseCard.entrance(2)
                        syncRow.entrance(3)
                    }
                    webFooter.entrance(4)
                }
                .padding(Brand.s5)
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Clarion")
            .refreshable {
                Haptics.touch()
                await sync.sync()
                await report.load()
                await log.load()
                Haptics.success()
            }
        }
        .task {
            if case .loading = report.state { await report.load() }
            await log.load()
        }
    }

    // MARK: - Connect (permission primer BEFORE the system sheet)

    private var connectCard: some View {
        card {
            VStack(alignment: .leading, spacing: Brand.s3) {
                Text("Connect Apple Health")
                    .font(.display(21, weight: 700))
                    .foregroundStyle(Color.ink)
                Text(PersonaScopes.primerCopy(for: persona))
                    .font(.bodyFace(15))
                    .foregroundStyle(Color.ink2)
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
            VStack(alignment: .leading, spacing: Brand.s4) {
                Eyebrow("What you'll see")
                HStack(spacing: Brand.s5) {
                    previewMetric("Readiness", "82")
                    previewMetric("HRV", "78 ms")
                    previewMetric("Sleep", "7h 20m")
                }
                Text("Your recovery, sleep, and training — connected to your bloodwork.")
                    .font(.bodyFace(13))
                    .foregroundStyle(Color.ink3)
            }
        }
        .opacity(0.75)
    }

    private func previewMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.display(19, weight: 700))
                .foregroundStyle(Color.ink3)
                .redacted(reason: .placeholder)
            Text(label).font(.bodyFace(12)).foregroundStyle(Color.ink3)
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
            VStack(alignment: .leading, spacing: Brand.s4) {
                HStack {
                    Text("Today")
                        .font(.display(21, weight: 700))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    if let last = sync.lastSyncedAt {
                        Text("synced \(last.formatted(.relative(presentation: .named)))")
                            .font(.bodyFace(12))
                            .foregroundStyle(Color.ink3)
                    }
                }
                if let today = sync.lastSummary.last {
                    HStack(spacing: Brand.s6) {
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
                        .font(.bodyFace(15))
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private func bigMetric(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—")
                .font(.data(22, weight: 600))
                .foregroundStyle(Color.ink)
            Text(label)
                .font(.bodyFace(12))
                .foregroundStyle(Color.ink3)
        }
    }

    private func formatMinutes(_ min: Double) -> String {
        let h = Int(min) / 60
        let m = Int(min) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: - The report's biggest lever

    @ViewBuilder
    private var reportFlagCard: some View {
        if case .ready(let r) = report.state, let results = r.results, !results.isEmpty {
            let score = ScoreEngine.score(results)
            let top = ScoreEngine.orderedDrivers(results, max: 1).first

            Button {
                Haptics.tap()
                tab = 2
            } label: {
                HStack(spacing: Brand.s4) {
                    ScoreDial(score: score, label: ScoreEngine.label(for: score), size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        if let top {
                            Eyebrow("Focus first", color: .forest)
                            Text("\(top.statusLabel) \(top.name)")
                                .font(.display(17, weight: 700))
                                .foregroundStyle(Color.ink)
                            if let gain = ScoreEngine.improvementForecast(results, fixing: top.name) {
                                Text("Worth +\(gain) points on your score.")
                                    .font(.bodyFace(13.5))
                                    .foregroundStyle(Color.ink2)
                            }
                        } else {
                            Eyebrow("Your report", color: .forest)
                            Text("Everything in range")
                                .font(.display(17, weight: 700))
                                .foregroundStyle(Color.ink)
                            Text("Your panel looks well-covered.")
                                .font(.bodyFace(13.5))
                                .foregroundStyle(Color.ink2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink4)
                }
                .padding(Brand.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .clarionCard()
        }
    }

    // MARK: - Next dose

    @ViewBuilder
    private var nextDoseCard: some View {
        if case .ready(let r) = report.state {
            let takeable = (r.stack ?? []).filter { $0.bucket != .cut }
            if !takeable.isEmpty {
                let remaining = takeable.filter { !log.isDone($0) }
                card {
                    VStack(alignment: .leading, spacing: Brand.s3) {
                        HStack {
                            Eyebrow("Protocol")
                            Spacer()
                            Button {
                                Haptics.tap()
                                tab = 3
                            } label: {
                                Text("See plan")
                                    .font(.ui(13, weight: 600))
                                    .foregroundStyle(Color.forest)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        if let next = remaining.first {
                            HStack(spacing: Brand.s3) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(next.name)
                                        .font(.display(16, weight: 700))
                                        .foregroundStyle(Color.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text("\(next.dose) · \(takeable.count - remaining.count) of \(takeable.count) taken today")
                                        .font(.bodyFace(13))
                                        .foregroundStyle(Color.ink3)
                                }
                                Spacer()
                                Button {
                                    Haptics.commit()
                                    Task { await log.toggle(next) }
                                } label: {
                                    Text("Log dose")
                                        .font(.ui(13.5, weight: 600))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 9)
                                        .background(
                                            LinearGradient(colors: [Color.forestBright, Color.forest], startPoint: .top, endPoint: .bottom),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(PressableStyle(haptic: false))
                            }
                        } else {
                            HStack(spacing: Brand.s2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.forest)
                                Text("All \(takeable.count) doses logged for today.")
                                    .font(.bodyFace(14.5))
                                    .foregroundStyle(Color.ink2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sync state (one quiet row, not a card of chrome)

    private var syncRow: some View {
        card {
            HStack(spacing: Brand.s2) {
                switch sync.status {
                case .idle:
                    Image(systemName: sync.lastSyncedAt == nil ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .foregroundStyle(Color.forest)
                    Text(sync.lastSyncedAt == nil ? "Not synced yet" : "Everything up to date")
                        .font(.bodyFace(14.5)).foregroundStyle(Color.ink3)
                case .syncing:
                    ProgressView().controlSize(.small)
                    Text("Syncing…").font(.bodyFace(14.5)).foregroundStyle(Color.ink3)
                case .done(let daily, let workouts, _):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.forest)
                    Text("Synced \(daily) days, \(workouts) workouts")
                        .font(.bodyFace(14.5)).foregroundStyle(Color.ink3)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.amber)
                    Text(message).font(.bodyFace(14.5)).foregroundStyle(Color.ink3)
                }
                Spacer()
                Button("Sync") {
                    Haptics.commit()
                    Task { await sync.sync() }
                }
                .font(.ui(14, weight: 600))
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
            HStack(spacing: 4) {
                Text(openingDashboard ? "Opening…" : "Full analysis on clarionlabs.tech")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.bodyFace(13))
            .foregroundStyle(Color.ink3)
        }
        .buttonStyle(PressableStyle())
        .disabled(openingDashboard)
        .padding(.top, Brand.s1)
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
            .padding(Brand.s4 + 2)
            .clarionCard()
    }
}
