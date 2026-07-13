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

    // MARK: - Ask Clarion (POST /api/chat)

    /// One stateless chat round-trip (the endpoint doesn't stream; the client owns the
    /// transcript). Throws `.consentRequired` on the 403 consent wall so callers can
    /// grant ai_processing via `recordConsent` and retry.
    static func chat(
        message: String,
        biomarkerSnapshot: String?,
        conversationHistory: [ChatWireTurn],
        accessToken: String
    ) async throws -> String {
        let body = try JSONEncoder().encode(ChatRequest(
            message: message,
            biomarkerSnapshot: biomarkerSnapshot,
            conversationHistory: conversationHistory.isEmpty ? nil : conversationHistory
        ))
        let data = try await post("api/chat", body: body, accessToken: accessToken)
        return try JSONDecoder().decode(ChatResponse.self, from: data).reply
    }

    /// Record an affirmative consent (e.g. "ai_processing") — bearer-ready endpoint; the
    /// server captures the audit hashes itself.
    static func recordConsent(type: String, accessToken: String) async throws {
        let body = try JSONEncoder().encode(["consentType": type])
        _ = try await post("api/consents/record", body: body, accessToken: accessToken)
    }

    // MARK: - Settings (GET/PATCH /api/account/profile)

    private struct ProfileEnvelope: Decodable { var profile: ProfileSettings? }
    private struct ProfilePatchEnvelope: Decodable { var ok: Bool; var profile: ProfileSettings? }

    /// The settings read. `nil` (not an error) for survey-less users so the client can
    /// render the "finish the survey" empty state.
    static func fetchProfileSettings(accessToken: String) async throws -> ProfileSettings? {
        let data = try await get("api/account/profile", accessToken: accessToken)
        return try JSONDecoder().decode(ProfileEnvelope.self, from: data).profile
    }

    /// Partial profile update. Values may be String / Int / Double / Bool / NSNull (null
    /// clears a field). The server validates enums and rejects locked keys with a 400
    /// whose message is user-surfaceable; the fresh row is echoed back.
    static func updateProfileSettings(patch: [String: Any], accessToken: String) async throws -> ProfileSettings {
        let body = try JSONSerialization.data(withJSONObject: patch)
        let data = try await send(request("api/account/profile", method: "PATCH", body: body, accessToken: accessToken))
        guard let profile = try JSONDecoder().decode(ProfilePatchEnvelope.self, from: data).profile else {
            throw APIError.decode
        }
        return profile
    }

    // MARK: - Plumbing

    enum APIError: LocalizedError {
        case http(Int, String)
        /// 403 with code == "consent_required" — grant ai_processing and retry.
        case consentRequired
        case decode
        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): return "Request failed (\(code)): \(msg)"
            case .consentRequired: return "Turn on AI insights to use the assistant."
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
        try await send(request(path, method: "POST", body: body, accessToken: accessToken))
    }

    private static func request(_ path: String, method: String, body: Data, accessToken: String) -> URLRequest {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        return req
    }

    private static func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.decode }
        guard (200..<300).contains(http.statusCode) else {
            // The consent wall is a distinct, recoverable state — surface it as its own case.
            if http.statusCode == 403,
               let err = try? JSONDecoder().decode(ChatErrorResponse.self, from: data),
               err.code == "consent_required" {
                throw APIError.consentRequired
            }
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "error"
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }
}
