import Foundation

// Wire shapes for POST /api/chat (Ask Clarion) — verified against the route's doc-block
// (app/api/chat/route.ts). NOT streaming: one JSON round-trip per send; the client owns
// the transcript and replays it via conversationHistory (server keeps the last 24).

/// One transcript turn as the API knows it — roles are "user" | "assistant" only.
struct ChatWireTurn: Codable {
    let role: String
    let content: String
}

struct ChatRequest: Encodable {
    let message: String
    /// Plain-text panel snapshot (≤12,000 chars server-side); omitted when no labs.
    let biomarkerSnapshot: String?
    let conversationHistory: [ChatWireTurn]?
}

struct ChatResponse: Decodable {
    let reply: String
}

/// Error body for every non-2xx status. `code == "consent_required"` on 403 means the
/// user hasn't granted ai_processing consent — grant via POST /api/consents/record, retry.
struct ChatErrorResponse: Decodable {
    let error: String
    let code: String?
    let missing: [String]?
}

// MARK: - Native snapshot builder

/// Builds the exact plain-text snapshot the web sends (src/lib/biomarkerAiContext.ts,
/// buildBiomarkerSnapshotForAi): score line, status counts, then one "- Name: value
/// (status; target min–max)" line per marker, alphabetical. It's a plain string the
/// server pastes into the system prompt — no schema risk.
enum BiomarkerSnapshot {
    static func build(from report: ReportResponse) -> String? {
        guard let results = report.results, !results.isEmpty else { return nil }
        var lines: [String] = []
        lines.append("Clarion health score (0–100): \(ScoreEngine.score(results))")

        let sorted = results.sorted { $0.name < $1.name }
        func count(_ s: String) -> Int { sorted.filter { $0.status == s }.count }
        lines.append(
            "Counts — optimal: \(count("optimal")), suboptimal: \(count("suboptimal")), deficient: \(count("deficient")), high: \(count("high")), unknown: \(count("unknown"))"
        )
        lines.append("Markers:")
        for r in sorted {
            let target: String
            if let lo = r.optimalMin, let hi = r.optimalMax {
                target = "target \(trim(lo))–\(trim(hi))"
            } else {
                target = "target not available"
            }
            lines.append("- \(r.name): \(trim(r.value)) (\(r.status); \(target))")
        }
        return lines.joined(separator: "\n")
    }

    /// "34.0" → "34", "5.1" stays "5.1" — matches JS number stringification.
    private static func trim(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15
            ? String(Int(v))
            : String(v)
    }
}
