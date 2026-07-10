import Foundation

/// POSTs normalized batches to the Clarion backend. Auth is the Supabase access token as a
/// Bearer header — the server validates it and RLS scopes every write to this user
/// (bloodwise-frontend src/lib/apiAuth.ts).
enum IngestError: LocalizedError {
    case http(Int, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let message): return "Sync failed (\(code)): \(message)"
        case .network(let message): return message
        }
    }
}

enum IngestClient {
    static func post(
        daily: [WearableDailyMetrics],
        workouts: [WearableWorkout],
        accessToken: String
    ) async throws -> IngestResponse {
        let payload = IngestPayload(
            provider: "apple_health",
            clientVersion: Config.clientVersion,
            daily: daily,
            workouts: workouts
        )

        var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/wearables/ingest"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw IngestError.network("No response — check your connection.")
        }
        let decoded = (try? JSONDecoder().decode(IngestResponse.self, from: data)) ?? IngestResponse()
        guard http.statusCode == 200 else {
            throw IngestError.http(http.statusCode, decoded.error ?? "unknown error")
        }
        return decoded
    }
}
