import Foundation

// =============================================================================
// Daily-inputs copy + math — verbatim ports of the web's pure helpers
// (src/lib/trackingHandoffData.ts + the normalize* fill functions from
// src/lib/readinessComposite.ts). Pure functions, no stores, no network.
//
// NAMING GUARD: none of this is ever labeled "readiness" in UI copy — the app
// has exactly one readiness, the wearable's, on the Vitals tab. These numbers
// only answer "did I log my inputs?" and drive slider fills.
// =============================================================================

enum TrackingData {

    /// The four manual inputs the journal captures.
    static let inputCount = 4

    static let cupLiters = 0.25
    static let hydrationGoalLiters = 2.5

    private static let activityShort: [Int: String] = [
        1: "rest", 2: "easy", 3: "steady", 4: "strong", 5: "max",
    ]

    // MARK: - Slider fills (the scoring-normalized pct, NOT value/max)

    /// Peak at 8h, −14/hr distance (normalizeSleepScore).
    static func sleepFillPct(_ h: Double?) -> Double {
        guard let h, h > 0 else { return 0 }
        return max(0, min(100, 100 - abs(h - 8) * 14))
    }

    /// min/45 × 100 capped (normalizeSunScore).
    static func sunFillPct(_ min: Double?) -> Double {
        guard let min, min >= 0 else { return 0 }
        return Swift.min(100, (min / 45) * 100)
    }

    /// liters vs the 2.5 L goal (hydrationBarPct).
    static func hydrationFillPct(_ cups: Double?) -> Double {
        guard let cups, cups >= 0 else { return 0 }
        return Swift.min(100, (cupsToLiters(cups) / hydrationGoalLiters) * 100)
    }

    /// (level−1)/4 × 100 (normalizeActivityScore).
    static func trainingFillPct(_ level: Double?) -> Double {
        guard let level, level >= 1 else { return 0 }
        return ((level - 1) / 4) * 100
    }

    // MARK: - Value display

    static func cupsToLiters(_ cups: Double) -> Double {
        (cups * cupLiters * 10).rounded() / 10
    }

    /// "1.5" + " / 2.5 L" (formatHydrationHandoff).
    static func formatHydration(_ cups: Double?) -> (primary: String, suffix: String) {
        guard let cups, cups >= 0 else { return ("—", "") }
        return (trimNumber(cupsToLiters(cups)), " / 2.5 L")
    }

    /// "3" + " · steady" (formatActivityHandoff).
    static func formatActivity(_ level: Double?) -> (primary: String, suffix: String) {
        guard let level, level >= 1 else { return ("—", "") }
        let tag = activityShort[Int(level)] ?? "steady"
        return (trimNumber(level), " · \(tag)")
    }

    static func trimNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// Rounded-to-1dp average of a metric across history (avgFromHistory).
    static func avgSleep(_ history: [DailyMetrics]) -> Double? {
        let nums = history.compactMap(\.sleep_hours).filter(\.isFinite)
        guard !nums.isEmpty else { return nil }
        return ((nums.reduce(0, +) / Double(nums.count)) * 10).rounded() / 10
    }

    // MARK: - Copy ladder (buildTrackingStatusBold — port EXACT)

    static func statusBold(_ m: DailyMetrics) -> String {
        if !m.hasTrackedInputs { return "Nothing logged yet today." }
        let sleepGood = (m.sleep_hours ?? 0) >= 7
        let sunGood = (m.sun_minutes ?? 0) >= 20
        let hydLow = (m.hydration_cups ?? 0) < 4
        let hydGood = (m.hydration_cups ?? 0) >= 6
        let trained = (m.activity_level ?? 0) >= 2

        if sleepGood && sunGood && hydLow { return "Strong sleep and sun today — hydration is lagging." }
        if sleepGood && hydGood { return "Strong sleep and hydration today" }
        if sleepGood && trained { return "Strong sleep and training logged today" }
        if sleepGood { return "Sleep is on track today" }
        if hydLow { return "Hydration is lagging" }
        return "Keep logging — patterns sharpen with each day."
    }

