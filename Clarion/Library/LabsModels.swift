import Foundation

// =============================================================================
// GET /api/labs/history — the native Labs tab's full history feed.
// Exact twin of the web payload (src/lib/labsHistoryApiPayload.ts): the deduped
// panel archive (no marker maps), every multi-draw marker's complete journey
// (server-ranked — render in order), and the honest movers selection.
// Plain JSONDecoder, no key strategy, matching ReportModels.swift style.
// =============================================================================

struct LabsHistoryResponse: Codable {
    var panelCount: Int
    /// YYYY-MM-DD of the newest draw.
    var lastDrawIso: String?
    var lastDrawLabel: String?
    /// profiles.retest_weeks (nil → default 8).
    var retestWeeks: Double?
    /// Newest first (catalog order).
    var panels: [LabPanel]
    /// ONLY markers on ≥2 draws; server-ranked (goal/flag-relevant first).
    var journeys: [LabJourney]
    var movers: LabMovers
}

struct LabPanel: Codable, Identifiable {
    /// "session-<uuid>" | "manual-…" | "save-<uuid>" — joins journeys[].points[].panelId.
    var id: String
    /// YYYY-MM-DD of the draw; nil when unknown ('' coerced server-side).
    var dateIso: String?
    /// "Jun 28, 2026" — "Unknown date" fallback.
    var dateLabel: String
    /// ISO — sortable; matches journeys[].points[].dateIso for this draw.
    var sortTimestamp: String
    /// "upload" | "manual" | "survey".
    var source: String
    var markerCount: Int
    /// Rounded to an integer server-side.
    var score: Int?
    /// Markers whose tone is 'low' (needs review) under the user's CURRENT ranges.
    var reviewCount: Int
}

struct LabJourney: Codable, Identifiable {
    /// Stable key; SwiftUI id.
    var markerKey: String
    /// Canonical name from the analysis engine.
    var displayName: String
    /// "" possible when the engine has no unit for the marker.
    var unit: String?
    /// last − first, 1 decimal.
    var delta: Double?
    /// nil = no meaningful direction between the last two draws.
    var improved: Bool?
    /// Oldest → newest.
    var points: [LabJourneyPoint]

    var id: String { markerKey }

    var lastPoint: LabJourneyPoint? { points.last }
}

struct LabJourneyPoint: Codable {
    /// Joins back to panels[].id.
    var panelId: String
    /// sortTimestamp of that draw (ISO).
    var dateIso: String
    var dateLabel: String
    var value: Double
}

struct LabMovers: Codable {
    /// ≤4, ranked by |last−prior|/|prior|, each ≥2% move; keys into journeys.
    var markerKeys: [String]
    /// Multi-draw markers that held within 2%.
    var steadyCount: Int
}

// =============================================================================
// Client-derived labels — verbatim ports of the pure web helpers
// (src/lib/labsHandoffData.ts + src/lib/labsHandoffSpark.ts). The server
// deliberately does NOT send these; the web derives them client-side too.
// =============================================================================

enum LabsLabels {

    /// Web's fmtVal: integers unadorned, else rounded to 2 decimals.
    static func fmtValue(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static let dayMs: Double = 86_400_000
    private static let monthMs: Double = 30.44 * 86_400_000
    private static let yearMs: Double = 365.25 * 86_400_000

    /// "last 8 months" / "last 2 years" from the ACTUAL elapsed time between the
    /// first and last draw — never the calendar-year difference. Short spans
    /// floor at "last 3 months". (journeyYearSpanLabel, labsHandoffData.ts:61)
    static func journeySpanLabel(_ points: [LabJourneyPoint]) -> String? {
        guard points.count >= 2,
              let first = points.first.flatMap({ VictoryCard.parseTimestamp($0.dateIso) }),
              let last = points.last.flatMap({ VictoryCard.parseTimestamp($0.dateIso) })
        else { return nil }
        let elapsedMs = max(0, last.timeIntervalSince(first) * 1000)
        let months = elapsedMs / monthMs
        if months < 11 {
            let n = max(3, MorningBrief.jsRound(months))
            return "last \(n) months"
        }
        let years = max(1, MorningBrief.jsRound(elapsedMs / yearMs))
        return "last \(years) year\(years == 1 ? "" : "s")"
    }

    /// The journey header's delta line (formatJourneyDelta, labsHandoffSpark.ts:63).
    static func journeyDeltaLabel(_ points: [LabJourneyPoint], improved: Bool?) -> String {
        guard points.count >= 2 else { return "first panel" }
        let prior = points[points.count - 2].value
        let last = points[points.count - 1].value
        if prior == last { return "steady" }
        let priorLabel = fmtValue((prior * 10).rounded() / 10)
        if improved == true {
            return last > prior ? "↑ up from \(priorLabel)" : "↓ better from \(priorLabel)"
        }
        if improved == false { return "↓ watch from \(priorLabel)" }
        return last > prior ? "↑ from \(priorLabel)" : "↓ from \(priorLabel)"
    }

    /// "↑ 4" / "↓ 2" / "steady" / "first panel" (formatPanelScoreDelta).
    static func panelScoreDelta(current: Int?, prior: Int?) -> String {
        guard let current, let prior else { return "first panel" }
        let d = current - prior
        if d == 0 { return "steady" }
        return d > 0 ? "↑ \(d)" : "↓ \(abs(d))"
    }

    /// "24 markers · 3 to review · calibrated for …" (panelReviewMeta).
    static func panelReviewMeta(markerCount: Int, reviewCount: Int, profileLabel: String? = nil) -> String {
        var parts = ["\(markerCount) marker\(markerCount == 1 ? "" : "s")"]
        parts.append(reviewCount > 0 ? "\(reviewCount) to review" : "all in range")
        if let profileLabel, !profileLabel.isEmpty { parts.append("calibrated for \(profileLabel)") }
        return parts.joined(separator: " · ")
    }

    enum TrendClass {
        case up, flat, down
    }

    struct TrendTile {
        var trendClass: TrendClass
        var label: String
        var valueMuted: Bool
    }

    /// Mover tile trend chip (markerTrendTileLabel, labsHandoffData.ts:146).
    static func trendTileLabel(_ journey: LabJourney) -> TrendTile {
        guard journey.points.count >= 2 else {
            return TrendTile(trendClass: .flat, label: "steady", valueMuted: false)
        }
        let last = journey.points[journey.points.count - 1].value
        let prior = journey.points[journey.points.count - 2].value
        if last == prior { return TrendTile(trendClass: .flat, label: "steady", valueMuted: false) }
        let delta = last - prior
        if journey.improved == true {
            return TrendTile(trendClass: .up, label: delta > 0 ? "↑ rising" : "↓ better", valueMuted: false)
        }
        if journey.improved == false {
            return TrendTile(trendClass: .down, label: "↓ watch", valueMuted: true)
        }
        return TrendTile(
            trendClass: delta > 0 ? .up : .down,
            label: delta > 0 ? "↑ rising" : "↓ watch",
            valueMuted: delta < 0
        )
    }

    /// Axis captions under the featured chart (axisLabelsFromPoints).
    static func axisLabels(_ points: [LabJourneyPoint]) -> [String] {
        if points.isEmpty { return [] }
        if points.count <= 4 { return points.map(\.dateLabel) }
        let first = points.first?.dateLabel ?? ""
        let last = points.last?.dateLabel ?? ""
        let mid = points[points.count / 2].dateLabel
        var out: [String] = []
        for label in [first, mid, last] where !label.isEmpty && !out.contains(label) {
            out.append(label)
        }
        return out
    }
}
