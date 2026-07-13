import Foundation

// =============================================================================
// The protocol_log wire models — exact twins of the web contract
// (src/lib/protocolLogApiPayload.ts + src/lib/dailyMetrics.ts):
//
//   GET /api/protocol-log?start&end   → ProtocolLogRangeResponse
//   PUT /api/protocol-log/metrics     → MetricsPutRequest / MetricsPutResponse
//   GET /api/logbook/labs             → LogbookLabsResponse
//
// `log_date` is a bare DATE keyed by the client's LOCAL wall-clock day; lab
// timestamps come back RAW and are bucketed into local days on-device.
// =============================================================================

/// Self-reported daily metrics between blood panels (protocol_log.metrics jsonb).
/// All optional — the user picks what to track. Numbers decode as Double
/// defensively (jsonb has no integer guarantee).
struct DailyMetrics: Codable, Equatable {
    /// 1 = low … 5 = very high.
    var activity_level: Double?
    /// Minutes outdoors / deliberate sun (rough).
    var sun_minutes: Double?
    /// Glasses or 8oz cups — rough; half-steps possible.
    var hydration_cups: Double?
    /// Self-reported hours slept.
    var sleep_hours: Double?
    /// Optional daily weight (kg).
    var weight_kg: Double?
    /// Free text, ≤280 chars.
    var notes: String?

    init(
        activity_level: Double? = nil,
        sun_minutes: Double? = nil,
        hydration_cups: Double? = nil,
        sleep_hours: Double? = nil,
        weight_kg: Double? = nil,
        notes: String? = nil
    ) {
        self.activity_level = activity_level
        self.sun_minutes = sun_minutes
        self.hydration_cups = hydration_cups
        self.sleep_hours = sleep_hours
        self.weight_kg = weight_kg
        self.notes = notes
    }

    /// Swift port of clampDailyMetrics (src/lib/dailyMetrics.ts:30) — the same
    /// clamps the server applies, run client-side before sending.
    func clamped() -> DailyMetrics {
        var out = DailyMetrics()
        if let v = activity_level, v.isFinite {
            out.activity_level = Double(min(5, max(1, MorningBrief.jsRound(v))))
        }
        if let v = sun_minutes, v.isFinite {
            out.sun_minutes = Double(min(600, max(0, MorningBrief.jsRound(v))))
        }
        if let v = hydration_cups, v.isFinite {
            out.hydration_cups = min(30, max(0, Double(MorningBrief.jsRound(v * 2)) / 2))
        }
        if let v = sleep_hours, v.isFinite {
            out.sleep_hours = min(16, max(0, Double(MorningBrief.jsRound(v * 2)) / 2))
        }
        if let v = weight_kg, v.isFinite, v > 20, v < 400 {
            out.weight_kg = (v * 10).rounded() / 10
        }
        if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            out.notes = String(n.prefix(280))
        }
        return out
    }

    /// Presence, not truthiness — a deliberate 0 (zero sun minutes) IS a log.
    /// (countTrackingInputs, trackingHandoffData.ts:62)
    var trackedInputCount: Int {
        var n = 0
        if sleep_hours != nil { n += 1 }
        if sun_minutes != nil { n += 1 }
        if hydration_cups != nil { n += 1 }
        if activity_level != nil { n += 1 }
        return n
    }

    var hasTrackedInputs: Bool { trackedInputCount > 0 }
}

// MARK: - GET /api/protocol-log?start&end

struct ProtocolLogRangeResponse: Codable {
    var rows: [ProtocolLogRow]
}

struct ProtocolLogRow: Codable {
    /// "YYYY-MM-DD" (date column — no time, no tz).
    var logDate: String
    /// Keys: "entry:<stackEntryId>" canonical; legacy = supplement name or biomarker slug.
    var checks: [String: Bool]
    /// Server-clamped; always an object.
    var metrics: DailyMetrics
}

// MARK: - PUT /api/protocol-log/metrics

/// REPLACE semantics — send the FULL merged metrics object, `{}` clears the day.
struct MetricsPutRequest: Codable {
    var logDate: String
    var metrics: DailyMetrics
}

struct MetricsPutResponse: Codable {
    var ok: Bool
    /// Server-clamped canonical values — adopt these on success.
    var metrics: DailyMetrics
}

// MARK: - GET /api/logbook/labs

struct LogbookLabsResponse: Codable {
    var bloodworkSaves: [LabSaveMarker]
    var labSessions: [LabSessionMarker]
    /// nil → default 8 (computeNextRetestDate convention).
    var retestWeeks: Double?
}

struct LabSaveMarker: Codable {
    /// RAW timestamptz ISO string — bucket to a LOCAL calendar day on device.
    var createdAt: String?
    var score: Double?
    var markerCount: Int
}

struct LabSessionMarker: Codable {
    /// RAW as stored: bare "YYYY-MM-DD", full ISO, or nil.
    var collectedAt: String?
    var createdAt: String?
    /// uploading | extracting | confirming | confirmed | discarded.
    var status: String
}

// MARK: - Local-day date math (src/lib/logbook.ts conventions)

enum LocalDay {

