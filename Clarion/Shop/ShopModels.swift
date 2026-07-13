import Foundation

/// Response of GET /api/shop?platform=ios — the fully server-computed shop catalog.
/// Every engine (multi-draw lab merge, bucketing, verdict reasons, Clarion Pick,
/// purchase warnings) runs on the server (src/lib/shopApiPayload.ts in the web repo);
/// the app only renders and buys. Cards arrive pre-ordered backed → maintenance → skip.
struct ShopResponse: Codable {
    /// Merged multi-draw lab inputs were non-empty — drives hero copy + empty states.
    var hasLabs: Bool
    /// One per catalog preset (38 today).
    var cards: [ShopCard]
}

/// One supplement preset, pre-bucketed and pre-reasoned by the server.
struct ShopCard: Codable, Identifiable {
    var presetId: String
    var displayName: String
    /// vitamin | mineral | fatty-acid | amino | probiotic | other
    var category: String
    /// 2–3 sentence entry summary.
    var overview: String
    /// UL/interaction footnote — shown under the pick sheet's buy button.
    var caution: String?
    /// backed | maintenance | skip
    var bucket: String
    /// for-you | pairs-well | optional | skip — the card tag.
    var flag: String
    /// LabAwarenessStatus: priority | maintenance | optimal | unknown
    var status: String
    var monthlyUsd: Double
    /// Verdict-engine why + marker chip — nil when the labs say nothing about this preset.
    var reason: ShopReason?
    var warning: ShopWarning
    /// The pick sheet's one-line lab status — nil when no marker backs this entry or it's untested.
    var labGap: ShopLabGap?
    /// [0] is always the hero (Clarion Pick / gummy-pref lead), then deduped alternatives.
    var options: [ShopOption]

    var id: String { presetId }

    var bucketKind: ShopBucket {
        switch bucket {
        case "backed": return .backed
        case "maintenance": return .maintenance
        default: return .skip
        }
    }

    /// The Clarion Pick — the server guarantees options[0] is the hero.
    var hero: ShopOption? { options.first }

    var flagLabel: String {
        switch flag {
        case "for-you": return "For you"
        case "pairs-well": return "Pairs well"
        case "optional": return "Optional"
        default: return "Skip"
        }
    }

    /// The web's formatShopMonthly: "$12".
    var monthlyLabel: String { "$\(Int(max(0, monthlyUsd.rounded())))" }

    /// First quality mark of the hero, same fallback as the web card.
    var qualityCue: String { hero?.qualityMarks.first ?? "Clarion-vetted" }

    /// true ⇒ the buy CTA demotes to a ghost "Buy anyway".
    var suppressPurchase: Bool { warning.suppressPurchase }
}

/// The per-preset "why this is for you" — identical words to the report/plan verdict.
struct ShopReason: Codable {
    var text: String
    /// Marker chip, e.g. "22 ng/mL · below your 50–150 target".
    var chip: String?
}

/// ShopProductWarning — drives the ghost buy CTA on accumulators at optimal levels.
struct ShopWarning: Codable {
    /// lab_priority | optional | likely_unnecessary | maintenance_ok
    var level: String
    var label: String
    var detail: String
    var suppressPurchase: Bool
}

/// ClarionPickLabGap — the pick sheet's status line, built from the user's own result.
struct ShopLabGap: Codable {
    var markerName: String
    var value: Double
    var targetMin: Double?
    var targetMax: Double?
    /// below | above | in_band | unscored
    var direction: String
    /// Human clause, e.g. "below your 50–150 target".
    var clause: String
    /// Per-marker cadence when known, e.g. "Retest in 8–10 weeks".
    var retest: String?

    /// Value formatted the way the web prints it (whole numbers stay whole).
    var valueLabel: String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: abs(value) >= 10 ? "%.1f" : "%.2f", value)
    }
}

/// One buyable product inside a card — the hero or a deduped alternative tier.
struct ShopOption: Codable, Identifiable {
    /// "hero", "alt-0", …
    var id: String
    var isHero: Bool
    /// "Clarion Pick · best overall" | "Lower cost" | "Higher potency" | "Liquid" | "Gummy"
    var tierLabel: String
    var brand: String
    var productName: String
    /// "25 mg elemental per capsule"
    var dose: String?
    /// Display only — "~$10", "$15–20".
    var priceLabel: String
    /// Hero only — the one-line "why Clarion picked this".
    var why: String?
    /// ≤4 short marks; may be empty.
    var qualityMarks: [String]
    /// For the live availability POST once PA-API keys land.
    var asin: String?
    var buy: ShopBuy

    var fullName: String {
        let joined = "\(brand) \(productName)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? productName : joined
    }
}

/// BuyOption (src/lib/fulfillment.ts) — the resolved buy action for one product.
struct ShopBuy: Codable {
    /// dropship | fullscript | amazon
    var provider: String
    /// external_link | in_app_cart
    var mode: String
    /// "Buy on Amazon" / "Add to cart"
    var label: String
    /// ABSOLUTE for external_link — always OUR /go/amazon redirect (never amazon.com
    /// directly: the first tap must stay on clarionlabs.tech so the Amazon app can't
    /// intercept and strip the affiliate tag). Empty for in_app_cart.
    var url: String
    var presetId: String
    var external: Bool
    /// "Opens on Amazon · Clarion may earn a commission"
    var fulfillmentNote: String

    var isExternalLink: Bool { mode == "external_link" }

    var resolvedURL: URL? {
        guard !url.isEmpty else { return nil }
        return URL(string: url)
    }
}

/// The three shop shelves, with the web's SECTION_HEAD_COPY (ShopHandoff.tsx) verbatim.
enum ShopBucket: Int, CaseIterable {
    case backed = 0
    case maintenance = 1
    case skip = 2

    var title: String {
        switch self {
        case .backed: return "Backed by your labs"
        case .maintenance: return "Maintenance"
        case .skip: return "No signal in your labs"
        }
    }

    var desc: String {
        switch self {
        case .backed: return "Tied to a flagged or trending marker"
        case .maintenance: return "Reasonable to keep, not essential"
        case .skip: return "We won’t push these on you"
        }
    }

    /// Per-bucket empty line, same words as the web's bucketEmptyMessage.
    func emptyLine(hasLabs: Bool) -> String {
        switch self {
        case .backed:
            return hasLabs
                ? "Nothing here based on your current labs — that's a good thing."
                : "Upload labs to see what's backed by your results."
        case .maintenance:
            return "No maintenance items right now."
        case .skip:
            return "No low-signal items to browse right now."
        }
    }
}
