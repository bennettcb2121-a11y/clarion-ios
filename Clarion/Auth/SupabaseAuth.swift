import Foundation

/// Supabase auth via the GoTrue REST API with plain URLSession — deliberately dependency-free
/// for v1 (nothing to audit, nothing to break, no privacy-manifest surface). The supabase-swift
/// SDK can replace this later if Google/SIWA flows make it worthwhile; the rest of the app only
/// sees `session.accessToken`.
///
/// v1 auth = email + password. Google + Sign in with Apple land in Phase 2 (the App Store 4.8
/// requirement kicks in the moment Google is offered — see docs/ios-app-plan.md in the web repo).
struct SupabaseSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
    var email: String?

    var isExpiringSoon: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }
}

enum AuthError: LocalizedError {
    case badCredentials(String)
    case network(String)
    case noSession

    var errorDescription: String? {
        switch self {
        case .badCredentials(let m): return m
        case .network(let m): return m
        case .noSession: return "You're signed out."
        }
    }
}

@MainActor
final class SupabaseAuth: ObservableObject {
    @Published private(set) var session: SupabaseSession?

    private static let keychainKey = "supabase_session_v1"

    init() {
        if let data = Keychain.get(Self.keychainKey),
           let stored = try? JSONDecoder().decode(SupabaseSession.self, from: data) {
            session = stored
        }
    }

    var isSignedIn: Bool { session != nil }

    // MARK: - Flows

    func signIn(email: String, password: String) async throws {
        let body = ["email": email, "password": password]
        let session = try await tokenRequest(grantType: "password", body: body)
        persist(session)
    }

    /// Returns a fresh access token, refreshing first if the current one is near expiry.
    func validAccessToken() async throws -> String {
        guard let current = session else { throw AuthError.noSession }
        if !current.isExpiringSoon { return current.accessToken }
        let refreshed = try await tokenRequest(
            grantType: "refresh_token",
            body: ["refresh_token": current.refreshToken]
        )
        persist(refreshed)
        return refreshed.accessToken
    }

    /// Returns BOTH current tokens, refreshing first if the access token is near expiry
    /// (same refresh logic as `validAccessToken()`). The web-session handoff needs the
    /// refresh token too — the server calls `supabase.auth.setSession(access, refresh)`
    /// to write the @supabase/ssr cookie, so a slightly-stale access token is fine but a
    /// missing refresh token would strand the webview.
    func validSessionTokens() async throws -> (access: String, refresh: String) {
        guard let current = session else { throw AuthError.noSession }
        if !current.isExpiringSoon { return (current.accessToken, current.refreshToken) }
        let refreshed = try await tokenRequest(
            grantType: "refresh_token",
            body: ["refresh_token": current.refreshToken]
        )
        persist(refreshed)
        return (refreshed.accessToken, refreshed.refreshToken)
    }

    func signOut() {
        session = nil
        Keychain.delete(Self.keychainKey)
    }

    /// Adopt a session produced by an external flow (OAuth — see OAuthSignIn.swift).
    func applyExternalSession(_ s: SupabaseSession) { persist(s) }

    // MARK: - GoTrue REST

    private func persist(_ s: SupabaseSession) {
        session = s
        if let data = try? JSONEncoder().encode(s) {
            Keychain.set(data, forKey: Self.keychainKey)
        }
    }

    private struct TokenResponse: Codable {
        struct U: Codable {
            var id: String
            var email: String?
        }
        var access_token: String
        var refresh_token: String
        var expires_in: Double
        var user: U
    }

    private struct GoTrueError: Codable {
        var error_description: String?
        var msg: String?
        var message: String?
    }

    private func tokenRequest(grantType: String, body: [String: String]) async throws -> SupabaseSession {
        var comps = URLComponents(
            url: Config.supabaseURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No response from Clarion — check your connection.")
        }
        guard http.statusCode == 200 else {
            let err = try? JSONDecoder().decode(GoTrueError.self, from: data)
            let message = err?.error_description ?? err?.msg ?? err?.message
                ?? "Sign-in failed (\(http.statusCode))."
            throw AuthError.badCredentials(message)
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SupabaseSession(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: Date().addingTimeInterval(token.expires_in),
            userId: token.user.id,
            email: token.user.email
        )
    }
}
