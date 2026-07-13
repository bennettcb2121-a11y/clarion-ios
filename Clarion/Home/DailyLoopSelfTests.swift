import Foundation

#if DEBUG
/// No test target ships in this hand-rolled project, so the daily-loop logic is
/// verified by an assertion block that runs once at launch in DEBUG builds —
/// a failed expectation crashes the debug app immediately (and therefore fails
/// the screenshot pass). Cases mirror the web suites (morningBrief.test.ts,
/// victoryCard.test.ts, nextDrawCountdown.test.ts, nudgeSlot.test.ts).
enum DailyLoopSelfTests {

    static func run() {
        formatters()
        morningBrief()
        countdown()
        victory()
        nudge()
        #if targetEnvironment(simulator)
        print("[DailyLoopSelfTests] all assertions passed")
        #endif
    }

    private static func formatters() {
        assert(MorningBrief.fmtValue(34) == "34")
        assert(MorningBrief.fmtValue(46.7) == "46.7")
        assert(MorningBrief.fmtValue(5.04) == "5") // toFixed(1) → "5.0" → "5"
        assert(MorningBrief.fmtSleep(437) == "7h 17m")
        assert(MorningBrief.fmtSleep(425.5) == "7h 06m")
        assert(MorningBrief.fmtSleep(42) == "42m")
        assert(MorningBrief.jsRound(-2.5) == -2) // JS half-up, not away-from-zero
        assert(MorningBrief.readinessWordFor(82) == "Well-recovered")
        assert(MorningBrief.readinessWordFor(49) == "Under-recovered")
    }

    private static func morningBrief() {
        let ferritinLow = MorningBrief.Marker(name: "Ferritin", value: 34, status: "low", optimalMin: 50, optimalMax: 150)

        // Blood-only day: no wearable → protocol line + blood pool insight.
        let bloodOnly = MorningBrief.build(MorningBrief.Input(
            dateKey: "2026-07-12",
            daily: nil,
            workouts: [],
            markers: [ferritinLow],
            stackNames: ["Iron — gentle (bisglycinate)"],
            protocolState: .init(total: 5, done: 2, streakDays: 4)
        ))
        assert(!bloodOnly.wearableDay && bloodOnly.readiness == nil)
        assert(bloodOnly.protocolLine == "2 of 5 logged today · 4-day streak")
        assert(bloodOnly.insight?.text.contains("Ferritin is at 34 — target 50–150.") == true)

        // Wearable day with a falling HRV over low ferritin (iron already in the stack).
        var daily: [WearableDailyMetrics] = []
        for i in 0..<8 {
            var d = WearableDailyMetrics(date: String(format: "2026-07-%02d", 5 + i))
            d.hrv = i < 4 ? 80 : 60 // prior mean 80 → recent mean 60: −25%, falling
            d.readinessScore = 82
            daily.append(d)
        }
        let cross = MorningBrief.build(MorningBrief.Input(
            dateKey: "2026-07-12",
            daily: daily,
            workouts: [],
            markers: [ferritinLow],
            stackNames: ["Iron — gentle (bisglycinate)"],
            protocolState: .init(total: 3, done: 0, streakDays: 0)
        ))
        assert(cross.wearableDay && cross.readiness == 82 && cross.readinessWord == "Well-recovered")
        assert(cross.insight?.id == "iron-low-hrv-falling-treated")
        assert(cross.insight?.text == "Your HRV is down 25% while ferritin sits at 34 — low iron is the likeliest anchor on your recovery, and it's the one you're already treating.")
        assert(cross.protocolLine == nil) // wearable day → no protocol fallback line

        // Stale device (last real reading 3 days old) is a blood-only day.
        var staleDay = WearableDailyMetrics(date: "2026-07-09")
        staleDay.hrv = 70
        let stale = MorningBrief.build(MorningBrief.Input(
            dateKey: "2026-07-12",
            daily: [staleDay],
            workouts: [],
            markers: [ferritinLow],
            stackNames: [],
            protocolState: .init(total: 0, done: 0, streakDays: 0)
        ))
        assert(!stale.wearableDay && stale.readiness == nil)

        // Deterministic rotation: identical input → identical pick.
        let again = MorningBrief.build(MorningBrief.Input(
            dateKey: "2026-07-12",
            daily: daily,
            workouts: [],
            markers: [ferritinLow],
            stackNames: ["Iron — gentle (bisglycinate)"],
            protocolState: .init(total: 3, done: 0, streakDays: 0)
        ))
        assert(again.insight?.id == cross.insight?.id)
    }

