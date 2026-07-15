import Foundation

/// The Home hero's short status verdict — a punchy 1–3 word read on the day, NOT a sentence.
/// Pure + testable: the readiness tier (the same 80/65/50 bands the vitals hero uses) maps to a
/// word, lightly flavored by persona (endurance gets a training voice at the extremes). The
/// readiness number rides alongside as the secondary figure; this is just the word.
enum HomeStatus {

    /// Recovery tiers, split on the vitals hero's 80 / 65 / 50 thresholds.
    enum Tier {
        case charged // ≥ 80 — fully recovered, spend it
        case steady  // 65–79 — solid, train as planned
        case ease    // 50–64 — part-recovered, keep it moderate
        case rest    // < 50 — under-recovered, back off
    }

    static func tier(for readiness: Int?) -> Tier? {
        guard let r = readiness else { return nil }
        if r >= 80 { return .charged }
        if r >= 65 { return .steady }
        if r >= 50 { return .ease }
        return .rest
    }

    /// Short status word for the hero. Nil readiness (no fresh wearable day) → a neutral
    /// placeholder that states the day without over-claiming recovery we don't have.
    static func word(readiness: Int?, persona: Persona) -> String {
        guard let tier = tier(for: readiness) else { return "New day." }

        // Endurance flavors the extremes with a training voice; middle tiers use the neutral set.
        switch (persona, tier) {
        case (.endurance, .charged): return "Push day."
        case (.endurance, .rest):    return "Easy miles."
        default: break
        }

        switch tier {
        case .charged: return "Green light."
        case .steady:  return "Steady."
        case .ease:    return "Ease off."
        case .rest:    return "Rest up."
        }
    }
}