    // MARK: - Effect lines (port verbatim, incl. the wearable variant of sleep)

    struct EffectLine {
        var bold: String?
        var text: String
    }

    static func sleepEffectLine(hours: Double?, avgHours: Double?, hasWearable: Bool) -> EffectLine {
        guard let hours, hours > 0 else {
            return hasWearable
                ? EffectLine(text: "Your wearable already tracks sleep — log here only for nights without it.")
                : EffectLine(text: "Log sleep to connect recovery to your labs.")
        }
        let aboveAvg = avgHours != nil && hours > avgHours! + 0.2
        let text: String
        if aboveAvg {
            text = "Above your \(trimNumber(avgHours!))h average — recovery is on track."
        } else if hours >= 7 {
            text = "Solid recovery range for today."
        } else {
            text = "Short night — prioritize rest when you can."
        }
        return EffectLine(bold: "Recovery signal.", text: text)
    }

    static func sunEffectLine(minutes: Double?) -> EffectLine {
        guard let minutes, minutes >= 0 else {
            return EffectLine(bold: "Supports Vitamin D.", text: "Log rough minutes outside to connect light to your markers.")
        }
        return EffectLine(
            bold: "Supports Vitamin D.",
            text: minutes >= 20
                ? "Morning light helps the marker you're keeping steady."
                : "A little more daylight would strengthen the rhythm signal."
        )
    }

    static func hydrationEffectLine(cups: Double?) -> EffectLine {
        guard let cups, cups >= 0 else { return EffectLine(text: "Estimate intake for the day.") }
        if cups < 4 {
            return EffectLine(bold: "Running low.", text: "Behind for the day — a couple glasses would close the gap.")
        }
        return EffectLine(text: "On pace for the day — keep steady through the afternoon.")
    }

    /// Web activityFeedbackLine (readinessComposite.ts:98).
    static func activityFeedbackLine(_ level: Double?) -> String {
        guard let level, level >= 1 else { return "Tap your movement level today." }
        if level <= 2 { return "Light day — recovery is still progress." }
        if level <= 4 { return "Steady stimulus." }
        return "High output — prioritize sleep and fuel."
    }

    static func trainingEffectLine(level: Double?) -> EffectLine {
        guard let level, level >= 1 else { return EffectLine(text: "Tap training to log movement for today.") }
        var line = activityFeedbackLine(level)
        if line.hasSuffix(".") { line.removeLast() }
        return EffectLine(bold: "Logged.", text: "\(line) — iron and hydration matter most on these days.")
    }

    // MARK: - Week strip (buildWeekLoggedDays — LOCAL day keys)

    /// One day on the Mon–Sun strip. Deliberately NOT a score — this only
    /// answers "did I log my inputs?".
    struct WeekDay: Identifiable {
        var label: String
        var logged: Bool
        var isToday: Bool
        var isFuture: Bool

        var id: String { label }
    }

    private static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Mon-start strip; a day counts as logged when ANY manual input is present.
    /// iOS keys days by LOCAL wall-clock (the ProtocolLogStore.todayKey
    /// convention) — self-consistent with dose logging. The web tracking page
    /// still uses UTC keys; metrics logged near midnight may bucket differently
    /// there until the web adopts local keys.
    static func weekLoggedDays(history: [ProtocolLogRow], now: Date = Date()) -> [WeekDay] {
        let todayIso = LocalDay.todayIso(now)
        var byDate: [String: ProtocolLogRow] = [:]
        for row in history { byDate[row.logDate] = row }

        let jsDay = Calendar.current.component(.weekday, from: now) - 1 // Sunday = 0
        let dayIdx = (jsDay + 6) % 7                                     // Monday = 0
        var out: [WeekDay] = []
        for i in 0..<7 {
            let d = LocalDay.addDays(now, i - dayIdx)
            let iso = LocalDay.toIso(d)
            let isFuture = iso > todayIso
            let logged = !isFuture && (byDate[iso]?.metrics.hasTrackedInputs ?? false)
            out.append(WeekDay(label: dayLabels[i], logged: logged, isToday: iso == todayIso, isFuture: isFuture))
        }
        return out
    }
}
