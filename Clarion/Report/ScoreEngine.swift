import Foundation

/// Faithful Swift port of the web's graded scoring engine (`src/lib/calculateScore.ts` +
/// `src/lib/scoreBreakdown.ts` in bloodwise-frontend). The app computes the score locally from
/// the per-marker analysis the API returns, because the API's `score` field can be a stale
/// value stored under an older formula — the web dashboard recomputes fresh for exactly the
/// same reason, and the two must never disagree.
///
/// Any change to the web formula is a breaking parity change and must be mirrored here.
enum ScoreEngine {

    // MARK: - Tuning constants (mirror calculateScore.ts exactly)

    /// Full-severity point loss for a marker below its floor / above its ceiling.
    private static let maxLow: Double = 16
    private static let maxHigh: Double = 14
    /// Being outside the band at all always registers at least this much.
    private static let minDing: Double = 2
    /// Hard ceiling on any single marker's contribution.
    private static let perMarkerCap: Double = 16
    /// Raw-penalty total above which extra dings are half-weighted.
    private static let softCapThreshold: Double = 30

    /// A HIGH reading on these markers is protective or typically benign (high HDL, high B12,
    /// high vitamin D from supplements) — it never drags the score.
    private static func highIsBenign(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("hdl") || n.contains("b12") || n.contains("cobalamin")
            || n.contains("folate") || n.contains("folic")
            || n.contains("vitamin d") || n.contains("25-oh") || n.contains("25-hydroxy")
    }

    /// 0 → just at the bound, 1 → 40% beyond it (full severity).
    private static func severityBeyond(distance: Double, bound: Double) -> Double {
        guard bound > 0 else { return 0 }
        return min(1, max(0, distance / (bound * 0.4)))
    }

    private static func round1(_ n: Double) -> Double { (n * 10).rounded() / 10 }

    // MARK: - Per-marker penalty

    /// Point loss for one marker. Graded by how far the value sits outside its optimal band
    /// when value + bound are known; gentle flat fallback otherwise.
    static func markerPenalty(_ m: BiomarkerResult) -> Double {
        let status = m.status.lowercased()

        if status.isEmpty || status == "optimal" || status == "normal" || status == "in range" || status == "unknown" {
            return 0
        }

        let isHigh = status == "high"
        let isLow = status == "deficient" || status == "low" || status == "suboptimal"

        if isHigh && highIsBenign(m.name) { return 0 }

        if m.value.isFinite {
            if isLow, let lo = m.optimalMin, m.value < lo {
                let s = severityBeyond(distance: lo - m.value, bound: lo)
                return round1(minDing + (maxLow - minDing) * s)
            }
            if isHigh, let hi = m.optimalMax, m.value > hi {
                let s = severityBeyond(distance: m.value - hi, bound: hi)
                return round1(minDing + (maxHigh - minDing) * s)
            }
        }

        switch status {
        case "deficient": return 12
        case "low": return 8
        case "high": return 8
        case "suboptimal": return 5
        default: return 0
        }
    }

    // MARK: - Total score

    /// Health score 0–100: 100 minus capped, softened penalties. Empty panel scores 100.
    static func score(_ results: [BiomarkerResult]) -> Int {
        guard !results.isEmpty else { return 100 }

        var penalty: Double = 0
        for r in results {
            penalty += min(perMarkerCap, markerPenalty(r))
        }

        let softened = penalty <= softCapThreshold
            ? penalty
            : softCapThreshold + (penalty - softCapThreshold) * 0.5

        let score = 100 - softened
        guard score.isFinite else { return 100 }
        return max(0, Int(score.rounded()))
    }

    /// Mirror of scoreEngine.ts `scoreToLabel`.
    static func label(for score: Int) -> String {
        if score >= 90 { return "Optimized" }
        if score >= 75 { return "Strong" }
        if score >= 60 { return "Mixed" }
        return "Needs attention"
    }

    // MARK: - Category breakdown (scoreBreakdown.ts)

    enum Category: String, CaseIterable, Identifiable {
        case iron = "Iron status"
        case vitamins = "Vitamin status"
        case metabolic = "Metabolic markers"
        case lipids = "Lipids & cardiovascular"
        case inflammation = "Inflammation"
        case minerals = "Electrolytes & minerals"

        var id: String { rawValue }
    }

    /// Mirror of BIOMARKER_TO_CATEGORY (plus the 25-OH Vitamin D alias from getCategoryForMarker).
    static func category(for markerName: String) -> Category {
        let n = markerName.trimmingCharacters(in: .whitespaces)
        if n == "25-OH Vitamin D" { return .vitamins }
        switch n {
        case "Ferritin", "Hemoglobin", "Hematocrit", "RBC", "MCV", "MCH", "RDW":
            return .iron
        case "Vitamin D", "Vitamin B12", "Folate":
            return .vitamins
        case "HbA1c", "Glucose", "Fasting Glucose", "Insulin":
            return .metabolic
        case "LDL-C", "Triglycerides", "HDL-C", "Total cholesterol", "ApoB":
            return .lipids
        case "hs-CRP", "CRP", "ESR":
            return .inflammation
        default:
            return .minerals
        }
    }

    /// Per-category 100-minus-penalties score; categories with markers only (the web defaults
    /// empty categories to 100 but never shows them — the app omits them).
    static func breakdown(_ results: [BiomarkerResult]) -> [(category: Category, score: Int, count: Int)] {
        var byCat: [Category: [BiomarkerResult]] = [:]
        for r in results {
            byCat[category(for: r.name), default: []].append(r)
        }
        return Category.allCases.compactMap { cat in
            guard let items = byCat[cat], !items.isEmpty else { return nil }
            let score = max(0, Int((100 - items.reduce(0) { $0 + markerPenalty($1) }).rounded()))
            return (cat, score, items.count)
        }
    }

    // MARK: - Drivers ("what should we focus on first?")

    /// Severity weight used for ORDERING drivers only (mirror penaltyForStatus — not the score).
    static func orderingWeight(for status: String) -> Double {
        switch status.lowercased() {
        case "deficient": return 18
        case "low": return 12
        case "high": return 10
        case "suboptimal": return 8
        default: return 0
        }
    }

    /// Flagged markers, most severe first — the web's driver order when no extra profile
    /// context is available (lab severity, then graded penalty as tiebreak).
    static func orderedDrivers(_ results: [BiomarkerResult], max maxItems: Int = 10) -> [BiomarkerResult] {
        results
            .filter { r in
                let s = r.status.lowercased()
                return s == "deficient" || s == "suboptimal" || s == "high" || s == "low"
            }
            .sorted {
                let (wa, wb) = (orderingWeight(for: $0.status), orderingWeight(for: $1.status))
                if wa != wb { return wa > wb }
                return markerPenalty($0) > markerPenalty($1)
            }
            .prefix(maxItems)
            .map { $0 }
    }

    /// Score if this one marker were moved to optimal — the "+N points" motivator.
    /// Returns nil when the marker is already optimal or fixing it wouldn't move the score.
    static func improvementForecast(_ results: [BiomarkerResult], fixing markerName: String) -> Int? {
        guard let item = results.first(where: { $0.name == markerName }),
              item.status.lowercased() != "optimal" else { return nil }
        let current = score(results)
        let simulated = results.map { r -> BiomarkerResult in
            guard r.name == markerName else { return r }
            var fixed = r
            fixed.status = "optimal"
            return fixed
        }
        let projected = score(simulated)
        return projected > current ? projected - current : nil
    }
}
