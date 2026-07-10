import Foundation

/// Small authenticated JSON client for the non-ingest Clarion endpoints (persona, account
/// deletion, dashboard handoff). Every call carries the Supabase access token as a Bearer.
enum ClarionAPI {
    struct PersonaResponse: Codable {
        var persona: String
        var sex: String?
        var menopauseStage: String?
    }

    private struct LinkResponse: Codable { var url: String }
    private struct ErrorResponse: Codable { var error: String? }

    /// The user's wearable persona, so HealthKit permissions can be scoped to their goals.
    /// Defaults to `.general` on any failure — never block the connect flow on this.
    static func fetchPersona(accessToken: String) async -> Persona {
        do {
            let data = try await get("api/account/persona", accessToken: accessToken)
            let decoded = try JSONDecoder().decode(PersonaResponse.self, from: data)
            return Persona(rawValue: decoded.persona) ?? .general
        } catch {
            return .general
        }
    }

    /// Mint a one-time login URL to the web dashboard (lands the user signed in).
    static func dashboardLoginLink(path: String, accessToken: String) async throws -> URL {
        let body = try JSONEncoder().encode(["path": path])
        let data = try await post("api/account/app-login-link", body: body, accessToken: accessToken)
        let decoded = try JSONDecoder().decode(LinkResponse.self, from: data)
        guard let url = URL(string: decoded.url) else { throw APIError.decode }
        return url
    }

    /// Permanently delete the account. Irreversible; the caller signs out after.
    static func deleteAccount(accessToken: String) async throws {
        let body = try JSONEncoder().encode(["confirm": "DELETE"])
        _ = try await post("api/account/delete", body: body, accessToken: accessToken)
    }

    // MARK: - Plumbing

    enum APIError: LocalizedError {
        case http(Int, String)
        case decode
        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): return "Request failed (\(code)): \(msg)"
            case .decode: return "Unexpected response from Clarion."
            }
        }
    }

    private static func get(_ path: String, accessToken: String) async throws -> Data {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent(path))
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    private static func post(_ path: String, body: Data, accessToken: String) async throws -> Data {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        return try await send(req)
    }

    private static func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.decode }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "error"
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }
}
