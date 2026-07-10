import SwiftUI
import Charts

/// The native vitals dashboard — hero readiness ring + coaching, persona metric cards with
/// baseline-band charts, correlation insights, recent workouts. Reads GET /api/wearables/snapshot.
struct VitalsView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var sync: SyncCoordinator
    @StateObject private var store: VitalsStore

    init(auth: SupabaseAuth) {
        _store = StateObject(wrappedValue: VitalsStore(auth: auth))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                switch store.state {
                case .loading:
                    ProgressView().padding(.top, 80)
                case .loaded(let r), .demo(let r):
                    content(r)
                }
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Vitals")
            .refreshable { await reload() }
        }
        .task { await store.load() }
    }

    @ViewBuilder
    private func content(_ r: SnapshotResponse) -> some View {
        let snap = r.snapshot
        VStack(spacing: 18) {
            if snap.isDemo {
                sampleBanner
            }

            hero(snap)

            if !r.insights.isEmpty {
                sectionLabel("What your labs + wearable say together")
                ForEach(r.insights) { insight in
                    InsightCard(insight: insight)
                }
            }

            sectionLabel("Your dashboard")
            let metrics = r.widgetKeys.compactMap { VitalsMetric.catalog[$0] }
                .filter { VitalsMetric.hasData($0, snap.daily) }
            ForEach(metrics) { metric in
                MetricCard(metric: metric, daily: snap.daily)
            }

            if !snap.workouts.isEmpty {
                sectionLabel("Recent workouts")
                WorkoutsCard(workouts: Array(snap.workouts.prefix(5)))
            }
        }
        .padding(20)
    }

    private func hero(_ snap: WearableSnapshot) -> some View {
        let readiness = WearableDailyMetrics.latest(snap.daily, \.readinessScore).map { Int($0) }
        return VStack(spacing: 16) {
            ReadinessRing(score: readiness)
            Text(coachingLine(readiness))
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let hrv = WearableDailyMetrics.latest(snap.daily, \.hrv) {
                    chip("HRV \(Int(hrv)) ms", good: true)
                }
                if let rhr = WearableDailyMetrics.latest(snap.daily, \.restingHeartRate) {
                    chip("RHR \(Int(rhr)) bpm", good: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            LinearGradient(colors: [Color.white, Color.forestWash.opacity(0.6)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 26)
        )
    }

    private func coachingLine(_ score: Int?) -> String {
        guard let score else { return "We'll show your recovery once your ring syncs tonight's data." }
        if score >= 80 { return "You're well-recovered — a strong day to push." }
        if score >= 65 { return "Solidly recovered — train as planned." }
        if score >= 50 { return "Only part-recovered — keep it moderate today." }
        return "Under-recovered — prioritise easy movement and sleep."
    }

    private func chip(_ text: String, good: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(good ? Color.forestWash : Color(.systemGray6), in: Capsule())
            .foregroundStyle(good ? Color.forestInk : Color.inkMuted)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Color.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reload() async {
        await sync.sync()
        await store.load()
    }
}

extension VitalsMetric {
    static func hasData(_ metric: VitalsMetric, _ daily: [WearableDailyMetrics]) -> Bool {
        daily.contains { $0[keyPath: metric.keyPath] != nil }
    }
}

private extension Color {
    static let paper = Color(red: 0.94, green: 0.95, blue: 0.94)
}
