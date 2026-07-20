import SwiftUI
import Charts

/// The native vitals dashboard — hero readiness ring + coaching, persona metric cards with
/// baseline-band charts, correlation insights, recent workouts. Reads GET /api/wearables/snapshot.
/// Customizable (drag/add/remove via CustomizeSheet) and honest about stale device data.
struct VitalsView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var sync: SyncCoordinator
    /// Injected, NOT owned: Home reads the same snapshot for its metric row and readiness. Two
    /// separate stores drifted apart — the tab showed real data (readiness 64, HRV 51) while
    /// Home's copy had fallen back to the sample and rendered no metrics at all.
    @ObservedObject var store: VitalsStore
    @State private var customizing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                switch store.state {
                case .loading:
                    ClarionLoadingView()
                case .loaded(let r), .demo(let r):
                    content(r)
                }
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Vitals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        customizing = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $customizing) {
                CustomizeSheet(store: store)
            }
            .refreshable {
                Haptics.touch()
                await reload()
            }
        }
        .task { if case .loading = store.state { await store.load() } }
    }

    @ViewBuilder
    private func content(_ r: SnapshotResponse) -> some View {
        let snap = r.snapshot
        VStack(spacing: 18) {
            if !snap.isDemo && snap.isStale {
                staleBanner(snap).entrance(0)
            }

            hero(snap).entrance(1)

            if !r.insights.isEmpty {
                sectionLabel("What your labs + wearable say together").entrance(2)
                ForEach(Array(r.insights.enumerated()), id: \.element.id) { i, insight in
                    InsightCard(insight: insight).entrance(3 + i)
                }
            }

            sectionLabel("Your dashboard").entrance(3)
            let metrics = store.widgetKeys.compactMap { VitalsMetric.catalog[$0] }
                .filter { VitalsMetric.hasData($0, snap.daily) }
            ForEach(Array(metrics.enumerated()), id: \.element.id) { i, metric in
                MetricCard(metric: metric, daily: snap.daily).entrance(4 + i)
            }

            if !snap.workouts.isEmpty {
                sectionLabel("Recent workouts").entrance(5 + metrics.count)
                WorkoutsCard(workouts: Array(snap.workouts.prefix(5))).entrance(6 + metrics.count)
            }
        }
        .padding(20)
    }

    // MARK: - Banners

    /// Honest-data banner: the pipeline is fine but the DEVICE hasn't delivered a fresh night.
    /// Without this, a 9-day-old HRV silently reads as "today" — worse than no data.
    private func staleBanner(_ snap: WearableSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(Color.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Latest reading is \(snap.readingAgeDays ?? 0) days old")
                    .font(.clarionLabel(14))
                    .foregroundStyle(Color.ink)
                Text("Open the \(providerName(snap.provider)) app so your device uploads its recent nights, then pull to refresh.")
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink2)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.amberWash, in: RoundedRectangle(cornerRadius: Brand.r))
    }

    private func providerName(_ p: String) -> String {
        ["oura": "Oura", "apple_health": "Health", "garmin": "Garmin", "whoop": "Whoop", "fitbit": "Fitbit"][p] ?? "device"
    }

    // MARK: - Hero

    private func hero(_ snap: WearableSnapshot) -> some View {
        let readiness = WearableDailyMetrics.latest(snap.daily, \.readinessScore).map { Int($0) }
        return VStack(spacing: 16) {
            ReadinessRing(score: readiness)
            Text(coachingLine(readiness, stale: snap.isStale))
                .font(.clarionDisplayItalic(17))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            HStack(spacing: 10) {
                if let hrv = WearableDailyMetrics.latest(snap.daily, \.hrv) {
                    chip("HRV \(Int(hrv)) ms", good: true)
                }
                if let rhr = WearableDailyMetrics.latest(snap.daily, \.restingHeartRate) {
                    chip("RHR \(Int(rhr)) bpm", good: true)
                }
                if snap.isStale, let date = snap.latestReadingDate {
                    chip("as of \(prettyDay(date))", good: false)
                }
                if snap.isDemo {
                    chip("Sample data", good: false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            LinearGradient(colors: [Color.surface, Color.forestWash.opacity(0.5)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: Brand.rXL)
        )
        .overlay(RoundedRectangle(cornerRadius: Brand.rXL).stroke(Color.line))
        .shadow(color: Color.forest.opacity(0.08), radius: 16, y: 6)
    }

    private func coachingLine(_ score: Int?, stale: Bool) -> String {
        guard let score else { return "We'll show your recovery once your ring syncs tonight's data." }
        if stale { return "Showing your last available reading — sync your device for today's picture." }
        if score >= 80 { return "You're well-recovered — a strong day to push." }
        if score >= 65 { return "Solidly recovered — train as planned." }
        if score >= 50 { return "Only part-recovered — keep it moderate today." }
        return "Under-recovered — prioritise easy movement and sleep."
    }

    private func chip(_ text: String, good: Bool) -> some View {
        Text(text)
            .font(.clarionData(12))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(good ? Color.forestWash : Color.paperDim, in: Capsule())
            .foregroundStyle(good ? Color.forestInk : Color.ink3)
    }

    private func prettyDay(_ iso: String) -> String {
        // Server day keys are Gregorian — parse and render them that way.
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.calendar = Calendar(identifier: .gregorian)
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    private func sectionLabel(_ text: String) -> some View {
        Eyebrow(text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reload() async {
        await sync.sync()
        await store.load()
        Haptics.success()
    }
}

extension VitalsMetric {
    static func hasData(_ metric: VitalsMetric, _ daily: [WearableDailyMetrics]) -> Bool {
        daily.contains { $0[keyPath: metric.keyPath] != nil }
    }
}
