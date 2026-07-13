import Foundation

// =============================================================================
// Daily loop — victory card, next-draw countdown, and the ONE nudge slot.
// Swift twins of the web's src/lib/victoryCard.ts, nextDrawCountdown.ts,
// nudgeSlot.ts and homeNextStep.ts: same priority ladders, same thresholds,
// same copy. All pure functions — no stores, no network.
// =============================================================================

// MARK: - Victory / delta card (web: victoryCard.ts)

/// The single most meaningful movement across draws: a marker that moved
/// flagged → in-range ("Ferritin 34 → 57 since March. Your iron protocol
/// worked."), a supplemented marker that closed ≥20% of the gap to target,
/// HONESTLY a marker that drifted out of range, or — with a single draw —
/// next-draw anticipation instead.
enum VictoryCard: Equatable {

    /// Percent positions (0–100) on the honest axis for the before→after strip.
    struct Visual: Equatable {
        var fromPct: Double
        var toPct: Double
        var bandStartPct: Double?
        var bandEndPct: Double?
    }

    struct Delta: Equatable {
        var marker: String
        var from: String
        var to: String
        var unit: String
        var sinceLabel: String
        var body: String
        var visual: Visual
        /// Lowercased supplement base name when the marker is supplemented ("iron").
        var protocolLabel: String?
    }

    case improved(Delta)
    case regressed(Delta)
    case anticipation(headline: String, body: String)

    private static let flaggedStatuses: Set<String> = ["deficient", "low", "suboptimal", "high"]

    /// Distance from a value to the nearest edge of the optimal band (0 inside).
    static func distanceToBand(_ value: Double, optimalMin: Double?, optimalMax: Double?) -> Double {
        if let lo = optimalMin, value < lo { return lo - value }
        if let hi = optimalMax, value > hi { return value - hi }
        return 0
    }

    /// "since March" — month of the first point; adds the year when it isn't this journey's last year.
    static func sinceLabel(firstTs: String, lastTs: String) -> String {
        guard let first = parseTimestamp(firstTs) else { return "your first draw" }
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMMM"
        let month = fmt.string(from: first)
        if let last = parseTimestamp(lastTs),
           cal.component(.year, from: first) != cal.component(.year, from: last) {
            return "\(month) \(cal.component(.year, from: first))"
        }
        return month
    }

