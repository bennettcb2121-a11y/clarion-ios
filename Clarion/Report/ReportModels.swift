import Foundation

/// Response of GET /api/report — the user's latest analyzed bloodwork + supplement stack.
/// The enriched fields (verdict, labNormal*, science drawer) ship in the API's parity update;
/// everything new is optional so the app renders fine against the older payload too.
struct ReportResponse: Codable {
    var hasBloodwork: Bool
    var score: Int?
    var scoreLabel: String?
    var counts: StatusCounts?
    var lastUpdated: String?
    var results: [BiomarkerResult]?
    var stack: [StackItem]?
    var stackMonthlyCost: Double?
    /// Panel-to-panel movement + countdown anchors — additive field; older API omits it.
    var history: ReportHistory?
}

/// The `history` field of GET /api/report: each multi-draw marker's first + latest
/// point evaluated under the user's CURRENT adaptive ranges (the victory card's
/// input), plus the next-draw countdown anchors (lastDrawIso + retest_weeks).
struct ReportHistory: Codable {
    var panelCount: Int
    /// YYYY-MM-DD of the most recent draw.
    var lastDrawIso: String?
    /// profiles.retest_weeks (nil → the app falls back to the default of 8).
    var retestWeeks: Double?
    var markers: [ReportHistoryMarker]
}

struct ReportHistoryMarker: Codable, Identifiable {
    var name: String
    var unit: String?
    /// Total draws carrying this marker (≥2 by construction).
    var points: Int
    var first: ReportHistoryPoint
    var last: ReportHistoryPoint

    var id: String { name }
}

struct ReportHistoryPoint: Codable {
    var value: Double
    /// Sort timestamp of the draw (ISO) — enough for "since March" labels.
    var dateIso: String
    /// Status under the user's CURRENT personalized ranges.
    var status: String
    var optimalMin: Double?
    var optimalMax: Double?
}

struct StatusCounts: Codable {
    var optimal: Int
    var low: Int
    var high: Int
    var suboptimal: Int
}

struct BiomarkerResult: Codable, Identifiable {
    var name: String
    var value: Double
    var unit: String?
    var optimalMin: Double?
    var optimalMax: Double?
    var status: String // deficient | low | suboptimal | optimal | high | unknown
    var whyItMatters: String?

    // Honest axis — what a real lab slip calls "normal" vs Clarion's band for this profile.
    var labNormalMin: Double?
    var labNormalMax: Double?
    var labReferenceSource: String?
    var isPersonalized: Bool?
    var mismatch: String?
    var profileLabel: String?
    /// Plain-English one-sentence verdict ("Your 22 is 'normal' on a lab slip but…").
    var verdict: String?
    var verdictIsFlagged: Bool?

    // Science drawer.
    var description: String?
    var foods: String?
    var lifestyle: String?
    var supplementNotes: String?
    var retest: String?
    var researchSummary: String?

    var id: String { name }

    var isFlagged: Bool { status == "low" || status == "deficient" || status == "high" || status == "suboptimal" }

    /// Outside what even the LAB calls normal — a clinician conversation, not a supplement tweak.
    var isOutsideLabNormal: Bool {
        guard let lo = labNormalMin, let hi = labNormalMax, hi > lo else { return false }
        return value < lo || value > hi
    }

    /// Sort weight: flagged first (most severe), then optimal, then unknown.
    var sortRank: Int {
        switch status {
        case "deficient", "high": return 0
        case "low", "suboptimal": return 1
        case "optimal": return 2
        default: return 3
        }
    }

    var statusLabel: String {
        switch status {
        case "deficient": return "Deficient"
        case "low": return "Low"
        case "suboptimal": return "Suboptimal"
        case "high": return "High"
        case "optimal": return "Optimal"
        default: return "—"
        }
    }

    var hasScience: Bool {
        researchSummary != nil || foods != nil || lifestyle != nil || supplementNotes != nil || retest != nil
    }
}

struct StackItem: Codable, Identifiable {
    var name: String
    var dose: String
    var monthlyCost: Double
    var recommendationType: String
    var reason: String
    var marker: String?
    /// Canonical `protocol_log.checks` key — present once the API parity update ships;
    /// the supplement name is the accepted legacy fallback.
    var logKey: String?

    var id: String { name }

    /// Key used when logging a dose against this row.
    var protocolKey: String { logKey ?? name }

    /// The three-bucket money grouping the web tells: Need (lab-backed adds),
    /// Maintain (keeps/training support), Cut (drops).
    var bucket: StackBucket {
        switch recommendationType.lowercased() {
        case "add", "increase", "start": return .need
        case "consider_cut", "cut", "drop", "remove": return .cut
        default: return .maintain
        }
    }
}

enum StackBucket: Int, CaseIterable {
    case need = 0
    case maintain = 1
    case cut = 2

    var title: String {
        switch self {
        case .need: return "Lab-backed"
        case .maintain: return "Keep steady"
        case .cut: return "Consider cutting"
        }
    }
}