    /// YYYY-MM-DD from a Date using LOCAL time (web toLocalIso).
    static func toIso(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Parse YYYY-MM-DD as a LOCAL midnight date (web fromLocalIso).
    static func fromIso(_ iso: String) -> Date? {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func addDays(_ d: Date, _ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: d) ?? d
    }

    static func todayIso(_ now: Date = Date()) -> String { toIso(now) }

    private static func isBareDate(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        let pattern = "^\\d{4}-\\d{2}-\\d{2}$"
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    /// Coerce a raw Supabase timestamp to a LOCAL ISO day (web coerceToLocalIso):
    /// bare "YYYY-MM-DD" (date column) stays as-is — it's already a local calendar
    /// date; a full timestamptz ISO buckets into the user's local calendar day.
    static func coerceToLocalIso(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if isBareDate(raw) { return raw }
        guard let d = VictoryCard.parseTimestamp(raw) else { return nil }
        return toIso(d)
    }

    /// "This is a bloodwork day" markers from both lab tables, deduped by local
    /// day (web collectLabDates). Only CONFIRMED sessions pin a badge.
    static func collectLabDates(saves: [LabSaveMarker], sessions: [LabSessionMarker]) -> Set<String> {
        var out = Set<String>()
        for row in saves {
            if let iso = coerceToLocalIso(row.createdAt) { out.insert(iso) }
        }
        for s in sessions {
            if !s.status.isEmpty && s.status != "confirmed" { continue }
            let raw = (s.collectedAt?.isEmpty == false) ? s.collectedAt : s.createdAt
            if let iso = coerceToLocalIso(raw) { out.insert(iso) }
        }
        return out
    }
}

// MARK: - Month grid (src/lib/logbook.ts buildMonthGrid)

/// One day in the 42-cell calendar grid, classified for rendering.
struct LogbookDay: Identifiable {
    var isoDate: String
    var dayOfMonth: Int
    var inMonth: Bool
    var isToday: Bool
    var isFuture: Bool
    var checksCompleted: Int
    var checks: [String: Bool]
    /// The day's logged inputs, when a row exists (native extra for the detail sheet).
    var metrics: DailyMetrics?
    var hasLab: Bool
    var isRetestDay: Bool
    var isRetestWindow: Bool

    var id: String { isoDate }
}

struct LogbookMonth {
    var monthStart: Date
    /// "July 2026".
    var label: String
    /// 42 cells, Sunday-start, 6 rows.
    var days: [LogbookDay]
}

enum LogbookGrid {

    static func firstOfMonth(_ d: Date) -> Date {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return Calendar.current.date(from: c) ?? d
    }

    /// Query range for the 42-cell grid: walk back to the Sunday on/before the
    /// 1st, then +41 days (web monthGridRange).
    static func monthGridRange(_ monthDate: Date) -> (startIso: String, endIso: String) {
        let first = firstOfMonth(monthDate)
        let sundayOffset = Calendar.current.component(.weekday, from: first) - 1 // Sunday = 1
        let gridStart = LocalDay.addDays(first, -sundayOffset)
        let gridEnd = LocalDay.addDays(gridStart, 41)
        return (LocalDay.toIso(gridStart), LocalDay.toIso(gridEnd))
    }

    /// Build the 6-week grid. Weeks start on Sunday; the retest window is the
    /// target ±3 days (string comparison is safe on ISO days).
    static func buildMonthGrid(
        monthDate: Date,
        todayIso: String,
        rows: [ProtocolLogRow],
        labDates: Set<String>,
        nextRetestIso: String?
    ) -> LogbookMonth {
        let first = firstOfMonth(monthDate)
        let sundayOffset = Calendar.current.component(.weekday, from: first) - 1
        let gridStart = LocalDay.addDays(first, -sundayOffset)
        let monthIndex = Calendar.current.component(.month, from: monthDate)

        var byDate: [String: ProtocolLogRow] = [:]
        for r in rows { byDate[r.logDate] = r }

        var retestStart: String?
        var retestEnd: String?
        if let retestIso = nextRetestIso, let retestDate = LocalDay.fromIso(retestIso) {
            retestStart = LocalDay.toIso(LocalDay.addDays(retestDate, -3))
            retestEnd = LocalDay.toIso(LocalDay.addDays(retestDate, 3))
        }

        var days: [LogbookDay] = []
        for i in 0..<42 {
            let d = LocalDay.addDays(gridStart, i)
            let iso = LocalDay.toIso(d)
            let row = byDate[iso]
            let checks = row?.checks ?? [:]
            days.append(LogbookDay(
                isoDate: iso,
                dayOfMonth: Calendar.current.component(.day, from: d),
                inMonth: Calendar.current.component(.month, from: d) == monthIndex,
                isToday: iso == todayIso,
                isFuture: iso > todayIso,
                checksCompleted: checks.values.filter { $0 }.count,
                checks: checks,
                metrics: row?.metrics,
                hasLab: labDates.contains(iso),
                isRetestDay: nextRetestIso != nil && iso == nextRetestIso,
                isRetestWindow: retestStart != nil && retestEnd != nil && iso >= retestStart! && iso <= retestEnd!
            ))
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "LLLL yyyy"
        return LogbookMonth(monthStart: first, label: fmt.string(from: monthDate), days: days)
    }
}