    /// Accepts full ISO timestamps or bare YYYY-MM-DD (like JS `new Date(...)`).
    static func parseTimestamp(_ ts: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: ts) { return d }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: ts) { return d }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(identifier: "UTC") // JS parses bare dates as UTC midnight
        return day.date(from: String(ts.prefix(10)))
    }

    static func buildVisual(from: Double, to: Double, optimalMin: Double?, optimalMax: Double?) -> Visual {
        var candidates = [from, to]
        if let lo = optimalMin { candidates.append(lo) }
        if let hi = optimalMax { candidates.append(hi) }
        var lo = candidates.min()!
        var hi = candidates.max()!
        var span = hi - lo
        if span == 0 { span = abs(hi) }
        if span == 0 { span = 1 }
        lo -= span * 0.12
        hi += span * 0.12
        func pct(_ v: Double) -> Double { min(100, max(0, ((v - lo) / (hi - lo)) * 100)) }
        return Visual(
            fromPct: pct(from),
            toPct: pct(to),
            bandStartPct: optimalMin.map(pct),
            bandEndPct: optimalMax.map(pct) ?? (optimalMin != nil ? 100 : nil)
        )
    }

    /// "Iron — liquid" → "iron"; "Magnesium Glycinate (200 mg)" → "magnesium glycinate".
    static func supplementBaseLabel(_ name: String) -> String {
        let head = name.split(maxSplits: 1, whereSeparator: { $0 == "—" || $0 == "(" || $0 == "," }).first.map(String.init) ?? name
        return head.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Supplement base label for a marker when the user's stack targets it, else nil.
    static func supplementedBy(_ marker: String, stack: [StackItem]) -> String? {
        let m = marker.trimmingCharacters(in: .whitespaces).lowercased()
        guard !m.isEmpty else { return nil }
        for item in stack {
            let itemMarker = (item.marker ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let itemName = item.name.lowercased()
            if !itemMarker.isEmpty, itemMarker == m || itemMarker.contains(m) || m.contains(itemMarker) {
                return supplementBaseLabel(item.name)
            }
            if itemName.contains(m) { return supplementBaseLabel(item.name) }
            // Ferritin is supplemented with iron, not "ferritin".
            if m == "ferritin", itemMarker == "iron" || itemName.contains("iron") {
                return supplementBaseLabel(item.name)
            }
        }
        return nil
    }

    private struct ImprovedCandidate {
        var marker: ReportHistoryMarker
        var isTransition: Bool
        var closure: Double
        var protocolLabel: String?
        var order: Int
        var rank: Double { (isTransition ? 1000 : 0) + closure * 100 + (protocolLabel != nil ? 1 : 0) }
    }

    private struct RegressedCandidate {
        var marker: ReportHistoryMarker
        var driftAmount: Double
        var order: Int
    }

    /// Mirrors the web's `selectVictoryCard` over the /api/report `history` field —
    /// the server already evaluated each journey's first/last point under the
    /// user's CURRENT adaptive ranges.
    static func select(history: ReportHistory, stack: [StackItem]) -> VictoryCard {
        var improved: [ImprovedCandidate] = []
        var regressed: [RegressedCandidate] = []

        for (i, j) in history.markers.enumerated() {
            guard j.points >= 2 else { continue }
            let aStatus = j.first.status.lowercased()
            let bStatus = j.last.status.lowercased()
            if aStatus == "unknown" || bStatus == "unknown" { continue }

            // Distances measured against the LATEST evaluation's band, like the web.
            let distA = distanceToBand(j.first.value, optimalMin: j.last.optimalMin, optimalMax: j.last.optimalMax)
            let distB = distanceToBand(j.last.value, optimalMin: j.last.optimalMin, optimalMax: j.last.optimalMax)
            let protocolLabel = supplementedBy(j.name, stack: stack)

            if flaggedStatuses.contains(aStatus), bStatus == "optimal" {
                improved.append(ImprovedCandidate(marker: j, isTransition: true, closure: distA > 0 ? 1 : 0, protocolLabel: protocolLabel, order: i))
                continue
            }

            if protocolLabel != nil, distA > 0, distB < distA, (distA - distB) / distA >= 0.2 {
                improved.append(ImprovedCandidate(marker: j, isTransition: false, closure: (distA - distB) / distA, protocolLabel: protocolLabel, order: i))
                continue
            }

            if aStatus == "optimal", flaggedStatuses.contains(bStatus) {
                regressed.append(RegressedCandidate(marker: j, driftAmount: distB, order: i))
            }
        }

        if !improved.isEmpty {
            // Full flagged→in-range transitions beat partial progress; supplemented ties win.
            let best = improved.sorted { a, b in
                a.rank != b.rank ? a.rank > b.rank : a.order < b.order
            }[0]
            let j = best.marker
            let body: String
            if best.isTransition {
                body = best.protocolLabel.map { "Your \($0) protocol worked." } ?? "Back in range — that's real movement."
            } else {
                body = "\(MorningBrief.jsRound(best.closure * 100))% of the gap to target closed — the protocol is pulling."
            }
            return .improved(Delta(
                marker: j.name,
                from: MorningBrief.fmtValue(j.first.value),
                to: MorningBrief.fmtValue(j.last.value),
                unit: j.unit ?? "",
                sinceLabel: sinceLabel(firstTs: j.first.dateIso, lastTs: j.last.dateIso),
                body: body,
                visual: buildVisual(from: j.first.value, to: j.last.value, optimalMin: j.last.optimalMin, optimalMax: j.last.optimalMax),
                protocolLabel: best.protocolLabel
            ))
        }

        if !regressed.isEmpty {
            let worst = regressed.sorted { a, b in
                a.driftAmount != b.driftAmount ? a.driftAmount > b.driftAmount : a.order < b.order
            }[0]
            let j = worst.marker
            return .regressed(Delta(
                marker: j.name,
                from: MorningBrief.fmtValue(j.first.value),
                to: MorningBrief.fmtValue(j.last.value),
                unit: j.unit ?? "",
                sinceLabel: sinceLabel(firstTs: j.first.dateIso, lastTs: j.last.dateIso),
                body: "Worth watching — not panicking. Your next draw says whether it's a trend.",
                visual: buildVisual(from: j.first.value, to: j.last.value, optimalMin: j.last.optimalMin, optimalMax: j.last.optimalMax),
                protocolLabel: nil
            ))
        }

        return .anticipation(
            headline: "Your baseline is set.",
            body: "One draw on file. The next one is where progress shows — every dose you log between now and then is evidence."
        )
    }
}

// MARK: - Next-draw countdown (web: nextDrawCountdown.ts)

/// Endowed progress: the elapsed portion of the last-draw → next-draw window
/// renders in forest, so the user sees protocol days already banked, not just
/// days remaining. Same date math as the web Logbook chip
/// (next = last draw + retest_weeks).
enum NextDrawCountdown: Equatable {
    case scheduled(nextIso: String, nextLabel: String, daysLeft: Int, totalDays: Int, elapsedPct: Double)
    case overdue(nextIso: String, nextLabel: String, daysOver: Int)
    case none

    /// Parse YYYY-MM-DD as a LOCAL midnight date (web's fromLocalIso).
    static func fromLocalIso(_ iso: String) -> Date? {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func toLocalIso(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func daysBetween(_ fromIso: String, _ toIso: String) -> Int? {
        guard let a = fromLocalIso(fromIso), let b = fromLocalIso(toIso) else { return nil }
        return MorningBrief.jsRound(b.timeIntervalSince(a) / 86_400)
    }

    /// Web's computeNextRetestDate: last draw + round(weeks × 7) days; default 8 weeks.
    static func computeNextRetestDate(lastDrawIso: String, retestWeeks: Double?) -> String? {
        let weeks = retestWeeks ?? 8
        guard weeks.isFinite, weeks > 0, let last = fromLocalIso(lastDrawIso) else { return nil }
        guard let target = Calendar.current.date(byAdding: .day, value: MorningBrief.jsRound(weeks * 7), to: last) else { return nil }
        return toLocalIso(target)
    }

    static func labelFor(_ iso: String) -> String {
        guard let d = fromLocalIso(iso) else { return iso }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMM d"
        return fmt.string(from: d)
    }

    static func build(lastDrawIso: String?, retestWeeks: Double?, todayIso: String) -> NextDrawCountdown {
        guard let lastDrawIso, !lastDrawIso.isEmpty,
              let nextIso = computeNextRetestDate(lastDrawIso: lastDrawIso, retestWeeks: retestWeeks),
              let daysLeft = daysBetween(todayIso, nextIso)
        else { return .none }

        let nextLabel = labelFor(nextIso)
        if daysLeft < 0 {
            return .overdue(nextIso: nextIso, nextLabel: nextLabel, daysOver: -daysLeft)
        }

        let totalDays = max(1, daysBetween(lastDrawIso, nextIso) ?? 1)
        let elapsed = min(totalDays, max(0, totalDays - daysLeft))
        let elapsedPct = (Double(elapsed) / Double(totalDays) * 1000).rounded() / 10
        return .scheduled(nextIso: nextIso, nextLabel: nextLabel, daysLeft: daysLeft, totalDays: totalDays, elapsedPct: elapsedPct)
    }

    /// The web's countdown sub-line copy, verbatim.
    var subline: String? {
        switch self {
        case .scheduled(_, _, let daysLeft, _, _):
            return daysLeft == 0
                ? "draw day — go get your proof"
                : "\(daysLeft) day\(daysLeft == 1 ? "" : "s") of protocol between now and proof"
        case .overdue(_, _, let daysOver):
            return "\(daysOver) day\(daysOver == 1 ? "" : "s") past — the proof is waiting."
        case .none:
            return nil
        }
    }
}

// MARK: - Next step ladder (web: homeNextStep.ts)

/// The Home "next step" spine: one always-current action that answers
/// "what do I do now?". Exactly one step is ever surfaced.
struct HomeNextStep: Equatable {
    var id: String // add-labs | log-cabinet | read-report | see-plan | log-doses | on-track
    var label: String
    var why: String
    /// Web-route destination; HomeView maps these onto tabs / web links.
    var href: String?
    var done: Bool

    static func compute(
        hasBloodwork: Bool,
        /// nil = unknown on this client (the cabinet is a web surface) — the step is skipped.
        cabinetCount: Int?,
        reportViewed: Bool,
        planViewed: Bool,
        protocolCount: Int,
        protocolCheckedCount: Int
    ) -> HomeNextStep {
        if !hasBloodwork {
            return HomeNextStep(
                id: "add-labs",
                label: "Add your labs",
                why: "Everything here calibrates to your blood — a photo or PDF of any panel works.",
                href: "/labs/upload",
                done: false
            )
        }
        if !reportViewed {
            return HomeNextStep(
                id: "read-report",
                label: "Read your report",
                why: "Your panel is analyzed — see what your blood says in plain English.",
                href: "/dashboard/analysis",
                done: false
            )
        }
        if cabinetCount == 0 {
            return HomeNextStep(
                id: "log-cabinet",
                label: "Log what you take",
                why: "Tell Clarion your current supplements so it can sort keep vs. skip against your labs.",
                href: nil,
                done: false
            )
        }
        if !planViewed {
            return HomeNextStep(
                id: "see-plan",
                label: "See what to take & skip",
                why: "The Supplements tab grades your shelf against your labs and fills the gaps.",
                href: "/dashboard/plan",
                done: false
            )
        }
        if protocolCount > 0, protocolCheckedCount < protocolCount {
            return HomeNextStep(
                id: "log-doses",
                label: "Log today's doses",
                why: "\(protocolCount - protocolCheckedCount) of \(protocolCount) still unchecked today.",
                href: "/dashboard#protocol",
                done: false
            )
        }
        return HomeNextStep(
            id: "on-track",
            label: "You're on track",
            why: "Doses logged, plan set. Next milestone: your retest.",
            href: nil,
            done: true
        )
    }
}

// MARK: - Retest countdown (web: dashboard page's retestCountdown memo)

/// Weeks until/past the suggested retest, from the last bloodwork timestamp +
/// profiles.retest_weeks — the nudge slot's retest input.
enum RetestCountdown: Equatable {
    case until(weeks: Int)
    case overdue(weeks: Int)

    static func compute(lastBloodworkAt: Date?, retestWeeks: Double?, now: Date = Date()) -> RetestCountdown? {
        guard let lastBloodworkAt, let retestWeeks, retestWeeks > 0 else { return nil }
        let week: TimeInterval = 7 * 24 * 60 * 60
        let due = lastBloodworkAt.timeIntervalSince1970 + retestWeeks * week
        let nowS = now.timeIntervalSince1970
        if nowS < due {
            return .until(weeks: Int(ceil((due - nowS) / week)))
        }
        return .overdue(weeks: Int(ceil((nowS - due) / week)))
    }
}

// MARK: - The ONE nudge slot (web: nudgeSlot.ts)

/// A priority queue that selects EXACTLY ONE nudge per day:
///
///   critical supply-out  >  next step (orientation ladder)  >  retest due
///   >  gentle log re-engage  >  supply merely-low (fallback)
///
/// Dismissal is per local day — a dismissed day shows nothing until tomorrow
/// (one nudge per day means one, not a fallback chain).
struct HomeNudge: Equatable {
    /// Same storage key as the web, so the convention stays recognizable.
    static let dismissedDayKey = "clarion_home_nudge_dismissed_day_v1"

    enum Kind: String {
        case supply
        case nextStep = "next-step"
        case retest
        case log
    }

    struct RunningLowItem: Equatable {
        var name: String
        /// daysLeft ≤ 0 = out.
        var daysLeft: Int
    }

    struct Input {
        /// Running-low items, worst first (empty on iOS — no inventory surface yet).
        var runningLow: [RunningLowItem] = []
        /// Result of HomeNextStep.compute (or nil before hydration).
        var nextStep: HomeNextStep?
        var retest: RetestCountdown?
        var daysSinceLog: Int?
        var protocolTodayComplete: Bool?
        var hasStack: Bool
        /// True when today's nudge was dismissed — the slot stays empty until tomorrow.
        var dismissedToday: Bool = false
    }

    var kind: Kind
    /// Small uppercase label above the headline.
    var kicker: String
    var headline: String
    var body: String
    var ctaLabel: String
    /// nil → the view wires an in-app action.
    var href: String?
    var dismissible: Bool

    /// Onboarding-ladder steps that belong in the slot. `log-doses` is excluded —
    /// the Today's-doses card already carries it, and `on-track` is not a nudge.
    private static let orientationStepIds: Set<String> = ["add-labs", "read-report", "log-cabinet", "see-plan"]

    private static let nextStepCta: [String: String] = [
        "add-labs": "Add labs",
        "read-report": "Open your report",
        "log-cabinet": "Log what you take",
        "see-plan": "See the plan",
    ]

    private static func supplyNudge(_ items: [RunningLowItem], critical: Bool) -> HomeNudge {
        let first = items[0]
        let headline: String
        if critical {
            headline = items.count > 1 ? "\(items.count) supplements are out." : "\(first.name) is out."
        } else {
            headline = items.count > 1 ? "Running low on \(items.count) items." : "\(first.name) is running low."
        }
        let body = critical
            ? "You'll miss tomorrow's dose without a refill."
            : items.prefix(2).map { "\($0.name) has \($0.daysLeft)d left" }.joined(separator: " · ") + "."
        return HomeNudge(
            kind: .supply,
            kicker: "Running low",
            headline: headline,
            body: body,
            ctaLabel: items.count > 1 ? "Restock \(items.count)" : "Reorder \(first.name)",
            href: nil,
            dismissible: !critical
        )
    }

    static func pick(_ input: Input) -> HomeNudge? {
        if input.dismissedToday { return nil }

        // 1 — critical supply-out: doses stop without a refill.
        let out = input.runningLow.filter { $0.daysLeft <= 0 }
        if !out.isEmpty { return supplyNudge(out, critical: true) }

        // 2 — orientation next step (unread report, empty cabinet, unseen plan).
        if let step = input.nextStep, !step.done, orientationStepIds.contains(step.id) {
            return HomeNudge(
                kind: .nextStep,
                kicker: "Next step",
                headline: step.label,
                body: step.why,
                ctaLabel: nextStepCta[step.id] ?? "Open",
                href: step.href,
                dismissible: true
            )
        }

        // 3 — retest due (overdue, or the window opens within 2 weeks).
        if let retest = input.retest {
            switch retest {
            case .overdue(let w):
                return HomeNudge(
                    kind: .retest,
                    kicker: "Retest",
                    headline: "Your retest is \(w) week\(w == 1 ? "" : "s") past due.",
                    body: "Book it and turn these weeks of protocol into proof.",
                    ctaLabel: "Plan your retest",
                    href: "/dashboard/logbook",
                    dismissible: true
                )
            case .until(let w):
                if w > 0, w <= 2 {
                    return HomeNudge(
                        kind: .retest,
                        kicker: "Retest",
                        headline: "Retest window opens in \(w) week\(w == 1 ? "" : "s").",
                        body: "Get the draw on the calendar while it's easy.",
                        ctaLabel: "Open logbook",
                        href: "/dashboard/logbook",
                        dismissible: true
                    )
                }
            }
        }

        // 4 — gentle log re-engage (the old guilt banner, rewritten).
        if input.hasStack,
           input.protocolTodayComplete != true,
           let daysSinceLog = input.daysSinceLog,
           daysSinceLog >= 2 {
            return HomeNudge(
                kind: .log,
                kicker: "Today",
                headline: "Pick up where you left off",
                body: "Today's doses are one tap away.",
                ctaLabel: "Log now",
                href: "/dashboard#protocol",
                dismissible: true
            )
        }

        // 5 — merely-low supply, only when nothing above claimed the slot.
        if !input.runningLow.isEmpty { return supplyNudge(input.runningLow, critical: false) }

        return nil
    }
}
