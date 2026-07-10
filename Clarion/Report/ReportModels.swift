import Foundation

/// Response of GET /api/report — the user's latest analyzed bloodwork + supplement stack.
struct ReportResponse: Codable {
    var hasBloodwork: Bool
    var score: Int?
    var scoreLabel: String?
    var counts: StatusCounts?
    var lastUpdated: String?
    var results: [BiomarkerResult]?
    var stack: [StackItem]?
    var stackMonthlyCost: Double?
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
    var optimalMin: Double?
    var optimalMax: Double?
    var status: String // deficient | low | suboptimal | optimal | high | unknown
    var whyItMatters: String?

    var id: String { name }

    var isFlagged: Bool { status == "low" || status == "deficient" || status == "high" || status == "suboptimal" }

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
}

struct StackItem: Codable, Identifiable {
    var name: String
    var dose: String
    var monthlyCost: Double
    var recommendationType: String
    var reason: String
    var marker: String?

    var id: String { name }
}
