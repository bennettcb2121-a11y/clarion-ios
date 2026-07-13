import Foundation

/// Morning brief — the daily-changing layer on Home's hero. Swift twin of the web's
/// `src/lib/morningBrief.ts`: same pools, same conditions, same sentences.
///
/// The brief produces the genuinely-daily layer: the vitals readiness score (read
/// straight from the wearable daily window — never recomputed) plus ONE rotating
/// insight line that connects the wearable to the blood.
///
/// Honesty rules (mirrored from the web):
///  - Every template's condition must be TRUE from real data, and every value in
///    the copy is the actual number. No condition met → no claim.
///  - Demo snapshots never reach this module (pass nil when nothing is connected),
///    and stale devices (no real reading in ≥2 days) are treated as no-wearable days.
///  - The daily rotation is seeded by the local date key — deterministic per day.
struct MorningBrief: Equatable {

    /// Structural subset of BiomarkerResult — keeps this logic pure and light.
    struct Marker: Equatable {
        var name: String
        var value: Double
        var status: String
        var optimalMin: Double?
        var optimalMax: Double?
    }

    struct Insight: Equatable {
        var id: String
        var text: String
    }

    struct ProtocolState: Equatable {
        var total: Int
        var done: Int
        var streakDays: Int
    }

    struct Input {
        /// Local date key YYYY-MM-DD — seeds the deterministic daily rotation.
        var dateKey: String
        /// REAL wearable daily window or nil. Never pass demo data (UITEST excepted).
        var daily: [WearableDailyMetrics]?
        var workouts: [WearableWorkout]
        /// Analyzed markers from the latest panel(s).
        var markers: [Marker]
        /// Supplement names in the lab-safe protocol stack.
        var stackNames: [String]
        var protocolState: ProtocolState
    }

    /// Latest fresh readiness from the window; nil on blood-only/stale days.
    var readiness: Int?
    var readinessWord: String?
    /// True when a fresh wearable reading exists — readiness leads the hero.
    var wearableDay: Bool
    var insight: Insight?
    /// Quiet protocol-state line for blood-only days ("2 of 5 logged · 4-day streak").
    var protocolLine: String?

    private static let flaggedStatuses: Set<String> = ["deficient", "low", "suboptimal", "high"]

    // MARK: - Shared helpers (also used by DailyLoop)

    /// Whole days since the Unix epoch for a YYYY-MM-DD key (UTC, like the web).
    static func daysSinceEpoch(_ dateKey: String) -> Int {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0, parts[1] > 0, parts[2] > 0 else { return 0 }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = utc.date(from: comps) else { return 0 }
        return Int(floor(date.timeIntervalSince1970 / 86_400))
    }

