import SwiftUI

/// Home is the daily loop: a time-of-day greeting, readiness + ONE daily insight that
/// connects the wearable to the blood, the next-draw countdown (endowed progress), today's
/// doses, the victory card (the most meaningful movement across draws), ONE nudge slot max,
/// and sync state. Pre-connect it earns the HealthKit permission with a persona-scoped
/// primer above a preview of what's coming.
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
    @State private var showSettings = false
    @State private var libraryRoute: LibraryRoute? = nil
    @State private var showChat = false
    @State private var showCustomize = false
    @State private var typedCount = 0
    @State private var greetingStarted = false
    @State private var didRequestHealth = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Persona-defaulted, user-overridable Home card order + visibility (persisted per user id).
    @StateObject private var layout: HomeLayoutStore
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
        self._layout = StateObject(wrappedValue: HomeLayoutStore(persona: persona, userId: userId))
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
                            // The Brief is the fixed star — eyebrow + one large insight sentence.
                            briefHero.entrance(0)
                            addLabsCard.entrance(1)
                            // Everything below reorders / hides per the persona default + user override.
                            ForEach(Array(layout.order.enumerated()), id: \.element) { i, card in
                                customCard(card).entrance(2 + i)
                            }
                            customizeFooter.entrance(2 + layout.order.count)
                            libraryGrid.entrance(3 + layout.order.count)
                            syncRow.entrance(4 + layout.order.count)
                        }
                        webFooter.entrance(9).id("home-bottom")
                    }
                    .padding(Brand.s5)
                }
                .contentMargins(.bottom, 96, for: .scrollContent)
                .background(Color.paper.ignoresSafeArea())
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Haptics.tap()
                            showChat = true
                        } label: {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .foregroundStyle(Color.forest)
                        }
                        .accessibilityLabel("Ask Clarion")
                        Button {
                            Haptics.tap()
                            libraryRoute = .hub
                        } label: {
                            Image(systemName: "books.vertical")
                                .foregroundStyle(Color.ink2)
                        }
                        .accessibilityLabel("Library")
                        Button {
                            Haptics.tap()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Color.ink2)
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
                    } else if args.contains("UITEST_HOME_CUSTOMIZE") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showCustomize = true }
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
        .sheet(isPresented: $showCustomize) {
            HomeCustomizeSheet(store: layout)
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
        (reportData?.stack ?? []).filter { $0.bucket != .cut }
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
        if isUITest, case .demo(let resp) = vitals.state {
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
        return HomeNudge.pick(HomeNudge.Input(
            runningLow: [], // no inventory surface on iOS yet
            nextStep: nextStep,
            retest: retest,
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

    // MARK: - The Brief (the fixed hero: eyebrow + ONE large insight sentence, no competing dial)

    /// Layout A — masthead + ring. The greeting is the largest thing on the screen and
    /// TYPES IN on appear; the readiness ring + status verdict sit beneath it, secondary.
    private var briefHero: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Text(dateEyebrow)
                .font(.clarionLabel(11))
                .tracking(0.14 * 11)
                .foregroundStyle(Color.ink3)

            // The masthead. Fraunces, biggest, types in with a caret.
            Text(displayedGreeting)
                .font(.clarionDisplay(31))
                .tracking(-0.02 * 31)
                .foregroundStyle(Color.ink)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(fullGreeting)

            // Readiness ring + status verdict — one calm unit, clearly below the welcome.
            HStack(spacing: Brand.s4) {
                if let readiness = heroReadiness {
                    heroRing(readiness)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(readinessIsSubjective
                         ? (feeling.word ?? HomeStatus.word(readiness: heroReadiness, persona: persona))
                         : HomeStatus.word(readiness: heroReadiness, persona: persona))
                        .font(.clarionDisplay(19))
                        .tracking(-0.015 * 19)
                        .foregroundStyle(Color.ink)
                    Text(readinessCaption)
                        .font(.clarionLabel(10))
                        .tracking(0.13 * 10)
                        .foregroundStyle(Color.ink3)
                }
            }
            .padding(.top, Brand.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Brand.s1)
        .onAppear { startGreetingType() }
    }

    /// A compact readiness ring with the figure inside — the score's real treatment.
    private func heroRing(_ value: Int) -> some View {
        ZStack {
            Circle().stroke(Color.forest.opacity(0.16), lineWidth: 5.5)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value, 0), 100)) / 100)
                .stroke(Color.forest, style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(.clarionData(22))
                .foregroundStyle(Color.ink)
        }
        .frame(width: 66, height: 66)
    }

    /// "READINESS · FULLY CHARGED" — the tier phrase mirrors the status word's band.
    private var readinessCaption: String {
        guard let r = heroReadiness else { return "Readiness".uppercased() }
        if readinessIsSubjective { return "How you feel today".uppercased() }
        let tier: String
        switch r {
        case 80...: tier = "Fully charged"
        case 65..<80: tier = "Well recovered"
        case 50..<65: tier = "Take it easy"
        default: tier = "Rest up"
        }
        return "Readiness · \(tier)".uppercased()
    }

    /// "WEDNESDAY, JULY 15" — Gregorian/POSIX so a non-Gregorian device calendar can't corrupt it.
    private var dateEyebrow: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date()).uppercased()
    }

    /// "Good morning,\nCharlie." — time-of-day greeting + first name (demo "Charlie" under UITEST).
    private var fullGreeting: String {
        let name = isUITest ? "Charlie" : auth.firstName
        if let name, !name.isEmpty { return "\(greeting),\n\(name)." }
        return "\(greeting)."
    }

    /// The progressively-revealed greeting with a typing caret until complete.
    private var displayedGreeting: String {
        let shown = String(fullGreeting.prefix(typedCount))
        return typedCount >= fullGreeting.count ? shown : shown + "\u{2009}▏"
    }

    private func startGreetingType() {
        guard !greetingStarted else { return }
        greetingStarted = true
        if reduceMotion { typedCount = fullGreeting.count; return }
        typedCount = 0
        let total = fullGreeting.count
        Task { @MainActor in
            for i in 0...total {
                typedCount = i
                try? await Task.sleep(nanoseconds: 85_000_000)
            }
        }
    }

    /// The fresh readiness driving the hero word + figure. DEBUG `UITEST_READINESS=<n>` forces a
    /// value so the screenshot harness can show every status tier without hacking the demo data.
    private var heroReadiness: Int? {
        #if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("UITEST_READINESS=") }),
           let forced = Int(arg.dropFirst("UITEST_READINESS=".count)) {
            return forced
        }
        #endif
        // Wearable-derived readiness is authoritative; when it's quiet (no fresh reading, or
        // no wearable at all — e.g. the simulator), the self-reported check-in fills the ring
        // so Home is never a blank "New day."
        if let r = brief.readiness { return r }
        return feeling.readiness
    }

    /// True when the ring is showing the self-reported check-in rather than a wearable reading.
    private var readinessIsSubjective: Bool {
        brief.readiness == nil && feeling.readiness != nil
    }

    /// "WEDNESDAY · READINESS" — tracked-caps eyebrow (the figure now sits beside the hero word).
    private var eyebrowRow: some View {
        Text(eyebrowLead)
            .font(.clarionLabel(11.5))
            .tracking(0.14 * 11.5)
            .foregroundStyle(Color.ink3)
    }

    private var eyebrowLead: String {
        heroReadiness != nil ? "\(weekday) · Readiness".uppercased() : weekday.uppercased()
    }

    /// Weekday name (Gregorian, en_US_POSIX — never the device's Buddhist calendar).
    private var weekday: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    // MARK: - Customizable card dispatch (persona default order, user override wins)

    @ViewBuilder
    private func customCard(_ card: HomeCard) -> some View {
        switch card {
        case .feeling: feelingCard
        case .metrics: metricRow
        case .run: runCard
        case .victory: victoryCardView
        case .doses: nextDoseCard
        case .countdown: countdownRow
        case .nudge: nudgeCard
        }
    }

    // MARK: - Metric chip row (persona-adaptive — which three numbers lead)

    private struct HomeMetric: Identifiable {
        let id: String
        let value: String
        let unit: String?
        let caption: String
    }

    @ViewBuilder
    private var metricRow: some View {
        let metrics = homeMetrics
        if !metrics.isEmpty {
            VStack(alignment: .leading, spacing: Brand.s2 + 2) {
                if let tuned = personaTunedLabel {
                    Eyebrow(tuned).padding(.horizontal, Brand.s1)
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
            Text(m.caption.uppercased())
                .font(.clarionLabel(10))
                .tracking(0.12 * 10)
                .foregroundStyle(Color.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Brand.s3)
        .padding(.vertical, Brand.s3 + 1)
        .clarionCardQuiet(cornerRadius: Brand.r)
    }

    // MARK: - How are you feeling? (a daily self-check — drives readiness when the wearable's quiet)

    private var feelingCard: some View {
        card {
            VStack(alignment: .leading, spacing: Brand.s3) {
                HStack(spacing: Brand.s2) {
                    Eyebrow("How are you feeling?")
                    Spacer()
                    if feeling.today != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.forest)
                    }
                }
                HStack(spacing: Brand.s2) {
                    ForEach(FeelingStore.levels, id: \.level) { opt in
                        feelingOption(opt.level, opt.label)
                    }
                }
                if feeling.today != nil && brief.readiness == nil {
                    Text("Feeding your readiness ring while your wearable's quiet.")
                        .font(.clarionBody(12))
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private func feelingOption(_ level: Int, _ label: String) -> some View {
        let selected = feeling.today == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { feeling.set(level) }
        } label: {
            Text(label)
                .font(.clarionLabel(11))
                .foregroundStyle(selected ? Color.forestInk : Color.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Brand.s2 + 2)
                .background(
                    RoundedRectangle(cornerRadius: Brand.rSM)
                        .fill(selected ? Color.forestWash : Color.ink.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.rSM)
                        .stroke(selected ? Color.forest.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Recent run (the latest training session — endurance leads with it)

    private var recentWorkout: WearableWorkout? {
        (briefWindow?.workouts ?? []).max(by: { $0.date < $1.date })
    }

    @ViewBuilder
    private var runCard: some View {
        if let w = recentWorkout {
            card {
                VStack(alignment: .leading, spacing: Brand.s3) {
                    HStack {
                        Eyebrow(workoutKindLabel(w.type))
                        Spacer()
                        Text(relativeDay(w.date))
                            .font(.clarionLabel(10)).tracking(0.1 * 10)
                            .foregroundStyle(Color.ink3)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if let km = w.distanceKm {
                            let d = UnitsMath.distanceParts(km: km, imperial: unitsImperial)
                            Text(d.value).font(.clarionDisplay(28)).foregroundStyle(Color.ink)
                            Text(d.unit).font(.clarionBody(14)).foregroundStyle(Color.ink3)
                        } else {
                            Text(formatMinutes(w.durationMin)).font(.clarionDisplay(28)).foregroundStyle(Color.ink)
                        }
                    }
                    HStack(spacing: Brand.s5) {
                        runStat(formatMinutes(w.durationMin), "TIME")
                        if let m = w.primaryMetric(imperial: unitsImperial) { runStat(m.value, m.label) }
                        if let hr = w.avgHeartRate { runStat("\(Int(hr))", "AVG HR") }
                    }
                }
            }
        } else if persona == .endurance || persona == .strength {
            Button {
                Haptics.tap()
                Task { await requestHealthAccess() }
            } label: {
                card {
                    HStack(spacing: Brand.s3) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.forest)
                            .frame(width: 40, height: 40)
                            .background(Color.forestWash, in: RoundedRectangle(cornerRadius: Brand.rSM))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No recent sessions").font(.clarionDisplay(16)).foregroundStyle(Color.ink)
                            Text(requestingAuth ? "Connecting…" : "Connect Apple Health to see your training here.")
                                .font(.clarionBody(12.5)).foregroundStyle(Color.ink3)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ink4)
                    }
                }
            }
            .buttonStyle(PressableStyle())
            .disabled(requestingAuth)
        }
    }

    private func runStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.clarionData(16)).foregroundStyle(Color.ink)
            Text(label).font(.clarionLabel(9)).tracking(0.1 * 9).foregroundStyle(Color.ink3)
        }
    }

    private func workoutKindLabel(_ type: String) -> String {
        switch type {
        case "run": return "Last run"
        case "ride": return "Last ride"
        case "swim": return "Last swim"
        case "strength": return "Last lift"
        case "walk": return "Last walk"
        case "hike": return "Last hike"
        case "row": return "Last row"
        default: return "Last session"
        }
    }

    /// "TODAY" / "YESTERDAY" / "N DAYS AGO" for a YYYY-MM-DD user-local workout date.
    private func relativeDay(_ iso: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso.uppercased() }
        let cal = Calendar(identifier: .gregorian)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1: return "TODAY"
        case 1: return "YESTERDAY"
        default: return "\(days) DAYS AGO"
        }
    }


    /// Age in days of the newest REAL wearable reading behind the metric row. The row shows the
    /// last known numbers, so it has to say when they aren't from today — same honesty rule the
    /// Vitals tab applies with its "as of Jul 13" chip.
    private var metricsReadingAgeDays: Int? {
        let source = sync.lastSummary.isEmpty ? (briefWindow?.daily ?? []) : sync.lastSummary
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
        let source = sync.lastSummary.isEmpty ? (briefWindow?.daily ?? []) : sync.lastSummary

        // The daily array runs THROUGH TODAY and its tail rows are EMPTY on days the device
        // hasn't uploaded. Reading `source.last` therefore grabbed a blank row and hid every
        // number the user actually has — Home showed only "86 SCORE" while the Vitals tab
        // showed "HRV 51 · as of Jul 13" off the same snapshot. Take each metric's most recent
        // real value instead (mirrors latestRealReadingAgeDays' backwards scan).
        func latest<T>(_ pick: (WearableDailyMetrics) -> T?) -> T? {
            for d in source.reversed() { if let v = pick(d) { return v } }
            return nil
        }

        func hrv() -> HomeMetric? {
            latest { $0.hrv }.map { HomeMetric(id: "hrv", value: "\(Int($0))", unit: "ms", caption: "HRV") }
        }
        func sleep() -> HomeMetric? {
            latest { $0.sleepDurationMin }.map { HomeMetric(id: "sleep", value: formatMinutes($0), unit: nil, caption: "Sleep") }
        }
        func vo2() -> HomeMetric? {
            latest { $0.vo2Max }.map { HomeMetric(id: "vo2max", value: String(format: "%.1f", $0), unit: nil, caption: "VO₂max") }
        }
        func temp() -> HomeMetric? {
            latest { $0.skinTempDeviationC }.map { HomeMetric(id: "temp", value: String(format: "%+.2f", $0), unit: "°C", caption: "Temp") }
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

    // MARK: - Next-draw countdown (endowed progress — protocol days already banked)

    @ViewBuilder
    private var countdownRow: some View {
        /* When the retest nudge holds the slot, the countdown would say the same thing twice. */
        if nudge?.kind != .retest {
            switch countdown {
            case .scheduled(_, let nextLabel, _, _, let elapsedPct):
                card {
                    VStack(alignment: .leading, spacing: Brand.s2) {
                        HStack(spacing: Brand.s2) {
                            Eyebrow("Next draw")
                            Text(nextLabel)
                                .font(.clarionData(13))
                                .foregroundStyle(Color.ink)
                            Spacer()
                        }
                        if let subline = countdown.subline {
                            Text(subline)
                                .font(.clarionBody(13))
                                .foregroundStyle(Color.ink2)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.line)
                                Capsule()
                                    .fill(Color.forest)
                                    .frame(width: max(4, geo.size.width * elapsedPct / 100))
                            }
                        }
                        .frame(height: 4)
                    }
                }
            case .overdue(_, let nextLabel, _):
                card {
                    HStack(spacing: Brand.s2) {
                        VStack(alignment: .leading, spacing: Brand.s1) {
                            HStack(spacing: Brand.s2) {
                                Eyebrow("Next draw")
                                Text(nextLabel)
                                    .font(.clarionData(13))
                                    .foregroundStyle(Color.ink)
                            }
                            if let subline = countdown.subline {
                                Text(subline)
                                    .font(.clarionBody(13))
                                    .foregroundStyle(Color.ink2)
                            }
                        }
                        Spacer()
                        Button {
                            Haptics.tap()
                            Task { await openWeb(path: "/dashboard/logbook") }
                        } label: {
                            Text("Plan it")
                                .font(.clarionLabel(13))
                                .foregroundStyle(Color.forest)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - No labs yet (the ladder's first rung gets the whole card, not a nudge)

    @ViewBuilder
    private var addLabsCard: some View {
        if case .empty = report.state {
            card {
                VStack(alignment: .leading, spacing: Brand.s3) {
                    Eyebrow("Next step", color: .forest)
                    Text("Add your labs")
                        .font(.clarionDisplay(19))
                        .foregroundStyle(Color.ink)
                    Text("Everything here calibrates to your blood — a photo or PDF of any panel works.")
                        .font(.clarionBody(14))
                        .foregroundStyle(Color.ink2)
                    Button {
                        Task { await openWeb(path: "/labs/upload") }
                    } label: {
                        Text("Add labs").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    // MARK: - Today's doses

    @ViewBuilder
    private var nextDoseCard: some View {
        if case .ready = report.state {
            let takeable = takeableStack
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
                                    .font(.clarionLabel(13))
                                    .foregroundStyle(Color.forest)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        if let next = remaining.first {
                            HStack(spacing: Brand.s3) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(next.name)
                                        .font(.clarionDisplay(16))
                                        .foregroundStyle(Color.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text("\(next.dose) · \(takeable.count - remaining.count) of \(takeable.count) taken today")
                                        .font(.clarionBody(13))
                                        .foregroundStyle(Color.ink3)
                                }
                                Spacer()
                                Button {
                                    Haptics.commit()
                                    Task { await log.toggle(next) }
                                } label: {
                                    Text("Log dose")
                                        .font(.clarionLabel(13.5))
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
                                    .font(.clarionBody(14.5))
                                    .foregroundStyle(Color.ink2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Victory / delta card (between draws)

    @ViewBuilder
    private var victoryCardView: some View {
        if let victory {
            switch victory {
            case .anticipation(let headline, let body):
                card {
                    VStack(alignment: .leading, spacing: Brand.s2) {
                        Eyebrow("Between draws")
                        Text(headline)
                            .font(.clarionDisplay(19))
                            .foregroundStyle(Color.ink)
                        Text(body)
                            .font(.clarionBody(14))
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .improved(let delta):
                victoryDeltaCard(delta, improved: true)
            case .regressed(let delta):
                victoryDeltaCard(delta, improved: false)
            }
        }
    }

    private func victoryDeltaCard(_ delta: VictoryCard.Delta, improved: Bool) -> some View {
        card {
            VStack(alignment: .leading, spacing: Brand.s3) {
                HStack {
                    Eyebrow("Between draws")
                    Spacer()
                    if improved {
                        TagPill("Improved", tone: .forest, wash: .forestWash)
                    } else {
                        TagPill("Drifting", tone: .clay, wash: .clayWash)
                    }
                }
                Text(delta.marker)
                    .font(.clarionDisplay(19))
                    .foregroundStyle(Color.ink)
                HStack(alignment: .firstTextBaseline, spacing: Brand.s2) {
                    Text(delta.from)
                        .font(.clarionData(20))
                        .foregroundStyle(Color.ink3)
                    Text("→")
                        .font(.clarionBody(15))
                        .foregroundStyle(Color.ink3)
                    Text(delta.to)
                        .font(.clarionData(24))
                        .foregroundStyle(improved ? Color.forestInk : Color.clay)
                    if !delta.unit.isEmpty {
                        Text(delta.unit)
                            .font(.clarionBody(12))
                            .foregroundStyle(Color.ink3)
                    }
                    Text("since \(delta.sinceLabel)")
                        .font(.clarionBody(12))
                        .foregroundStyle(Color.ink3)
                }
                Text(delta.body)
                    .font(.clarionBody(14))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                victoryStrip(delta.visual, improved: improved)
            }
        }
    }

    /// The before→after strip on the honest axis: optimal band wash + from/to dots.
    private func victoryStrip(_ visual: VictoryCard.Visual, improved: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (pct: Double) in w * pct / 100 }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.paperDim).frame(height: 6)
                if let bandStart = visual.bandStartPct, let bandEnd = visual.bandEndPct, bandEnd > bandStart {
                    Capsule()
                        .fill(Color.forestWash)
                        .frame(width: x(bandEnd - bandStart), height: 6)
                        .offset(x: x(bandStart))
                }
                Rectangle()
                    .fill(Color.ink4)
                    .frame(width: abs(x(visual.toPct) - x(visual.fromPct)), height: 2)
                    .offset(x: x(min(visual.fromPct, visual.toPct)))
                Circle()
                    .fill(Color.ink4)
                    .frame(width: 8, height: 8)
                    .offset(x: x(visual.fromPct) - 4)
                Circle()
                    .fill(improved ? Color.forest : Color.clay)
                    .frame(width: 10, height: 10)
                    .offset(x: x(visual.toPct) - 5)
            }
            .frame(height: 10)
        }
        .frame(height: 10)
        .padding(.top, 2)
    }

    // MARK: - The ONE nudge slot

    @ViewBuilder
    private var nudgeCard: some View {
        if let nudge {
            card {
                HStack(alignment: .top, spacing: Brand.s3) {
                    VStack(alignment: .leading, spacing: Brand.s2) {
                        Eyebrow(nudge.kicker, color: .forest)
                        Text(nudge.headline)
                            .font(.clarionDisplay(17))
                            .foregroundStyle(Color.ink)
                        Text(nudge.body)
                            .font(.clarionBody(13.5))
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Haptics.tap()
                            handleNudgeAction(nudge)
                        } label: {
                            Text(nudge.ctaLabel)
                                .font(.clarionLabel(13.5))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(
                                    LinearGradient(colors: [Color.forestBright, Color.forest], startPoint: .top, endPoint: .bottom),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(PressableStyle(haptic: false))
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    if nudge.dismissible {
                        Button {
                            Haptics.tap()
                            nudgeDismissedDay = ProtocolLogStore.todayKey()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.ink4)
                                .padding(6)
                        }
                        .buttonStyle(PressableStyle(haptic: false))
                        .accessibilityLabel("Dismiss for today")
                    }
                }
            }
        }
    }

    private func handleNudgeAction(_ nudge: HomeNudge) {
        switch nudge.href {
        case "/dashboard/analysis":
            tab = 2
        case "/dashboard/plan":
            tab = 3
        case "/labs/upload":
            Task { await openWeb(path: "/labs/upload") }
        case "/dashboard/logbook":
            Task { await openWeb(path: "/dashboard/logbook") }
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
        card {
            HStack(spacing: Brand.s2) {
                switch sync.status {
                case .idle:
                    Image(systemName: sync.lastSyncedAt == nil ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .foregroundStyle(Color.forest)
                    Text(sync.lastSyncedAt == nil ? "Not synced yet" : "Everything up to date")
                        .font(.clarionBody(14.5)).foregroundStyle(Color.ink3)
                case .syncing:
                    ProgressView().controlSize(.small)
                    Text("Syncing…").font(.clarionBody(14.5)).foregroundStyle(Color.ink3)
                case .done(let daily, let workouts, _):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.forest)
                    Text(daily == 0 && workouts == 0
                         ? "Up to date — no new wearable data"
                         : "Synced \(daily) days, \(workouts) workouts")
                        .font(.clarionBody(14.5)).foregroundStyle(Color.ink3)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.amber)
                    Text(message).font(.clarionBody(14.5)).foregroundStyle(Color.ink3)
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
        }
    }

    // MARK: - Customize affordance (a calm footer row — the Library moved to the toolbar icon,
    // so Home reads as a daily brief, not a launcher grid)

    private var customizeFooter: some View {
        Button {
            Haptics.tap()
            showCustomize = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                Text("Customize home")
                    .font(.clarionLabel(13))
            }
            .foregroundStyle(Color.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Brand.s2)
        }
        .buttonStyle(PressableStyle())
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

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Brand.s4 + 2)
            .clarionCard()
    }

    // MARK: - Library (the six reference surfaces, surfaced on Home so they're findable —
    // not hidden behind a toolbar glyph). A labeled section + 2-column grid; each tile
    // deep-links straight to its surface, with the hub kept underneath (back lands on the list).

    private var libraryGrid: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Text("LIBRARY")
                .font(.clarionLabel(11.5))
                .tracking(0.14 * 11.5)
                .foregroundStyle(Color.ink3)
                .padding(.leading, 2)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Brand.s3),
                          GridItem(.flexible(), spacing: Brand.s3)],
                spacing: Brand.s3
            ) {
                libraryTile(.labs, icon: "chart.line.uptrend.xyaxis", title: "Labs history")
                libraryTile(.biomarkers, icon: "drop", title: "Biomarkers")
                libraryTile(.dailyInputs, icon: "sun.max", title: "Daily inputs")
                libraryTile(.logbook, icon: "calendar", title: "Logbook")
                libraryTile(.guides, icon: "book", title: "Guides")
                libraryTile(.faq, icon: "questionmark.circle", title: "FAQ & support")
            }
        }
        .padding(.top, Brand.s2)
        .id("home-library")
    }

    private func libraryTile(_ route: LibraryRoute, icon: String, title: String) -> some View {
        Button {
            Haptics.tap()
            libraryRoute = route
        } label: {
            HStack(spacing: Brand.s3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.forest)
                    .frame(width: 32, height: 32)
                    .background(Color.forestWash, in: RoundedRectangle(cornerRadius: Brand.rSM))
                Text(title)
                    .font(.clarionDisplay(14.5))
                    .tracking(-0.015 * 14.5)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(Brand.s3 + 2)
            .clarionCard()
        }
        .buttonStyle(PressableStyle())
    }
}
