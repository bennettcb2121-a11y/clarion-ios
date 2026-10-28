import SwiftUI

/// Home is ONE paper sheet (web HomeHandoff `home-sheet`, Oct 2026): greeting, Today + Lab
/// score side by side, today's doses with a lab-backed reason each, the one nudge (running
/// low), next draw, the markers pulling the score down, the feeling check-in, and a weekly
/// research note matched to the person's flagged markers. No stacked cards, no score dial.
/// Pre-connect it earns the HealthKit permission with a persona-scoped primer.
struct HomeView: View {
    let persona: Persona
    @ObservedObject var report: ReportStore
    @ObservedObject var log: ProtocolLogStore
    @Binding var tab: Int

    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var sync: SyncCoordinator
    @EnvironmentObject private var subscription: SubscriptionStore
    /// Same real snapshot the Vitals tab renders — the brief never recomputes readiness.
    /// Injected from RootView so Home and the Vitals tab share ONE store: when each owned its
    /// own, they disagreed (tab: readiness 64 / HRV 51; Home: "New day." and no metric row).
    @ObservedObject var vitals: VitalsStore
    @AppStorage("clarion_health_authorized") private var healthAuthorized = false
    // App-wide distance/pace units (shared with Settings' body-units toggle). Default miles.
    @AppStorage("clarion_units_imperial") private var unitsImperial = true
    /// "Viewed" markers for the nudge slot's next-step ladder (web: HOME_*_VIEWED_KEY).
    @AppStorage("clarion_home_report_viewed") private var reportViewed = false
    @AppStorage("clarion_home_plan_viewed") private var planViewed = false
    /// Local date key of the last nudge dismissal — one nudge per day means one.
    @AppStorage(HomeNudge.dismissedDayKey) private var nudgeDismissedDay = ""
    @State private var requestingAuth = false
    @State private var openingWeb = false
    /// Lab intake, presented IN-APP. Bouncing the user to Safari for the single most
    /// important action in the product lost the session feel and the App Store dislikes a
    /// core flow leaving the app — the webview surface already exists, so use it.
    @State private var addLabsSheet = false
    @State private var showSettings = false
    @State private var libraryRoute: LibraryRoute? = nil
    @State private var showChat = false
    @State private var didRequestHealth = false
    /// Today's subjective "how are you feeling?" check-in (device-local, per user + day).
    @StateObject private var feeling: FeelingStore

    init(persona: Persona, report: ReportStore, log: ProtocolLogStore, vitals: VitalsStore, tab: Binding<Int>) {
        self.persona = persona
        self._report = ObservedObject(wrappedValue: report)
        self._log = ObservedObject(wrappedValue: log)
        self._vitals = ObservedObject(wrappedValue: vitals)
        self._tab = tab
        // The shared session reads the Keychain synchronously, so the layout key is user-scoped
        // from the first frame.
        let userId = SupabaseAuth.shared.session?.userId
        self._feeling = StateObject(wrappedValue: FeelingStore(userId: userId))
    }

    /// What the Library sheet opens onto: the hub (toolbar icon) or one surface
    /// deep-linked from a Home grid tile — the hub stays underneath as the container.
    private enum LibraryRoute: String, Identifiable {
        case hub, labs, biomarkers, dailyInputs, logbook, guides, faq
        var id: String { rawValue }