    /// Web's fmtValue: integers print bare, everything else 1 decimal with ".0" trimmed.
    static func fmtValue(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int(v)) }
        var s = String(format: "%.1f", v)
        if s.hasSuffix(".0") { s = String(s.dropLast(2)) }
        return s
    }

    /// JS Math.round — half always rounds UP (toward +∞), unlike Swift's away-from-zero.
    static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    static func fmtSleep(_ min: Double) -> String {
        let h = Int(floor(min / 60))
        let m = jsRound(min.truncatingRemainder(dividingBy: 60))
        return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
    }

    static func statusWord(_ status: String) -> String {
        let s = status.lowercased()
        if s == "deficient" || s == "low" { return "low" }
        if s == "suboptimal" { return "below target" }
        if s == "high" { return "high" }
        return s
    }

    /// Matches the vitals hero's coaching bands (80 / 65 / 50).
    static func readinessWordFor(_ score: Int?) -> String? {
        guard let score else { return nil }
        if score >= 80 { return "Well-recovered" }
        if score >= 65 { return "Solidly recovered" }
        if score >= 50 { return "Part-recovered" }
        return "Under-recovered"
    }

    // MARK: - Trend math (web's metricTrend)

    struct MetricTrend {
        var direction: String // "rising" | "falling" | "flat"
        var changePct: Double
        var recentMean: Double
        var priorMean: Double
        var n: Int
    }

    static func metricTrend(
        _ daily: [WearableDailyMetrics],
        _ keyPath: KeyPath<WearableDailyMetrics, Double?>,
        minPerHalf: Int = 3,
        flatThresholdPct: Double = 3
    ) -> MetricTrend? {
        let series = daily.compactMap { $0[keyPath: keyPath] }.filter { $0.isFinite }
        guard series.count >= minPerHalf * 2 else { return nil }
        let mid = series.count / 2
        let prior = Array(series[0..<mid])
        let recent = Array(series[(series.count - mid)...])
        let priorMean = prior.reduce(0, +) / Double(prior.count)
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        guard priorMean.isFinite, priorMean != 0 else { return nil }
        let changePct = ((recentMean - priorMean) / abs(priorMean)) * 100
        let direction = abs(changePct) < flatThresholdPct ? "flat" : (changePct > 0 ? "rising" : "falling")
        return MetricTrend(direction: direction, changePct: changePct, recentMean: recentMean, priorMean: priorMean, n: series.count)
    }

    // MARK: - Window scans

    private static func findMarker(_ markers: [Marker], _ needles: [String]) -> Marker? {
        for m in markers {
            let name = m.name.lowercased()
            for n in needles where name == n || name.contains(n) { return m }
        }
        return nil
    }

    private static func isLowish(_ m: Marker?) -> Bool {
        let s = m?.status.lowercased()
        return s == "deficient" || s == "low" || s == "suboptimal"
    }

    private static func stackHas(_ stackNames: [String], _ needle: String) -> Bool {
        stackNames.contains { $0.lowercased().contains(needle) }
    }

    /// Age (whole days) of the latest day with a REAL reading — steps alone don't count.
    static func latestRealReadingAgeDays(_ daily: [WearableDailyMetrics], dateKey: String) -> Int? {
        for d in daily.reversed() {
            if d.hrv != nil || d.restingHeartRate != nil || d.sleepDurationMin != nil || d.readinessScore != nil {
                return daysSinceEpoch(dateKey) - daysSinceEpoch(d.date)
            }
        }
        return nil
    }

    /// Latest fresh readiness (from a day ≤1 day old) — the vitals readiness, not a recompute.
    static func freshReadiness(_ daily: [WearableDailyMetrics], dateKey: String) -> Int? {
        for d in daily.reversed() {
            guard let r = d.readinessScore, r.isFinite else { continue }
            let age = daysSinceEpoch(dateKey) - daysSinceEpoch(d.date)
            return age <= 1 ? jsRound(r) : nil
        }
        return nil
    }

    private static func workoutsInLastWeek(_ workouts: [WearableWorkout], dateKey: String) -> Int {
        let today = daysSinceEpoch(dateKey)
        return workouts.filter { w in
            let age = today - daysSinceEpoch(w.date)
            return age >= 0 && age < 7
        }.count
    }

    private static func avgSleepLastWeek(_ daily: [WearableDailyMetrics], dateKey: String) -> Double? {
        let today = daysSinceEpoch(dateKey)
        var vals: [Double] = []
        for d in daily {
            let age = today - daysSinceEpoch(d.date)
            guard age >= 0, age < 7 else { continue }
            if let v = d.sleepDurationMin, v.isFinite { vals.append(v) }
        }
        guard vals.count >= 2 else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    // MARK: - Insight pools

    /// Builds every insight whose condition is actually true, in three pools:
    /// wearable×blood (the moat), wearable-only, blood-only. The pick rotates within
    /// the strongest non-empty pool.
    private static func collectInsights(_ input: Input, fresh: Bool) -> (cross: [Insight], wearableOnly: [Insight], bloodOnly: [Insight]) {
        var cross: [Insight] = []
        var wearableOnly: [Insight] = []
        var bloodOnly: [Insight] = []

        let ferritin = findMarker(input.markers, ["ferritin"])
        let vitD = findMarker(input.markers, ["vitamin d", "25-oh"])
        let flagged = input.markers.filter { flaggedStatuses.contains($0.status.lowercased()) }

        if let daily = input.daily, fresh {
            let hrv = metricTrend(daily, \.hrv)
            let rhr = metricTrend(daily, \.restingHeartRate)
            let sleepTrend = metricTrend(daily, \.sleepDurationMin)
            let readinessTrend = metricTrend(daily, \.readinessScore)
            let readiness = freshReadiness(daily, dateKey: input.dateKey)
            let sessions = workoutsInLastWeek(input.workouts, dateKey: input.dateKey)
            let avgSleep = avgSleepLastWeek(daily, dateKey: input.dateKey)

            // 1a/1b — low ferritin meeting a falling HRV (classic endurance pattern).
            if let ferritin, isLowish(ferritin), hrv?.direction == "falling", let hrv {
                let pct = abs(jsRound(hrv.changePct))
                let v = fmtValue(ferritin.value)
                if stackHas(input.stackNames, "iron") {
                    cross.append(Insight(
                        id: "iron-low-hrv-falling-treated",
                        text: "Your HRV is down \(pct)% while ferritin sits at \(v) — low iron is the likeliest anchor on your recovery, and it's the one you're already treating."
                    ))
                } else {
                    cross.append(Insight(
                        id: "iron-low-hrv-falling",
                        text: "Your HRV is down \(pct)% while ferritin sits at \(v) — low iron stores suppress recovery, and yours are flagged. Worth treating before you blame training."
                    ))
                }
            }

            // 2 — ferritin fine, HRV still sliding: don't reach for iron.
            if let ferritin, ferritin.status.lowercased() == "optimal", hrv?.direction == "falling" {
                cross.append(Insight(
                    id: "iron-clear-hrv-falling",
                    text: "Your HRV is trending low while ferritin sits at \(fmtValue(ferritin.value)) — recovery is the lever here, not iron."
                ))
            }

            // 3 — resting HR climbing with any marker still flagged.
            if let rhr, rhr.direction == "rising", let m = flagged.first {
                cross.append(Insight(
                    id: "rhr-rising-marker-flagged",
                    text: "Resting heart rate is up \(abs(jsRound(rhr.changePct)))% and \(m.name) is still \(statusWord(m.status)) at \(fmtValue(m.value)) — treat easy days as part of the protocol until both settle."
                ))
            }

            // 4 — short/sliding sleep with magnesium in the stack.
            if stackHas(input.stackNames, "magnesium"),
               let avgSleep,
               avgSleep < 420 || sleepTrend?.direction == "falling" {
                cross.append(Insight(
                    id: "sleep-short-magnesium",
                    text: "Sleep is averaging \(fmtSleep(avgSleep)) over the last week — the magnesium in your stack does its best work when lights-out is consistent."
                ))
            }

            // 5/6 — training load against the iron buffer.
            if sessions >= 3, let ferritin {
                let v = fmtValue(ferritin.value)
                if isLowish(ferritin) {
                    cross.append(Insight(
                        id: "load-iron-thin",
                        text: "\(sessions) sessions this week on a ferritin of \(v) — that training load spends iron you don't have spare. Easy days count double right now."
                    ))
                } else if ferritin.status.lowercased() == "optimal" {
                    cross.append(Insight(
                        id: "load-iron-holding",
                        text: "\(sessions) sessions this week and ferritin is holding at \(v) — your iron buffer is doing its job under this load."
                    ))
                }
            }

            // 7 — low vitamin D sitting under a flat, sub-70 readiness.
            if let vitD, isLowish(vitD), let readinessTrend, readinessTrend.recentMean < 70 {
                cross.append(Insight(
                    id: "vitd-low-readiness-flat",
                    text: "Readiness has been sitting under 70 and your vitamin D is \(fmtValue(vitD.value)) — repletion is cheap, and it tends to show up in both numbers."
                ))
            }

            // 8/9 — today's readiness verdict (wearable-only pool).
            if let readiness, readiness >= 80 {
                wearableOnly.append(Insight(
                    id: "readiness-high",
                    text: "Readiness \(readiness) — your body has signed off on a hard session. Spend it."
                ))
            }
            if let readiness, readiness < 50 {
                wearableOnly.append(Insight(
                    id: "readiness-low",
                    text: "Readiness \(readiness) — pushing hard today digs the hole deeper. Easy movement, real food, an early night."
                ))
            }
        }

        // 10 — top flagged marker with an honest target (blood-only pool).
        if let target = flagged.first(where: { $0.optimalMin != nil || $0.optimalMax != nil }) {
            let band: String
            if let lo = target.optimalMin, let hi = target.optimalMax {
                band = "\(fmtValue(lo))–\(fmtValue(hi))"
            } else if let lo = target.optimalMin {
                band = "≥\(fmtValue(lo))"
            } else {
                band = "≤\(fmtValue(target.optimalMax!))"
            }
            bloodOnly.append(Insight(
                id: "flagged-target",
                text: "\(target.name) is at \(fmtValue(target.value)) — target \(band). Every logged dose this week is a pull in that direction."
            ))
        }

        // 11 — streak → retest proof.
        if input.protocolState.streakDays >= 3 {
            bloodOnly.append(Insight(
                id: "streak-proof",
                text: "\(input.protocolState.streakDays) days logged in a row — the retest is where that streak becomes numbers."
            ))
        }

        // 12 — open doses today.
        if input.protocolState.total > 0, input.protocolState.done < input.protocolState.total {
            let left = input.protocolState.total - input.protocolState.done
            bloodOnly.append(Insight(
                id: "doses-open",
                text: "\(left) of \(input.protocolState.total) doses still open today — the plan only works on the days it happens."
            ))
        }

        // 13 — everything in range.
        if !input.markers.isEmpty, flagged.isEmpty {
            bloodOnly.append(Insight(
                id: "all-clear",
                text: "All \(input.markers.count) markers in range — today's job is to not break what's working."
            ))
        }

        return (cross, wearableOnly, bloodOnly)
    }

    // MARK: - Build

    static func build(_ input: Input) -> MorningBrief {
        let readingAge = input.daily.flatMap { latestRealReadingAgeDays($0, dateKey: input.dateKey) }
        // Same honesty rule as the vitals tab: a reading ≥2 days old isn't "today".
        let fresh = input.daily != nil && readingAge != nil && readingAge! < 2

        let pools = collectInsights(input, fresh: fresh)
        let pool = !pools.cross.isEmpty ? pools.cross : (!pools.wearableOnly.isEmpty ? pools.wearableOnly : pools.bloodOnly)
        let insight = pool.isEmpty ? nil : pool[daysSinceEpoch(input.dateKey) % pool.count]

        let readiness = fresh ? input.daily.flatMap { freshReadiness($0, dateKey: input.dateKey) } : nil

        var protocolLine: String? = nil
        if !fresh, input.protocolState.total > 0 {
            let streakPart = input.protocolState.streakDays >= 2 ? " · \(input.protocolState.streakDays)-day streak" : ""
            protocolLine = "\(input.protocolState.done) of \(input.protocolState.total) logged today\(streakPart)"
        }

        return MorningBrief(
            readiness: readiness,
            readinessWord: readinessWordFor(readiness),
            wearableDay: fresh,
            insight: insight,
            protocolLine: protocolLine
        )
    }
}