    private static func countdown() {
        let scheduled = NextDrawCountdown.build(lastDrawIso: "2026-06-28", retestWeeks: 8, todayIso: "2026-07-12")
        guard case .scheduled(let nextIso, let nextLabel, let daysLeft, let totalDays, let elapsedPct) = scheduled else {
            assertionFailure("expected scheduled"); return
        }
        assert(nextIso == "2026-08-23" && nextLabel == "Aug 23")
        assert(daysLeft == 42 && totalDays == 56 && elapsedPct == 25.0)
        assert(scheduled.subline == "42 days of protocol between now and proof")

        let overdue = NextDrawCountdown.build(lastDrawIso: "2026-06-28", retestWeeks: 8, todayIso: "2026-08-30")
        guard case .overdue(_, _, let daysOver) = overdue else { assertionFailure("expected overdue"); return }
        assert(daysOver == 7)
        assert(overdue.subline == "7 days past — the proof is waiting.")

        assert(NextDrawCountdown.build(lastDrawIso: nil, retestWeeks: 8, todayIso: "2026-07-12") == .none)
        assert(NextDrawCountdown.build(lastDrawIso: "2026-06-28", retestWeeks: 0, todayIso: "2026-07-12") == .none)

        // Draw day itself.
        let drawDay = NextDrawCountdown.build(lastDrawIso: "2026-06-28", retestWeeks: 2, todayIso: "2026-07-12")
        assert(drawDay.subline == "draw day — go get your proof")
    }

    private static func victory() {
        let iron = StackItem(name: "Iron — gentle (bisglycinate)", dose: "25 mg", monthlyCost: 12, recommendationType: "add", reason: "", marker: "Ferritin")

        func marker(_ name: String, first: (Double, String), last: (Double, String), band: (Double?, Double?)) -> ReportHistoryMarker {
            ReportHistoryMarker(
                name: name, unit: "ng/mL", points: 2,
                first: ReportHistoryPoint(value: first.0, dateIso: "2026-03-14T12:00:00.000Z", status: first.1, optimalMin: band.0, optimalMax: band.1),
                last: ReportHistoryPoint(value: last.0, dateIso: "2026-06-28T12:00:00.000Z", status: last.1, optimalMin: band.0, optimalMax: band.1)
            )
        }

        // Full flagged → in-range transition on a supplemented marker.
        let transition = VictoryCard.select(
            history: ReportHistory(panelCount: 2, lastDrawIso: "2026-06-28", retestWeeks: 8, markers: [marker("Ferritin", first: (34, "low"), last: (57, "optimal"), band: (50, 150))]),
            stack: [iron]
        )
        guard case .improved(let t) = transition else { assertionFailure("expected improved"); return }
        assert(t.from == "34" && t.to == "57" && t.sinceLabel == "March")
        assert(t.body == "Your iron protocol worked.")
        assert(t.protocolLabel == "iron")
        assert(t.visual.toPct > t.visual.fromPct)

        // Supplemented partial progress ≥20% closure.
        let progress = VictoryCard.select(
            history: ReportHistory(panelCount: 2, lastDrawIso: "2026-06-28", retestWeeks: 8, markers: [marker("Ferritin", first: (22, "deficient"), last: (34, "low"), band: (50, 150))]),
            stack: [iron]
        )
        guard case .improved(let p) = progress else { assertionFailure("expected progress"); return }
        assert(p.body == "43% of the gap to target closed — the protocol is pulling.")

        // Honest regression when nothing improved.
        let regression = VictoryCard.select(
            history: ReportHistory(panelCount: 2, lastDrawIso: "2026-06-28", retestWeeks: 8, markers: [marker("Vitamin B12", first: (520, "optimal"), last: (310, "low"), band: (400, 900))]),
            stack: []
        )
        guard case .regressed(let r) = regression else { assertionFailure("expected regressed"); return }
        assert(r.body == "Worth watching — not panicking. Your next draw says whether it's a trend.")

        // Single draw → anticipation.
        guard case .anticipation(let headline, _) = VictoryCard.select(
            history: ReportHistory(panelCount: 1, lastDrawIso: "2026-06-28", retestWeeks: 8, markers: []),
            stack: []
        ) else { assertionFailure("expected anticipation"); return }
        assert(headline == "Your baseline is set.")

        assert(VictoryCard.supplementBaseLabel("Iron — liquid") == "iron")
        assert(VictoryCard.supplementBaseLabel("Magnesium Glycinate (200 mg)") == "magnesium glycinate")
    }