        var deepLink: LibraryDestination? {
            switch self {
            case .hub: return nil
            case .labs: return .labs
            case .biomarkers: return .biomarkers
            case .dailyInputs: return .dailyInputs
            case .logbook: return .logbook
            case .guides: return .guides
            case .faq: return .faq
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Brand.s4) {
                        if !HealthStore.isAvailable {
                            card {
                                Text("Health data isn't available on this device.")
                                    .font(.clarionBody(15))
                                    .foregroundStyle(Color.ink3)
                            }
                        } else if !healthAuthorized && !isUITest {
                            connectCard.entrance(0)
                            previewSkeleton.entrance(1)
                        } else {
                            homeSheet.entrance(0)
                            syncRow.entrance(1)
                        }
                        webFooter.entrance(2).id("home-bottom")
                    }
                    .padding(.horizontal, Brand.s4)
                    .padding(.vertical, Brand.s2)
                }
                .contentMargins(.bottom, 96, for: .scrollContent)
                .background(Color.sheetPage.ignoresSafeArea())
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Quieter against the editorial hero: one forest accent (chat), the
                    // utility pair recede to ink-3, all at a lighter 15pt weight. Hit
                    // targets stay the system's 44pt toolbar standard.
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Haptics.tap()
                            showChat = true
                        } label: {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.forest)
                        }
                        .accessibilityLabel("Ask Clarion")
                        Button {
                            Haptics.tap()
                            libraryRoute = .hub
                        } label: {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.ink3)
                        }
                        .accessibilityLabel("Library")
                        Button {
                            Haptics.tap()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.ink3)
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
                .refreshable {
                    Haptics.touch()
                    await sync.sync()
                    await report.load()
                    await log.load()
                    await vitals.load()
                    Haptics.success()
                }
                .onAppear {
                    #if DEBUG
                    // Screenshot harness: `UITEST_SCROLL_BOTTOM` reveals the below-fold cards;
                    // the off-tab surfaces open on their own args (new IA: settings behind the
                    // gear, library pushed from Home, chat as a sheet).
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("UITEST_SCROLL_BOTTOM") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { proxy.scrollTo("home-bottom", anchor: .bottom) }
                        }
                    } else if args.contains("UITEST_SCROLL_LIBRARY") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { proxy.scrollTo("home-library", anchor: .bottom) }
                        }
                    }
                    if args.contains("UITEST_SETTINGS") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showSettings = true }
                    } else if args.contains("UITEST_LIBRARY") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { libraryRoute = .hub }
                    } else if args.contains("UITEST_FAQ") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { libraryRoute = .faq }
                    } else if args.contains("UITEST_CHAT") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showChat = true }
                    }
                    #endif
                }
            }
        }
        .sheet(isPresented: $showChat) {
            AskClarionSheet(auth: auth, snapshotProvider: { [report] in
                if case .ready(let r) = report.state { return BiomarkerSnapshot.build(from: r) }
                return nil
            })
        }
        // LibraryHomeView owns its own NavigationStack (six sub-surfaces), so it presents
        // as a sheet — its inner stack gets a clean context instead of nesting inside
        // Home's push hierarchy, and swipe-down dismisses. Grid tiles deep-link straight
        // to their surface; the hub stays underneath as the container. The environment
        // objects are re-attached explicitly — the gated surfaces (Labs history,
        // Biomarkers) read the entitlement, and the membership wall reads auth.
        .sheet(item: $libraryRoute) { route in
            LibraryHomeView(auth: auth, deepLink: route.deepLink)
                .environmentObject(auth)
                .environmentObject(subscription)
        }
        .sheet(isPresented: $addLabsSheet) {
            NavigationStack {
                ClarionWebSurface(auth: auth, path: "/labs/upload", title: "Add labs")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { addLabsSheet = false }
                        }
                    }
            }
        }
        .task {
            if case .loading = report.state { await report.load() }
            await log.load()
            await vitals.load()
            // Ensure HealthKit is actually requested this session. The persisted
            // `healthAuthorized` flag can be stale (reinstall / fresh sign-in), which left
            // reads "not determined" and Sync doing nothing. requestAuthorization is
            // idempotent — it shows the sheet only if the user hasn't decided yet.
            if HealthStore.isAvailable && !didRequestHealth {
                didRequestHealth = true
                await requestHealthAccess()
            }
        }
        .onChange(of: sync.status) { _, newStatus in
            // A sync just uploaded fresh HealthKit days — refetch the server snapshot so
            // every surface (metric row, ring, Vitals) reflects the merged truth, not a
            // local tail that disagrees with the server until the next manual refresh.
            if case .done(let d, let w, _) = newStatus, d + w > 0 {
                Task { await vitals.load() }
            }
        }
        .onChange(of: tab) { _, newTab in
            // The next-step ladder's "viewed" markers — visiting the tab settles the step.
            if newTab == 2 { reportViewed = true }
            if newTab == 3 { planViewed = true }
        }
    }

    // MARK: - Shared daily-loop state

    private var isUITest: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("UITEST_VITALS")
        #else
        return false
        #endif
    }

    /// Time-of-day greeting — same bands as the web hero.
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 5 { return "Still up" }
        if h < 12 { return "Good morning" }
        if h < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var reportData: ReportResponse? {
        if case .ready(let r) = report.state { return r }
        return nil
    }

    /// The lab-safe protocol (never sells against a cut verdict) — the web's labSafeStackItems.
    private var takeableStack: [StackItem] {
        let items = (reportData?.stack ?? []).filter { $0.bucket != .cut }
        #if DEBUG
        // Screenshot harness: `UITEST_RUNNING_LOW` gives the first vitamin D row a low bottle so
        // the running-low section can be captured (the demo report carries no inventory).
        if ProcessInfo.processInfo.arguments.contains("UITEST_RUNNING_LOW") {
            var injected = false
            return items.map { item in
                var copy = item
                if !injected, SupplementPresets.resolve(item.name) == "vitamin_d" {
                    copy.supply = .init(fillPercent: 14, status: "low", daysLeft: 5, pillsRemaining: 5)
                    injected = true
                }
                return copy
            }
        }
        #endif
        return items
    }

    private var dosesDone: Int { takeableStack.filter { log.isDone($0) }.count }

    private var protocolTodayComplete: Bool {
        !takeableStack.isEmpty && dosesDone == takeableStack.count
    }

    /// REAL wearable window for the brief: the server snapshot when it's real data,
    /// else the fresh HealthKit summary from the last sync. Demo only ever leaks in
    /// under UITEST (screenshot harness) — mirroring the web's honesty rule.
    private var briefWindow: (daily: [WearableDailyMetrics], workouts: [WearableWorkout])? {
        if case .loaded(let resp) = vitals.state {
            return (resp.snapshot.daily, resp.snapshot.workouts)
        }
        if !sync.lastSummary.isEmpty { return (sync.lastSummary, []) }
        #if DEBUG
        if isUITest, ProcessInfo.processInfo.arguments.contains("UITEST_WEARABLE"),
           case .demo(let resp) = vitals.state {
            return (resp.snapshot.daily, resp.snapshot.workouts)
        }
        #endif
        return nil
    }

    private var brief: MorningBrief {
        let markers = (reportData?.results ?? []).map {
            MorningBrief.Marker(name: $0.name, value: $0.value, status: $0.status, optimalMin: $0.optimalMin, optimalMax: $0.optimalMax)
        }
        return MorningBrief.build(MorningBrief.Input(
            dateKey: ProtocolLogStore.todayKey(),
            daily: briefWindow?.daily,
            workouts: briefWindow?.workouts ?? [],
            markers: markers,
            stackNames: takeableStack.map(\.name),
            protocolState: .init(
                total: takeableStack.count,
                done: dosesDone,
                streakDays: log.streakDays(todayComplete: protocolTodayComplete)
            )
        ))
    }

    private var countdown: NextDrawCountdown {
        guard let h = reportData?.history else { return .none }
        return NextDrawCountdown.build(
            lastDrawIso: h.lastDrawIso,
            retestWeeks: h.retestWeeks,
            todayIso: ProtocolLogStore.todayKey()
        )
    }

    private var victory: VictoryCard? {
        guard let h = reportData?.history, h.panelCount > 0 else { return nil }
        return VictoryCard.select(history: h, stack: takeableStack)
    }

    /// The ONE nudge of the day — same gate as the web (labs on file + log hydrated).
    private var nudge: HomeNudge? {
        guard let data = reportData, log.loaded else { return nil }
        let nextStep = HomeNextStep.compute(
            hasBloodwork: true,
            cabinetCount: nil, // the cabinet is a web surface — the step is skipped here
            reportViewed: reportViewed,
            planViewed: planViewed,
            protocolCount: takeableStack.count,
            protocolCheckedCount: dosesDone
        )
        let retest = RetestCountdown.compute(
            lastBloodworkAt: data.lastUpdated.flatMap(VictoryCard.parseTimestamp),
            retestWeeks: data.history?.retestWeeks ?? 8
        )
        var retestForSlot = retest
        #if DEBUG
        // Screenshot harness: let the injected low bottle hold the slot.
        if ProcessInfo.processInfo.arguments.contains("UITEST_RUNNING_LOW") { retestForSlot = nil }
        #endif
        return HomeNudge.pick(HomeNudge.Input(
            runningLow: runningLowItems,
            nextStep: nextStep,
            retest: retestForSlot,
            daysSinceLog: log.daysSinceLog,
            protocolTodayComplete: protocolTodayComplete,
            hasStack: !takeableStack.isEmpty,
            dismissedToday: nudgeDismissedDay == ProtocolLogStore.todayKey()
        ))
    }

    // MARK: - Connect (permission primer BEFORE the system sheet)

    private var connectCard: some View {
        card {
            VStack(alignment: .leading, spacing: Brand.s3) {
                Text("Connect Apple Health")
                    .font(.clarionDisplay(21))
                    .foregroundStyle(Color.ink)
                Text(PersonaScopes.primerCopy(for: persona))
                    .font(.clarionBody(15))
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
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
            }
        }
        .opacity(0.75)
    }

    private func previewMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.clarionData(19)) // preview of working numerals — data voice, not display
                .foregroundStyle(Color.ink3)
                .redacted(reason: .placeholder)
            Text(label).font(.clarionBody(12)).foregroundStyle(Color.ink3)
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

    // MARK: - Metric chip row (persona-adaptive — which three numbers lead)

    private struct HomeMetric: Identifiable {
        struct Delta {
            let text: String
            let good: Bool
        }

        let id: String
        let value: String
        let unit: String?
        let caption: String
        /// Chronological real readings behind the number (last ~14 uploads). Empty = no line.
        var series: [Double] = []
        /// Latest reading vs its 7-day baseline — nil when the move is inside noise.
        var delta: Delta? = nil
    }

    @ViewBuilder
    private var metricRow: some View {
        // Score already leads the sheet top — the strip carries wearable numbers only.
        let metrics = metricsForSheet
        if !metrics.isEmpty {
            VStack(alignment: .leading, spacing: Brand.s2 + 2) {
                if let tuned = personaTunedLabel {
                    sheetLabel(tuned)
                }
                HStack(spacing: Brand.s3) {
                    ForEach(metrics) { metricChip($0) }
                }
            }
        }
    }

    private func metricChip(_ m: HomeMetric) -> some View {
        VStack(alignment: .leading, spacing: Brand.s1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(m.value)
                    .font(.clarionData(22))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit = m.unit {
                    Text(unit)
                        .font(.clarionBody(11))
                        .foregroundStyle(Color.ink3)
                }
            }
            // The reading's own recent history — real points only; hidden below 3.
            if m.series.count >= 3 {
                TinySparkline(values: m.series)
                    .frame(height: 16)
                    .padding(.vertical, 1)
            }
            HStack(spacing: 3) {
                Text(m.caption.uppercased())
                    .font(.clarionLabel(10))
                    .tracking(0.12 * 10)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if let d = m.delta {
                    Text(d.text)
                        .font(.clarionData(10))
                        .foregroundStyle(d.good ? Color.forest : Color.amber)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // No chip boxes on the one sheet — the numbers sit on the paper.
    }

    /// Age in days of the newest REAL wearable reading behind the metric row. The row shows the
    /// last known numbers, so it has to say when they aren't from today — same honesty rule the
    /// Vitals tab applies with its "as of Jul 13" chip.
    private var metricsReadingAgeDays: Int? {
        // Same window the brief + Vitals read (server snapshot first) — one truth, one age.
        let source = briefWindow?.daily ?? []
        guard !source.isEmpty else { return nil }
        return MorningBrief.latestRealReadingAgeDays(source, dateKey: ProtocolLogStore.todayKey())
    }

    private var personaTunedLabel: String? {
        let base: String?
        switch persona {
        case .endurance: base = "Tuned for endurance"
        case .strength: base = "Tuned for strength"
        case .menopause: base = "Tuned for your transition"
        case .general: base = nil
        }
        guard let age = metricsReadingAgeDays, age >= 2 else { return base }
        let stale = "last reading \(age) days ago"
        guard let base else { return stale.prefix(1).uppercased() + stale.dropFirst() }
        return "\(base) · \(stale)"
    }

    /// The three numbers to lead with, by persona — first available wins, so a persona's flagship
    /// (VO₂max, overnight temp) leads when it's synced and gracefully falls back to the general
    /// set otherwise. Same wearable window the brief reads; Score comes from the report.
    private var homeMetrics: [HomeMetric] {
        // The SAME window the brief, the ring, and the Vitals tab read (server snapshot
        // first, fresh local sync only until it arrives). Home previously preferred the
        // local 3-day HealthKit tail, so it could show HRV 72 while Vitals showed the
        // snapshot's 40 — two "truths" on adjacent tabs. One source, one number.
        let source = briefWindow?.daily ?? []

        // The daily array runs THROUGH TODAY and its tail rows are EMPTY on days the device
        // hasn't uploaded. Reading `source.last` therefore grabbed a blank row and hid every
        // number the user actually has. Take each metric's most recent real value instead
        // (mirrors latestRealReadingAgeDays' backwards scan).
        func latest<T>(_ pick: (WearableDailyMetrics) -> T?) -> T? {
            for d in source.reversed() { if let v = pick(d) { return v } }
            return nil
        }
        /// Chronological REAL readings in the window (nil days skipped) — the sparkline input.
        func realSeries(_ pick: (WearableDailyMetrics) -> Double?) -> [Double] {
            Array(source.compactMap(pick).suffix(14))
        }
        /// Latest real reading vs the mean of up to 7 prior real readings. Needs ≥3 real
        /// points; below that there is no honest baseline, so no arrow is shown at all.
        func shift(_ series: [Double]) -> (diff: Double, base: Double)? {
            guard series.count >= 3, let last = series.last else { return nil }
            let prior = series.dropLast().suffix(7)
            guard prior.count >= 2 else { return nil }
            let base = prior.reduce(0, +) / Double(prior.count)
            return (last - base, base)
        }

        func hrv() -> HomeMetric? {
            latest { $0.hrv }.map { v in
                var m = HomeMetric(id: "hrv", value: "\(Int(v))", unit: "ms", caption: "HRV", series: realSeries { $0.hrv })
                if let s = shift(m.series), abs(s.diff) / max(s.base, 1) >= 0.03 {
                    let pct = Int((abs(s.diff) / max(s.base, 1) * 100).rounded())
                    m.delta = .init(text: "\(s.diff > 0 ? "▲" : "▼") \(pct)%", good: s.diff > 0)
                }
                return m
            }
        }
        func sleep() -> HomeMetric? {
            latest { $0.nightSleepMin }.map { v in
                var m = HomeMetric(id: "sleep", value: formatMinutes(v), unit: nil, caption: "Sleep", series: realSeries { $0.nightSleepMin })
                if let s = shift(m.series), abs(s.diff) >= 15 {
                    let mins = Int(abs(s.diff).rounded())
                    let text = mins < 95 ? "\(mins)m" : String(format: "%.1fh", Double(mins) / 60)
                    m.delta = .init(text: "\(s.diff > 0 ? "▲" : "▼") \(text)", good: s.diff > 0)
                }
                return m
            }
        }
        func vo2() -> HomeMetric? {
            latest { $0.vo2Max }.map { v in
                var m = HomeMetric(id: "vo2max", value: String(format: "%.1f", v), unit: nil, caption: "VO₂max", series: realSeries { $0.vo2Max })
                if let s = shift(m.series), abs(s.diff) >= 0.2 {
                    m.delta = .init(text: String(format: "%@ %.1f", s.diff > 0 ? "▲" : "▼", abs(s.diff)), good: s.diff > 0)
                }
                return m
            }
        }
        func temp() -> HomeMetric? {
            latest { $0.skinTempDeviationC }.map {
                HomeMetric(id: "temp", value: String(format: "%+.2f", $0), unit: "°C", caption: "Temp", series: realSeries { $0.skinTempDeviationC })
            }
        }
        func scoreMetric() -> HomeMetric? {
            guard let results = reportData?.results, !results.isEmpty else { return nil }
            return HomeMetric(id: "score", value: "\(ScoreEngine.score(results))", unit: nil, caption: "Score")
        }

        let candidates: [() -> HomeMetric?]
        switch persona {
        case .endurance: candidates = [vo2, hrv, sleep, scoreMetric]
        case .menopause: candidates = [temp, hrv, sleep, scoreMetric]
        case .strength, .general: candidates = [hrv, sleep, scoreMetric]
        }
        return Array(candidates.compactMap { $0() }.prefix(3))
    }

    private func formatMinutes(_ min: Double) -> String {
        let h = Int(min) / 60
        let m = Int(min) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func handleNudgeAction(_ nudge: HomeNudge) {
        if nudge.kind == .supply {
            // Reorder lives in the Shop tab (the web's reorder-shelf action).
            tab = 4
            return
        }
        switch nudge.href {
        case "/dashboard/analysis":
            tab = 2
        case "/dashboard/plan":
            tab = 3
        case "/labs/upload":
            addLabsSheet = true
        case "/dashboard/logbook":
            // Native surface — present it in-app rather than opening the web logbook.
            libraryRoute = .logbook
        case "/dashboard#protocol":
            // The doses card is right above — re-engage by logging the next dose directly.
            if let next = takeableStack.first(where: { !log.isDone($0) }) {
                Haptics.commit()
                Task { await log.toggle(next) }
            }
        default:
            break
        }
    }

    // MARK: - Sync state (one quiet row, not a card of chrome)

    private var syncRow: some View {
        VStack {
            HStack(spacing: Brand.s2) {
                switch sync.status {
                case .idle:
                    Image(systemName: sync.lastSyncedAt == nil ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .foregroundStyle(Color.forest)
                    Text(sync.lastSyncedAt == nil ? "Not synced yet" : "Everything up to date")
                        .font(.clarionBody(13)).foregroundStyle(Color.ink3)
                case .syncing:
                    ProgressView().controlSize(.small)
                    Text("Syncing…").font(.clarionBody(13)).foregroundStyle(Color.ink3)
                case .done(let daily, let workouts, _):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.forest)
                    Text(daily == 0 && workouts == 0
                         ? "Up to date — no new wearable data"
                         : "Synced \(daily) days, \(workouts) workouts")
                        .font(.clarionBody(13)).foregroundStyle(Color.ink3)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.amber)
                    Text(message).font(.clarionBody(13)).foregroundStyle(Color.ink3)
                }
                Spacer()
                Button("Sync") {
                    Haptics.commit()
                    // Request Health access first — if it was never granted this session,
                    // a bare sync just fails "not determined"; requesting shows the sheet.
                    Task { await requestHealthAccess() }
                }
                .font(.clarionLabel(14))
                .foregroundStyle(Color.forestInk)
                .buttonStyle(PressableStyle())
                .disabled(sync.status == .syncing)
            }
            .font(.clarionBody(13))
        }
        .padding(.horizontal, Brand.s2)
        .padding(.top, Brand.s2)
    }

    // MARK: - The web, demoted to a quiet footer

    private var webFooter: some View {
        Button {
            Task { await openWeb(path: "/dashboard/vitals") }
        } label: {
            HStack(spacing: 4) {
                Text(openingWeb ? "Opening…" : "Full analysis on clarionlabs.tech")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.clarionBody(13))
            .foregroundStyle(Color.ink3)
        }
        .buttonStyle(PressableStyle())
        .disabled(openingWeb)
        .padding(.top, Brand.s1)
    }

    private func openWeb(path: String) async {
        openingWeb = true
        defer { openingWeb = false }
        let fallback = Config.apiBase.appendingPathComponent(String(path.dropFirst()))
        guard let token = try? await auth.validAccessToken() else {
            await UIApplication.shared.open(fallback)
            return
        }
        let url = (try? await ClarionAPI.dashboardLoginLink(path: path, accessToken: token)) ?? fallback
        await UIApplication.shared.open(url)
    }

    // MARK: - The one sheet (web .home-sheet)

    /// Baskerville — the web's `--font-logo` (Libre Baskerville). iOS ships Apple's Baskerville,
    /// the same face the locked wordmark already uses.
    private static func serif(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Baskerville-Bold" : "Baskerville", size: size)
    }

    /// Section label — 11pt bold, 0.16em tracked caps.
    private func sheetLabel(_ text: String, color: Color = .ink3) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.16 * 11)
            .foregroundStyle(color)
    }

    /// Outline pill — forest text, thin forest border, never a filled button.
    private func outlinePill(_ text: String, systemImage: String? = nil, arrow: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11, weight: .heavy))
            }
            Text(text).font(.system(size: 13, weight: .semibold))
            if arrow { Text("→").font(.system(size: 13, weight: .semibold)) }
        }
        .foregroundStyle(Color.forest)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Capsule().stroke(Color.forest.opacity(0.35), lineWidth: 1))
        .contentShape(Capsule())
    }

    private var homeSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetTop
            sheetSection(!metricsForSheet.isEmpty) { metricRow }
            sheetSection(!takeableStack.isEmpty) { dosesSection }
            sheetSection(nudge != nil) { nudgeSection }
            sheetSection(reportData != nil) { nextDrawSection }
            sheetSection(!sheetMarkers.isEmpty) { markersSection }
            sheetSection(true) { feelingSection }
            sheetSection(weeklyNote != nil) { weeklyNoteSection }
            // Web: the victory card carries `order: 2`, so it lands at the end of the sheet.
            sheetSection(victory != nil) { victorySection }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .background(Color.sheetPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.sheetShadow.opacity(0.05), radius: 4, y: 2)
        .shadow(color: Color.sheetShadow.opacity(0.16), radius: 22, y: 16)
    }

    /// Each section after the top sits 32pt below the previous one — no dividers, no cards.
    @ViewBuilder
    private func sheetSection<Content: View>(_ show: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        if show {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 32)
        }
    }

    // 1 + 2 — greeting and the Today / Lab score pair

    private var greetingLine: String {
        let name = isUITest ? "Charlie" : auth.firstName
        if let name, !name.isEmpty { return "\(greeting), \(name)." }
        return "\(greeting)."
    }

    private var labScore: Int? {
        guard let data = reportData else { return nil }
        if let results = data.results, !results.isEmpty { return ScoreEngine.score(results) }
        return data.score
    }

    private var flaggedCount: Int { (reportData?.results ?? []).filter(\.isFlagged).count }
    private var inRangeCount: Int { (reportData?.results ?? []).filter { $0.status == "optimal" }.count }

    /// "Oct 2" — the latest draw date (history first, else the save timestamp).
    private var labDateLabel: String? {
        if let iso = reportData?.history?.lastDrawIso, !iso.isEmpty {
            return NextDrawCountdown.labelFor(iso)
        }
        guard let raw = reportData?.lastUpdated, let d = VictoryCard.parseTimestamp(raw) else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private var showReadinessColumn: Bool { brief.wearableDay && brief.readiness != nil }

    private var sheetTop: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(greetingLine)
                .font(Self.serif(17))
                .foregroundStyle(Color.ink3)
            HStack(alignment: .top, spacing: 0) {
                todayColumn
                hairline
                labColumn
                if showReadinessColumn {
                    hairline
                    readinessColumn
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.ink.opacity(0.12))
            .frame(width: 1)
            .padding(.trailing, showReadinessColumn ? 12 : 14)
            .padding(.leading, 12)
    }

    private var bigSize: CGFloat { showReadinessColumn ? 30 : 42 }

    private func bigNumber(_ value: String, suffix: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(Self.serif(bigSize, bold: true))
                .tracking(-0.03 * bigSize)
                .foregroundStyle(Color.ink)
            if let suffix {
                Text(suffix)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var todayColumn: some View {
        let total = takeableStack.count
        return VStack(alignment: .leading, spacing: 0) {
            sheetLabel("Today", color: .forest)
            bigNumber(total > 0 ? "\(dosesDone)" : "—", suffix: total > 0 ? "/\(total)" : nil)
            if total > 0 {
                let streak = log.streakDays(todayComplete: protocolTodayComplete)
                Text("taken" + (streak >= 2 ? " · \(streak)-day streak" : ""))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink3)
            } else {
                Button {
                    Haptics.tap()
                    tab = 3
                } label: {
                    Text("Build your plan →")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.forest)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var labColumn: some View {
        Button {
            Haptics.tap()
            if labScore == nil { addLabsSheet = true } else { tab = 2 }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                sheetLabel("Lab score", color: .forest)
                bigNumber(labScore.map(String.init) ?? "—", suffix: labScore == nil ? nil : "/100")
                if labScore == nil {
                    Text("Add your labs →")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.forest)
                } else {
                    Text([labDateLabel, flaggedCount > 0 ? "\(flaggedCount) low" : "\(inRangeCount) in range"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(labScore == nil ? "Adds your labs" : "Opens your report")
    }

    private var readinessColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetLabel("Readiness", color: .forest)
            bigNumber(brief.readiness.map(String.init) ?? "—", suffix: nil)
            Text(brief.readinessWord ?? "from your wearable")
                .font(.system(size: 13))
                .foregroundStyle(Color.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Vitals strip — real readings only (web HomeVitalsStrip)

    private var metricsForSheet: [HomeMetric] {
        homeMetrics.filter { $0.id != "score" }
    }

    // 3 — today's doses

    private var doseReasons: [String: String] {
        let results = reportData?.results ?? []
        var out: [String: String] = [:]
        for item in takeableStack {
            if let r = HomeSheet.doseReason(supplementName: item.name, results: results) { out[item.name] = r }
        }
        return out
    }

    private var dosesSection: some View {
        let items = takeableStack
        let total = items.count
        let done = dosesDone
        let reasons = doseReasons
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                sheetLabel("Today's doses")
                Spacer(minLength: 8)
                (Text("\(done)").fontWeight(.bold).foregroundColor(Color.ink)
                 + Text(" of \(total) logged" + (done == total ? " — nice work" : "")))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink3)
            }
            if done < total {
                Button {
                    Haptics.commit()
                    Task { await log.markAllDone(items) }
                } label: {
                    outlinePill(done == 0 ? "Took everything today" : "Took the rest (\(total - done))", systemImage: "checkmark")
                }
                .buttonStyle(PressableStyle(haptic: false))
                .padding(.top, 12)
                .padding(.bottom, 6)
            }
            VStack(spacing: 0) {
                ForEach(items) { item in
                    doseRow(item, reason: reasons[item.name])
                }
            }
            .padding(.top, 4)
        }
    }

    private func doseRow(_ item: StackItem, reason: String?) -> some View {
        let done = log.isDone(item)
        return Button {
            Haptics.commit()
            Task { await log.toggle(item) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(done ? Color.forest : Color.clear)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(done ? Color.forest : Color.ink.opacity(0.22), lineWidth: 1.3)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                BottleArt(presetId: SupplementPresets.resolve(item.name) ?? "")
                    .frame(width: 34, height: 44)
                    .shadow(color: Color.sheetShadow.opacity(0.22), radius: 1.5, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.coherentName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(done ? Color.ink3 : Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let reason {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 8)
                Text(item.dose)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(haptic: false))
        .accessibilityLabel("\(item.coherentName), \(item.dose)\(done ? ", taken" : "")")
    }

    // 4 — the one nudge (running low gets its drained bottle)

    private var lowItems: [StackItem] {
        takeableStack
            .filter { $0.supply?.status == "low" || $0.supply?.status == "out" }
            .sorted { ($0.supply?.daysLeft ?? 0) < ($1.supply?.daysLeft ?? 0) }
    }

    private var runningLowItems: [HomeNudge.RunningLowItem] {
        lowItems.map { .init(name: $0.coherentName, daysLeft: $0.supply?.status == "out" ? 0 : ($0.supply?.daysLeft ?? 0)) }
    }

    /// "Vitamin D3 (softgels)" → "Vitamin D3" — the short shelf label under the bottle.
    private func shelfLabel(_ name: String) -> String {
        let base = name.components(separatedBy: " — ").first ?? name
        return HomeSheet.shortName(base)
    }

    @ViewBuilder
    private var nudgeSection: some View {
        if let nudge {
            let isSupply = nudge.kind == .supply
            VStack(alignment: .trailing, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    if isSupply, !lowItems.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(lowItems.prefix(2)) { item in
                                lowBottle(item)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        sheetLabel(nudge.kicker, color: isSupply ? .clay : .forest)
                        Text(nudge.headline)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !nudge.body.isEmpty {
                            Text(nudge.body)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Color.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                    Spacer(minLength: 0)
                    if nudge.dismissible {
                        Button {
                            Haptics.tap()
                            nudgeDismissedDay = ProtocolLogStore.todayKey()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.ink4)
                                .padding(6)
                        }
                        .buttonStyle(PressableStyle(haptic: false))
                        .accessibilityLabel("Dismiss for today")
                    }
                }
                Button {
                    Haptics.tap()
                    handleNudgeAction(nudge)
                } label: {
                    outlinePill(nudge.ctaLabel, arrow: true)
                }
                .buttonStyle(PressableStyle(haptic: false))
            }
        }
    }

    /// The bottle drawn partly emptied to its real fill level (web mask: lvl × .74 + 10%).
    private func lowBottle(_ item: StackItem) -> some View {
        let supply = item.supply
        let fill = max(0, min(100, supply?.fillPercent ?? 0))
        let visible = (fill * 0.74 + 10) / 100
        let out = supply?.status == "out"
        return VStack(spacing: 3) {
            BottleArt(presetId: SupplementPresets.resolve(item.name) ?? "")
                .frame(width: 40, height: 54)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: visible),
                            .init(color: .black.opacity(0.1), location: visible),
                            .init(color: .black.opacity(0.1), location: 1),
                        ],
                        startPoint: .bottom, endPoint: .top
                    )
                )
            Text(shelfLabel(item.coherentName))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 64)
            Text(out ? "Out" : "\(supply?.daysLeft ?? 0)d left")
                .font(.system(size: 11.5))
                .foregroundStyle(out ? Color.clay : Color.amber)
        }
        .accessibilityElement(children: .combine)
    }

    // 5 — next draw

    @ViewBuilder
    private var nextDrawSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch countdown {
            case .scheduled(_, let nextLabel, _, _, _):
                drawLine(nextLabel)
                if let sub = countdown.subline { drawSub(sub) }
            case .overdue(_, let nextLabel, _):
                drawLine(nextLabel)
                if let sub = countdown.subline { drawSub(sub) }
                drawLink("Plan it →")
            case .none:
                drawLine(nil)
                drawSub("Nothing scheduled — give the protocol a finish line.")
                drawLink("Pick a date →")
            }
        }
    }

    private func drawLine(_ date: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            sheetLabel("Next draw")
            if let date {
                Text(date)
                    .font(Self.serif(18, bold: true))
                    .tracking(-0.01 * 18)
                    .foregroundStyle(Color.ink)
            }
        }
    }

    private func drawSub(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func drawLink(_ text: String) -> some View {
        Button {
            Haptics.tap()
            // Logbook is a NATIVE surface — open it in-app, don't bounce to the web.
            libraryRoute = .logbook
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.forest)
        }
        .buttonStyle(PressableStyle())
    }

    // 6 — markers: flagged first (most severe), then in-range wins, four max (web pickHomeHandoffMarkers)

    private var sheetMarkers: [BiomarkerResult] {
        let results = (reportData?.results ?? []).filter { $0.status != "unknown" }
        let flagged = results.filter(\.isFlagged).sorted { $0.sortRank < $1.sortRank }
        let wins = results.filter { $0.status == "optimal" }
        return Array((flagged + wins).prefix(4))
    }

    private func rangeLabel(_ m: BiomarkerResult) -> String {
        switch (m.optimalMin, m.optimalMax) {
        case let (lo?, hi?): return "\(HomeSheet.fmt(lo))–\(HomeSheet.fmt(hi))"
        case let (lo?, nil): return "over \(HomeSheet.fmt(lo))"
        case let (nil, hi?): return "under \(HomeSheet.fmt(hi))"
        default: return m.statusLabel
        }
    }

    private var markersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text((flaggedCount > 0 ? "What's pulling your lab score down" : "Markers").uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.16 * 11)
                    .lineSpacing(4)
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    tab = 2
                } label: {
                    Text("See all →")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.forest)
                        .fixedSize()
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.bottom, 6)
            ForEach(sheetMarkers) { m in
                Button {
                    Haptics.tap()
                    tab = 2
                } label: {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(m.isFlagged ? Color.clay : Color.forest)
                                    .frame(width: 6, height: 6)
                                Text(m.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.ink2)
                                    .lineLimit(1)
                            }
                            Text(rangeLabel(m))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ink3)
                                .padding(.leading, 14)
                        }
                        Spacer(minLength: 8)
                        Text([HomeSheet.fmt(m.value), m.unit].compactMap { $0 }.joined(separator: " "))
                            .font(Self.serif(19, bold: true))
                            .tracking(-0.01 * 19)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // 7 — how are you feeling (the existing device-local check-in)

    private func feelingTone(_ level: Int) -> Color {
        switch level {
        case 1: return .clay
        case 2: return .amber
        case 3: return .ink3
        case 4: return .forestBright
        default: return .forest
        }
    }

    private var feelingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sheetLabel("How are you feeling?")
            HStack(spacing: 6) {
                ForEach(FeelingStore.levels, id: \.level) { opt in
                    feelingPill(opt.level, opt.label)
                }
            }
        }
    }

    private func feelingPill(_ level: Int, _ label: String) -> some View {
        let selected = feeling.today == level
        let tone = feelingTone(level)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { feeling.set(level) }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(tone.opacity(selected ? 1 : 0.45))
                    .frame(width: 4, height: 4)
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selected ? Color.ink : Color.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
            .background(Capsule().fill(selected ? tone.opacity(0.13) : Color.surface))
            .overlay(Capsule().stroke(selected ? tone.opacity(0.55) : Color.line2, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // 8 — for you this week (only when a flagged marker matches a cited note)

    private var weeklyNote: HomeSheet.WeeklyNote? {
        HomeSheet.pickWeeklyNote(results: reportData?.results ?? [], dateKey: ProtocolLogStore.todayKey())
    }

    @ViewBuilder
    private var weeklyNoteSection: some View {
        if let note = weeklyNote {
            VStack(alignment: .leading, spacing: 6) {
                sheetLabel("For you this week · \(note.marker)", color: .forest)
                Text(note.headline)
                    .font(Self.serif(19, bold: true))
                    .tracking(-0.01 * 19)
                    .lineSpacing(3)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note.body)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note.source)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.ink4)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.ink.opacity(0.09)).frame(height: 1)
            }
        }
    }

    // Between draws (web keeps it, at the end of the sheet)

    @ViewBuilder
    private var victorySection: some View {
        if let victory {
            VStack(alignment: .leading, spacing: 8) {
                sheetLabel("Between draws")
                switch victory {
                case .anticipation(let headline, let body):
                    Text(headline)
                        .font(Self.serif(19, bold: true))
                        .foregroundStyle(Color.ink)
                    Text(body)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                case .improved(let delta):
                    victoryDelta(delta, improved: true)
                case .regressed(let delta):
                    victoryDelta(delta, improved: false)
                }
            }
        }
    }

    private func victoryDelta(_ delta: VictoryCard.Delta, improved: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(delta.marker)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink2)
                Text(improved ? "Improved" : "Drifting")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.1 * 11)
                    .textCase(.uppercase)
                    .foregroundStyle(improved ? Color.forest : Color.clay)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(delta.from)
                    .font(Self.serif(19, bold: true))
                    .foregroundStyle(Color.ink3)
                Text("→").font(.system(size: 15)).foregroundStyle(Color.ink3)
                Text(delta.to)
                    .font(Self.serif(23, bold: true))
                    .foregroundStyle(improved ? Color.forestInk : Color.clay)
                if !delta.unit.isEmpty {
                    Text(delta.unit).font(.system(size: 12)).foregroundStyle(Color.ink3)
                }
                Text("since \(delta.sinceLabel)").font(.system(size: 12)).foregroundStyle(Color.ink3)
            }
            Text(delta.body)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Brand.s4 + 2)
            .clarionCard()
    }
}

// MARK: - One-sheet paper colors (web .home-sheet: page #F4EFE7, sheet #FBF7F0)

extension Color {
    static let sheetPage = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x0F1614) : UIColor(hex: 0xF4EFE7) })
    static let sheetPaper = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x15201C) : UIColor(hex: 0xFBF7F0) })
    /// Warm brown shadow (web rgba(60,44,20,…)); black in dark mode.
    static let sheetShadow = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x000000) : UIColor(hex: 0x3C2C14) })
}
