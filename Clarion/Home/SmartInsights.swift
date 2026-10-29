import Foundation

// =============================================================================
// Smart insights — Swift twin of the web's src/lib/smartInsights.ts.
// Same rules, same thresholds, same copy, same guardrails:
//   one a day · earn it first (3 days in, 5+ logged days) · patterns not
//   diagnoses · always "Why am I seeing this?" · "Not now" snoozes 7 days and
//   the third snooze turns the rule off · Drained 5+ days escalates to a
//   doctor with no product suggestion · positive at least as often as fixes.
// Pure engine + a tiny UserDefaults-backed state store.
// =============================================================================

enum InsightTone: String, Codable { case fix, nudge, positive }

enum InsightRuleId: String, Codable, CaseIterable {
    case tiredMissedDoses = "tired_missed_doses"
    case feelingGoodStreak = "feeling_good_streak"
    case tiredDosesFine = "tired_doses_fine"
    case recoveryLagging = "recovery_lagging"
    case runningLow = "running_low"
    case retestWindow = "retest_window"
    case markerMoved = "marker_moved"
    case quietCheckIns = "quiet_check_ins"
    case escalateDrained = "escalate_drained"

    var label: String {
        switch self {
        case .tiredMissedDoses: return "Tired and missed doses"
        case .feelingGoodStreak: return "Feeling good on a streak"
        case .tiredDosesFine: return "Tired with doses on track"
        case .recoveryLagging: return "Recovery lagging"
        case .runningLow: return "Running low"
        case .retestWindow: return "Retest window"
        case .markerMoved: return "A marker moved"
        case .quietCheckIns: return "Quiet check-ins"
        case .escalateDrained: return "Drained for days"
        }
    }
}

struct SmartInsight: Equatable {
    enum Action: String { case remindTonight, reorder, logRestDay, checkIn, keepGoing }
    struct Cta: Equatable {
        var label: String
        /// Web route when the CTA navigates; nil → `action` runs in-app.
        var href: String?
        var action: Action?
    }

    var id: String
    var ruleId: InsightRuleId
    var tone: InsightTone
    var title: String
    var body: String
    var dataViz: String?
    var primaryCta: Cta?
    var whyText: String
    var cooldownDays: Int
    var noProducts: Bool = false

    var kicker: String {
        switch tone {
        case .fix: return "Something to fix"
        case .nudge: return "Worth a look"
        case .positive: return "Nice work"
        }
    }
}

struct InsightCheckIn: Equatable {
    var date: String
    /// 1 Drained … 5 Great
    var feeling: Int?
    var trained: Bool?
}

struct InsightState: Codable, Equatable {
    var lastShownDay: String?
    var lastShownId: String?
    var recentTones: [InsightTone] = []
    var lastShownByRule: [String: String] = [:]
    var snoozedUntil: [String: String] = [:]
    var dismissCount: [String: Int] = [:]
    var disabled: [String] = []
    var seenLabMoves: [String] = []

    static let empty = InsightState()

    func isDisabled(_ r: InsightRuleId) -> Bool { disabled.contains(r.rawValue) }
}

enum SmartInsights {

    struct StackItem { var logKey: String; var name: String; var presetId: String? }
    struct DoseLogDay { var date: String; var checks: [String: Bool] }
    struct WearableDay { var date: String; var readiness: Double?; var hrv: Double? }
    enum NextDraw { case scheduled(daysLeft: Int), overdue(daysOver: Int), none }
    struct LabMove {
        var marker: String; var from: String; var to: String; var unit: String
        var improved: Bool; var protocolLabel: String?; var panelKey: String
    }

    struct Input {
        var dateKey: String
        var stack: [StackItem]
        var doseLog: [DoseLogDay]
        var checkIns: [InsightCheckIn]
        var wearable: [WearableDay]?
        var runningLow: [(name: String, daysLeft: Int)]
        var nextDraw: NextDraw?
        var labMove: LabMove?
        var firstActivityDay: String?
        var state: InsightState
    }

    enum Reason { case shown, notEarned, alreadyToday, noneQualified }
    struct Decision { var insight: SmartInsight?; var reason: Reason }

