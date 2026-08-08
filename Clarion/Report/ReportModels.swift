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
    /// How full the user's bottle is, from their tracked inventory. `nil` when the
    /// supplement isn't tracked — the row then shows the plain form glyph, never a fake level.
    var supply: Supply?

    // MARK: - Live verdict (server-computed)
    //
    // The saved stack snapshot only carries a coarse `recommendationType` and a monthlyCost that
    // is 0 on older rows, so bucketing off it put every supplement in "Keep steady" and rendered
    // "$0 backed by your blood". These fields are the SAME verdict the web plan renders,
    // computed server-side in /api/report. Prefer them; fall back only when absent.
    /// "add" | "keep" | "drop" | "ask"
    var verdict: String?
    /// "blood" | "blood_adjacent" | "goal" | "ask" | "waste" — the honest source of the call.
    var verdictEvidence: String?
    var verdictReason: String?
    /// e.g. "below your 40–60 target" — nil when there's no lab range to anchor to.
    var targetClause: String?
    var caution: String?
    /// The verdict's own cost, populated where the snapshot's monthlyCost is 0.
    var verdictMonthlyUsd: Double?

    /// Cost to display: the verdict's figure when the snapshot has none.
    var effectiveMonthlyCost: Double {
        if monthlyCost > 0 { return monthlyCost }
        return verdictMonthlyUsd ?? 0
    }

    /// Bottle-drain supply level for one stack item — computed server-side from
    /// pills-per-bottle ÷ dose ÷ opened-date, mirroring the web shelf math.
    struct Supply: Codable {
        var fillPercent: Double   // 0…100
        var status: String        // "ok" | "low" | "out"
        var daysLeft: Int
        var pillsRemaining: Int?
    }

    var id: String { name }

    /// Key used when logging a dose against this row.
    var protocolKey: String { logKey ?? name }

    /// The three-bucket money grouping the web tells: Need (lab-backed adds),
    /// Maintain (keeps/training support), Cut (drops).
    /// The three-bucket money grouping the web tells: Need (lab-backed), Maintain, Cut.
    ///
    /// This switch used to list ONLY the verdict-style words ("add", "consider_cut", …). The API
    /// does not send those. `/api/report` serves `recommendationType` straight from the saved
    /// stack snapshot, whose vocabulary is `RecommendationType` in src/lib/supplements.ts:73 —
    /// "Core" | "Conditional" | "Context-dependent". None of those matched, so EVERY item fell to
    /// `default` and the Plan tab showed the whole stack as "Keep steady": the user was never told
    /// what their blood justifies or what to stop, which is the decision the product exists to
    /// make. A Core item driven by a deficient marker read identically to a no-signal one.
    ///
    /// Both vocabularies are accepted now — the snapshot's, and the verdict words in case a future
    /// payload sends those — so this cannot silently fall through again. Anything genuinely
    /// unrecognised still lands in `.maintain`, the safe bucket: it neither invents a lab
    /// justification nor tells someone to stop taking something.
    var bucket: StackBucket {
        // The live verdict wins when present. `evidence` is what actually distinguishes a
        // lab-backed keep from a goal-based one — kind alone collapses both to "keep", which is
        // how the whole shelf ended up in one bucket.
        if let kind = verdict?.lowercased() {
            switch kind {
            case "add": return .need
            case "drop": return .cut
            case "keep", "ask":
                let ev = (verdictEvidence ?? "").lowercased()
                return (ev == "blood" || ev == "blood_adjacent") ? .need : .maintain
            default: break
            }
        }
        switch recommendationType.lowercased() {
        // Snapshot vocabulary (src/lib/supplements.ts getRecommendationType).
        // Core = a deficient marker drives it; Conditional = low/suboptimal marker.
        case "core", "conditional": return .need
        case "context-dependent", "context dependent": return .maintain
        // Verdict vocabulary.
        case "add", "increase", "start": return .need
        case "consider_cut", "cut", "drop", "remove": return .cut
        default: return .maintain
        }
    }

    /// The name with a delivery-form word dropped when the dose contradicts it. A saved product
    /// named "Vitamin C — 1000 mg capsules" recommended as "2 gummies" (the user's gummy
    /// preference) otherwise renders the self-contradicting "…capsules · 2 gummies". Trusting the
    /// dose (the thing actually taken) and stripping the stale form word yields "Vitamin C —
    /// 1000 mg · 2 gummies". Fires only on a real conflict, so "Iron — liquid · 1 tbsp" and plain
    /// capsule rows are untouched.
    var coherentName: String {
        let d = dose.lowercased()
        let doseIsAltForm = d.contains("gumm") || d.contains("liquid") || d.contains("dropper")
            || d.contains("drop") || d.contains(" ml") || d.contains("tbsp") || d.contains("tsp")
            || d.contains("powder") || d.contains("scoop")
        guard doseIsAltForm else { return name }
        let stripped = name.replacingOccurrences(
            of: #"\s*\b(?:capsules?|caps?|tablets?|softgels?|caplets?)\b"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        let tidied = stripped
            .replacingOccurrences(of: #"[\s—–-]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return tidied.isEmpty ? name : tidied
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