    private static func nudge() {
        let step = HomeNextStep.compute(hasBloodwork: true, cabinetCount: nil, reportViewed: false, planViewed: false, protocolCount: 3, protocolCheckedCount: 0)
        assert(step.id == "read-report")

        // Priority 1: supply-out beats the orientation ladder.
        let out = HomeNudge.pick(HomeNudge.Input(
            runningLow: [.init(name: "Iron", daysLeft: 0)],
            nextStep: step, retest: .overdue(weeks: 3), daysSinceLog: 5,
            protocolTodayComplete: false, hasStack: true
        ))
        assert(out?.kind == .supply && out?.dismissible == false)
        assert(out?.headline == "Iron is out.")

        // Priority 2: orientation step.
        let orient = HomeNudge.pick(HomeNudge.Input(nextStep: step, retest: nil, daysSinceLog: nil, protocolTodayComplete: false, hasStack: true))
        assert(orient?.kind == .nextStep && orient?.ctaLabel == "Open your report")
        assert(orient?.headline == "Read your report")

        // Priority 3: retest overdue.
        let done = HomeNextStep.compute(hasBloodwork: true, cabinetCount: nil, reportViewed: true, planViewed: true, protocolCount: 0, protocolCheckedCount: 0)
        let retest = HomeNudge.pick(HomeNudge.Input(nextStep: done, retest: .overdue(weeks: 3), daysSinceLog: nil, protocolTodayComplete: false, hasStack: true))
        assert(retest?.headline == "Your retest is 3 weeks past due.")
        assert(retest?.ctaLabel == "Plan your retest")

        // A retest >2 weeks away does NOT claim the slot.
        let far = HomeNudge.pick(HomeNudge.Input(nextStep: done, retest: .until(weeks: 6), daysSinceLog: 0, protocolTodayComplete: false, hasStack: true))
        assert(far == nil)

        // Priority 4: gentle log re-engage.
        let log = HomeNudge.pick(HomeNudge.Input(nextStep: done, retest: .until(weeks: 6), daysSinceLog: 3, protocolTodayComplete: false, hasStack: true))
        assert(log?.kind == .log && log?.headline == "Pick up where you left off")

        // Dismissed today → nothing, no fallback chain.
        let dismissed = HomeNudge.pick(HomeNudge.Input(
            runningLow: [.init(name: "Iron", daysLeft: 4)],
            nextStep: step, retest: nil, daysSinceLog: nil,
            protocolTodayComplete: false, hasStack: true, dismissedToday: true
        ))
        assert(dismissed == nil)

        // Retest countdown math (9 weeks since draw on an 8-week cadence → 1 week over).
        let now = Date()
        let nineWeeksAgo = now.addingTimeInterval(-9 * 7 * 24 * 3600)
        assert(RetestCountdown.compute(lastBloodworkAt: nineWeeksAgo, retestWeeks: 8, now: now) == .overdue(weeks: 1))
        let threeWeeksAgo = now.addingTimeInterval(-3 * 7 * 24 * 3600)
        assert(RetestCountdown.compute(lastBloodworkAt: threeWeeksAgo, retestWeeks: 8, now: now) == .until(weeks: 5))
    }
}
#endif