    /// Editorial map — which supplements can line up with which symptom. Charlie signs off.
    static let symptomByPreset: [String: (nutrient: String, symptom: String)] = [
        "magnesium": ("magnesium", "poor sleep and feeling tired"),
        "iron": ("iron", "feeling tired or flat"),
        "vitamin_d": ("vitamin D", "low energy"),
        "b12": ("B12", "tiredness"),
    ]

    // MARK: - Day math (UTC day numbers, like the web)

    static func dayNumber(_ key: String) -> Int {
        let p = key.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return 0 }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        guard let d = utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return 0 }
        return Int(floor(d.timeIntervalSince1970 / 86_400))
    }

    static func addDays(_ key: String, _ n: Int) -> String {
        let d = Date(timeIntervalSince1970: Double(dayNumber(key) + n) * 86_400)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func lastNDays(_ key: String, _ n: Int) -> [String] {
        (0..<n).map { addDays(key, -(n - 1 - $0)) }
    }

    private static func fmtDays(_ n: Int) -> String { "\(n) day\(n == 1 ? "" : "s")" }

    // MARK: - Context

    private struct Ctx {
        let input: Input
        let logByDay: [String: [String: Bool]]
        let checkByDay: [String: InsightCheckIn]
        let wearByDay: [String: WearableDay]
        let loggedDays: Int

        init(_ input: Input) {
            self.input = input
            var log: [String: [String: Bool]] = [:]
            for d in input.doseLog { log[d.date, default: [:]].merge(d.checks) { _, new in new } }
            logByDay = log
            checkByDay = Dictionary(input.checkIns.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
            wearByDay = Dictionary((input.wearable ?? []).map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
            loggedDays = SmartInsights.lastNDays(input.dateKey, 14).filter { (log[$0] ?? [:]).values.contains(true) }.count
        }

        func todayFeeling() -> Int? { checkByDay[input.dateKey]?.feeling }

        func feelingRun(_ pred: (Int) -> Bool) -> Int {
            var run = 0; var day = input.dateKey
            for _ in 0..<30 {
                guard let f = checkByDay[day]?.feeling, pred(f) else { break }
                run += 1; day = SmartInsights.addDays(day, -1)
            }
            return run
        }

        func trainedRun() -> Int {
            var run = 0; var day = input.dateKey
            for _ in 0..<30 {
                guard checkByDay[day]?.trained == true else { break }
                run += 1; day = SmartInsights.addDays(day, -1)
            }
            return run
        }

        func adherence(_ n: Int) -> (pct: Int, days: Int) {
            guard !input.stack.isEmpty else { return (0, 0) }
            var taken = 0, possible = 0, days = 0
            for d in SmartInsights.lastNDays(input.dateKey, n) {
                guard let log = logByDay[d], log.values.contains(true) else { continue }
                days += 1
                for s in input.stack { possible += 1; if log[s.logKey] == true { taken += 1 } }
            }
            return (possible > 0 ? Int((Double(taken) / Double(possible) * 100).rounded()) : 0, days)
        }

        func missedNights(_ item: StackItem, _ n: Int) -> (missed: Int, days: Int) {
            var missed = 0, days = 0
            for d in SmartInsights.lastNDays(SmartInsights.addDays(input.dateKey, -1), n) {
                guard let log = logByDay[d] else { continue }
                days += 1
                if log[item.logKey] != true { missed += 1 }
            }
            return (missed, days)
        }

        func cleanStreak() -> Int {
            guard !input.stack.isEmpty else { return 0 }
            var streak = 0; var day = input.dateKey
            let todayClean = logByDay[day].map { log in input.stack.allSatisfy { log[$0.logKey] == true } } ?? false
            if !todayClean { day = SmartInsights.addDays(day, -1) }
            for _ in 0..<60 {
                guard let log = logByDay[day], input.stack.allSatisfy({ log[$0.logKey] == true }) else { break }
                streak += 1; day = SmartInsights.addDays(day, -1)
            }
            return streak
        }
    }

    private static func avg(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

    // MARK: - Rules

    private struct Rule { var id: InsightRuleId; var cooldown: Int; var evaluate: (Ctx) -> SmartInsight? }

    private static let rules: [Rule] = [
        Rule(id: .escalateDrained, cooldown: 7) { ctx in
            let run = ctx.feelingRun { $0 == 1 }
            guard run >= 5 else { return nil }
            return SmartInsight(
                id: "\(ctx.input.dateKey):escalate_drained", ruleId: .escalateDrained, tone: .nudge,
                title: "Drained \(run) days running.",
                body: "That is worth a conversation. Talk to a doctor if this keeps up, and bring your latest labs.",
                dataViz: "Feeling: Drained \(run) days in a row",
                primaryCta: .init(label: "Ask your doctor", href: "/dashboard/lab-request"),
                whyText: "You logged “Drained” on \(run) check-ins in a row, ending today. Clarion does not suggest products when this happens.",
                cooldownDays: 7, noProducts: true)
        },
        Rule(id: .tiredMissedDoses, cooldown: 5) { ctx in
            guard let f = ctx.todayFeeling(), f <= 2 else { return nil }
            var best: (item: StackItem, missed: Int, days: Int, map: (nutrient: String, symptom: String))?
            for item in ctx.input.stack {
                guard let pid = item.presetId, let map = symptomByPreset[pid] else { continue }
                let m = ctx.missedNights(item, 5)
                guard m.days >= 3, m.missed >= 2 else { continue }
                if best == nil || m.missed > best!.missed { best = (item, m.missed, m.days, map) }
            }
            guard let b = best else { return nil }
            let word = f == 1 ? "Drained" : "Tired"
            return SmartInsight(
                id: "\(ctx.input.dateKey):tired_missed_doses:\(b.item.logKey)", ruleId: .tiredMissedDoses, tone: .fix,
                title: "You’ve missed \(b.item.name) \(b.missed) of the last \(b.days) nights.",
                body: "Low \(b.map.nutrient) can show up as \(b.map.symptom). It’s one possible reason, not a diagnosis.",
                dataViz: "\(b.item.name): \(b.days - b.missed) of \(b.days) nights · today: \(word)",
                primaryCta: .init(label: "Remind me tonight", action: .remindTonight),
                whyText: "You checked in “\(word)” today, and your dose log shows \(b.item.name) missed on \(b.missed) of the last \(b.days) logged days.",
                cooldownDays: 5)
        },
        Rule(id: .runningLow, cooldown: 4) { ctx in
            let low = ctx.input.runningLow.filter { $0.daysLeft <= 5 }
            guard let first = low.first else { return nil }
            let out = first.daysLeft <= 0
            return SmartInsight(
                id: "\(ctx.input.dateKey):running_low:\(first.name)", ruleId: .runningLow, tone: .fix,
                title: out ? "\(first.name) is out." : "About \(fmtDays(first.daysLeft)) of \(first.name) left.",
                body: out ? "Reorder now so you don’t miss another day." : "Reorder now so you don’t miss a day.",
                dataViz: low.prefix(3).map { "\($0.name) · \($0.daysLeft <= 0 ? "out" : "\($0.daysLeft)d")" }.joined(separator: "  "),
                primaryCta: .init(label: "Reorder", action: .reorder),
                whyText: "Your logbook supply count for \(first.name) is \(out ? "zero" : "\(first.daysLeft) days") at your current dose.",
                cooldownDays: 4)
        },
        Rule(id: .recoveryLagging, cooldown: 5) { ctx in
            let run = ctx.trainedRun()
            guard run >= 3, let wear = ctx.input.wearable, !wear.isEmpty else { return nil }
            guard let today = ctx.wearByDay[ctx.input.dateKey] ?? ctx.wearByDay[addDays(ctx.input.dateKey, -1)], let hrv = today.hrv else { return nil }
            let baseVals = lastNDays(addDays(ctx.input.dateKey, -1), 14).compactMap { ctx.wearByDay[$0]?.hrv }
            guard let base = avg(baseVals), base > 0 else { return nil }
            let pct = Int(((base - hrv) / base * 100).rounded())
            guard pct >= 10 else { return nil }
            return SmartInsight(
                id: "\(ctx.input.dateKey):recovery_lagging", ruleId: .recoveryLagging, tone: .nudge,
                title: "Your HRV is \(pct)% under your usual after \(run) training days in a row.",
                body: "A lighter day could help you recover.",
                dataViz: "HRV \(Int(hrv.rounded())) ms vs \(Int(base.rounded())) ms 14-day average · trained \(run) days",
                primaryCta: .init(label: "Log a rest day", action: .logRestDay),
                whyText: "You answered “Trained” \(run) days in a row, and your latest HRV (\(Int(hrv.rounded())) ms) is \(pct)% below your 14-day average (\(Int(base.rounded())) ms).",
                cooldownDays: 5)
        },
        Rule(id: .tiredDosesFine, cooldown: 7) { ctx in
            let run = ctx.feelingRun { $0 <= 2 }
            guard run >= 3 else { return nil }
            let a = ctx.adherence(7)
            guard a.days >= 3, a.pct >= 80 else { return nil }
            return SmartInsight(
                id: "\(ctx.input.dateKey):tired_doses_fine", ruleId: .tiredDosesFine, tone: .nudge,
                title: "You’ve felt tired three days running even with your doses on track.",
                body: "Worth mentioning at your next draw, or sooner if it keeps up.",
                dataViz: "Tired \(run) days · doses \(a.pct)% over \(a.days) logged days",
                primaryCta: .init(label: "See my labs", href: "/dashboard/analysis"),
                whyText: "Your last \(run) check-ins were Tired or Drained, and your dose log shows \(a.pct)% of doses taken across the last \(a.days) logged days.",
                cooldownDays: 7)
        },
        Rule(id: .retestWindow, cooldown: 7) { ctx in
            guard let d = ctx.input.nextDraw else { return nil }
            switch d {
            case .scheduled(let daysLeft) where daysLeft <= 14:
                return SmartInsight(
                    id: "\(ctx.input.dateKey):retest_window", ruleId: .retestWindow, tone: .nudge,
                    title: daysLeft <= 0 ? "Your retest is today." : "Your retest is in \(fmtDays(daysLeft)).",
                    body: "Book it now so you can see what moved.", dataViz: nil,
                    primaryCta: .init(label: "Plan your retest", href: "/dashboard/lab-request"),
                    whyText: "Your next draw is scheduled \(daysLeft) days from today, based on your last draw date and your retest interval.",
                    cooldownDays: 7)
            case .overdue(let daysOver):
                let weeks = max(1, Int((Double(daysOver) / 7).rounded()))
                return SmartInsight(
                    id: "\(ctx.input.dateKey):retest_overdue", ruleId: .retestWindow, tone: .nudge,
                    title: "Your retest is \(weeks) week\(weeks == 1 ? "" : "s") past due.",
                    body: "A new draw shows whether the protocol is working.", dataViz: nil,
                    primaryCta: .init(label: "Plan your retest", href: "/dashboard/lab-request"),
                    whyText: "Your retest date passed \(daysOver) days ago, based on your last draw date and your retest interval.",
                    cooldownDays: 7)
            default: return nil
            }
        },
        Rule(id: .quietCheckIns, cooldown: 5) { ctx in
            let days = lastNDays(ctx.input.dateKey, 3)
            guard !days.contains(where: { ctx.checkByDay[$0]?.feeling != nil }) else { return nil }
            let logged = days.filter { (ctx.logByDay[$0] ?? [:]).values.contains(true) }.count
            guard logged >= 2, !ctx.input.checkIns.isEmpty else { return nil }
            return SmartInsight(
                id: "\(ctx.input.dateKey):quiet_check_ins", ruleId: .quietCheckIns, tone: .nudge,
                title: "Three days without a check-in.",
                body: "A quick tap helps Clarion connect how you feel to what you take.",
                dataViz: "Doses logged \(logged) of the last 3 days · check-ins 0",
                primaryCta: .init(label: "Check in", action: .checkIn),
                whyText: "You logged doses on \(logged) of the last 3 days but did not answer “How are you feeling?” on any of them.",
                cooldownDays: 5)
        },
        Rule(id: .markerMoved, cooldown: 0) { ctx in
            guard let m = ctx.input.labMove, !ctx.input.state.seenLabMoves.contains(m.panelKey) else { return nil }
            let body: String = m.improved
                ? (m.protocolLabel.map { "Your \($0) protocol worked." } ?? "That is the direction you wanted.")
                : "Worth watching, not panicking."
            return SmartInsight(
                id: "\(ctx.input.dateKey):marker_moved:\(m.panelKey)", ruleId: .markerMoved, tone: .positive,
                title: m.improved ? "\(m.marker) went from \(m.from) to \(m.to) \(m.unit)." : "\(m.marker) slipped from \(m.from) to \(m.to) \(m.unit).",
                body: body, dataViz: nil,
                primaryCta: .init(label: "Open report", href: "/dashboard/analysis"),
                whyText: "Your newest upload shows \(m.marker) at \(m.to) \(m.unit); the draw before it was \(m.from) \(m.unit). \(m.improved ? "It crossed into" : "It moved out of") your optimal band.",
                cooldownDays: 0)
        },
        Rule(id: .feelingGoodStreak, cooldown: 5) { ctx in
            guard let f = ctx.todayFeeling(), f >= 4 else { return nil }
            let streak = ctx.cleanStreak()
            guard streak >= 5 else { return nil }
            var readinessLine = ""
            var viz = "\(streak) days, no missed dose"
            if let wear = ctx.input.wearable, !wear.isEmpty {
                let inStreak = lastNDays(ctx.input.dateKey, streak).compactMap { ctx.wearByDay[$0]?.readiness }
                let before = lastNDays(addDays(ctx.input.dateKey, -streak), 14).compactMap { ctx.wearByDay[$0]?.readiness }
                if let a = avg(inStreak), let b = avg(before), inStreak.count >= 3, before.count >= 3, a - b >= 1 {
                    let x = Int((a - b).rounded())
                    readinessLine = " Your readiness has averaged \(x) point\(x == 1 ? "" : "s") higher since your streak started."
                    viz += " · readiness \(Int(b.rounded())) → \(Int(a.rounded()))"
                }
            }
            return SmartInsight(
                id: "\(ctx.input.dateKey):feeling_good_streak", ruleId: .feelingGoodStreak, tone: .positive,
                title: "\(streak) days without a missed dose.",
                body: ("You checked in feeling \(f == 5 ? "great" : "good")." + readinessLine).trimmingCharacters(in: .whitespaces),
                dataViz: viz,
                primaryCta: .init(label: "Keep it going", action: .keepGoing),
                whyText: "Your dose log shows every supplement taken for \(streak) days in a row, and today’s check-in was \(f == 5 ? "Great" : "Good").\(readinessLine.isEmpty ? "" : " Readiness is averaged from your wearable.")",
                cooldownDays: 5)
        },
    ]

    // MARK: - Pick

    static func pick(_ input: Input) -> Decision {
        let ctx = Ctx(input)
        let state = input.state
        let daysIn = input.firstActivityDay.map { dayNumber(input.dateKey) - dayNumber($0) } ?? 0
        guard input.firstActivityDay != nil, daysIn >= 3, ctx.loggedDays >= 5 else { return Decision(insight: nil, reason: .notEarned) }

        if state.lastShownDay == input.dateKey {
            let same = rules.lazy.compactMap { $0.evaluate(ctx) }.first { $0.id == state.lastShownId }
            return same.map { Decision(insight: $0, reason: .shown) } ?? Decision(insight: nil, reason: .alreadyToday)
        }

        var candidates: [SmartInsight] = []
        for rule in rules {
            if state.isDisabled(rule.id) { continue }
            if let s = state.snoozedUntil[rule.id.rawValue], s > input.dateKey { continue }
            if let last = state.lastShownByRule[rule.id.rawValue], rule.cooldown > 0, dayNumber(input.dateKey) - dayNumber(last) < rule.cooldown { continue }
            if let out = rule.evaluate(ctx) { candidates.append(out) }
        }
        guard !candidates.isEmpty else { return Decision(insight: nil, reason: .noneQualified) }
        if let esc = candidates.first(where: { $0.ruleId == .escalateDrained }) { return Decision(insight: esc, reason: .shown) }
        let lastTwo = state.recentTones.suffix(2)
        if lastTwo.count == 2, lastTwo.allSatisfy({ $0 == .fix }), let pos = candidates.first(where: { $0.tone == .positive }) {
            return Decision(insight: pos, reason: .shown)
        }
        let rank: [InsightTone: Int] = [.fix: 0, .nudge: 1, .positive: 2]
        let best = candidates.min { (rank[$0.tone] ?? 9) < (rank[$1.tone] ?? 9) }
        return Decision(insight: best, reason: .shown)
    }

    // MARK: - State transitions

    static func markShown(_ state: InsightState, _ insight: SmartInsight, dateKey: String, labPanelKey: String? = nil) -> InsightState {
        guard state.lastShownId != insight.id else { return state }
        var s = state
        s.lastShownDay = dateKey
        s.lastShownId = insight.id
        s.recentTones = Array((s.recentTones + [insight.tone]).suffix(2))
        s.lastShownByRule[insight.ruleId.rawValue] = dateKey
        if insight.ruleId == .markerMoved, let k = labPanelKey, !s.seenLabMoves.contains(k) { s.seenLabMoves.append(k) }
        return s
    }

    static func snooze(_ state: InsightState, _ rule: InsightRuleId, dateKey: String) -> InsightState {
        var s = state
        let count = (s.dismissCount[rule.rawValue] ?? 0) + 1
        s.dismissCount[rule.rawValue] = count
        s.snoozedUntil[rule.rawValue] = addDays(dateKey, 7)
        if count >= 3, !s.disabled.contains(rule.rawValue) { s.disabled.append(rule.rawValue) }
        s.lastShownDay = dateKey
        s.lastShownId = nil
        return s
    }

    static func enable(_ state: InsightState, _ rule: InsightRuleId) -> InsightState {
        var s = state
        s.disabled.removeAll { $0 == rule.rawValue }
        s.dismissCount[rule.rawValue] = 0
        s.snoozedUntil[rule.rawValue] = nil
        return s
    }
}

// MARK: - Device-local state (web: smartInsightsClient.ts)

@MainActor
final class InsightStateStore: ObservableObject {
    @Published private(set) var state: InsightState
    private let userId: String
    private var stateKey: String { "clarion_insights_state_v1_\(userId)" }
    private var firstKey: String { "clarion_insights_first_day_v1_\(userId)" }
    private var eventsKey: String { "clarion_insights_events_v1_\(userId)" }

    init(userId: String?) {
        self.userId = userId ?? "demo"
        let key = "clarion_insights_state_v1_\(userId ?? "demo")"
        if let data = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(InsightState.self, from: data) {
            state = s
        } else {
            state = .empty
        }
    }

    func update(_ next: InsightState) {
        guard next != state else { return }
        state = next
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: stateKey) }
    }

    /// "Earn it first" clock — oldest dose-log day, else the first day this device saw activity.
    func firstActivityDay(oldestLogDay: String?, todayKey: String) -> String {
        let stored = UserDefaults.standard.string(forKey: firstKey)
        let candidate: String
        if let o = oldestLogDay, stored == nil || o < stored! { candidate = o } else { candidate = stored ?? todayKey }
        if candidate != stored { UserDefaults.standard.set(candidate, forKey: firstKey) }
        return candidate
    }

    /// shown / tapped / snoozed per rule — kept small, for tuning the copy and thresholds.
    func logEvent(_ rule: InsightRuleId, _ kind: String) {
        var events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        events.append("\(ISO8601DateFormatter().string(from: Date()))|\(rule.rawValue)|\(kind)")
        UserDefaults.standard.set(Array(events.suffix(200)), forKey: eventsKey)
    }

    /// Check-in history as FeelingStore / the trained flag store it (per user + local day).
    static func checkIns(userId: String?, todayKey: String, days: Int = 30) -> [InsightCheckIn] {
        let uid = userId ?? "demo"
        var out: [InsightCheckIn] = []
        for i in 0..<days {
            let date = SmartInsights.addDays(todayKey, -i)
            let f = UserDefaults.standard.integer(forKey: "clarion_feeling_\(uid)_\(date)")
            let w = UserDefaults.standard.string(forKey: "clarion_workout_\(uid)_\(date)")
            let feeling: Int? = (1...5).contains(f) ? f : nil
            let trained: Bool? = w == "yes" ? true : w == "rest" ? false : nil
            if feeling != nil || trained != nil { out.append(.init(date: date, feeling: feeling, trained: trained)) }
        }
        return out
    }
}
