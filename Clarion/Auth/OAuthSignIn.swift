import AuthenticationServices
import UIKit

/// Web-based OAuth (Google / Apple) via GoTrue's /authorize endpoint + ASWebAuthenticationSession.
/// No SDK, no URL-scheme registration in Info.plist (ASWebAuthenticationSession intercepts the
/// callback scheme directly). GoTrue redirects to `clarionlabs://login-callback#access_token=…`
/// in the implicit flow; we parse the fragment into a session.
///
/// REQUIRES: `clarionlabs://login-callback` in Supabase → Auth → URL Configuration → Redirect URLs.
enum OAuthProvider: String {
    case google
    case apple
}

extension SupabaseAuth {
    static let oauthCallbackScheme = "clarionlabs"
    static let oauthRedirect = "clarionlabs://login-callback"

    func signInWithOAuth(_ provider: OAuthProvider) async throws {
        var comps = URLComponents(
            url: Config.supabaseURL.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: Self.oauthRedirect),
        ]
        guard let authURL = comps.url else { throw AuthError.network("Couldn't start sign-in.") }

        let callback = try await presentWebAuth(url: authURL)
        let session = try await sessionFromCallback(callback)
        applyExternalSession(session)
    }

    // MARK: - Present the web session

    private func presentWebAuth(url: URL) async throws -> URL {
        let presenter = WebAuthPresenter()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.oauthCallbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.badCredentials("Sign-in cancelled."))
                } else {
                    continuation.resume(throwing: AuthError.network(error?.localizedDescription ?? "Sign-in failed."))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false // remember the Google/Apple login
            // Retain the presenter for the session's lifetime.
            objc_setAssociatedObject(session, &WebAuthPresenter.key, presenter, .OBJC_ASSOCIATION_RETAIN)
            if !session.start() {
                continuation.resume(throwing: AuthError.network("Couldn't open the sign-in window."))
            }
        }
    }

    // MARK: - Parse callback → session

    private func sessionFromCallback(_ url: URL) async throws -> SupabaseSession {
        // Tokens arrive in the URL fragment (implicit flow).
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            throw AuthError.badCredentials("Sign-in didn't complete. Please try again.")
        }
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        if let errDesc = params["error_description"] {
            throw AuthError.badCredentials(errDesc.replacingOccurrences(of: "+", with: " "))
        }
        guard let access = params["access_token"], let refresh = params["refresh_token"] else {
            throw AuthError.badCredentials("Sign-in didn't return a session. Please try again.")
        }
        let expiresIn = Double(params["expires_in"] ?? "3600") ?? 3600
        let user = try await fetchUser(accessToken: access)
        return SupabaseSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userId: user.id,
            email: user.email
        )
    }

    private struct UserResponse: Codable {
        var id: String
        var email: String?
    }

    private func fetchUser(accessToken: String) async throws -> UserResponse {
        var req = URLRequest(url: Config.supabaseURL.appendingPathComponent("auth/v1/user"))
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.network("Couldn't load your account.")
        }
        return try JSONDecoder().decode(UserResponse.self, from: data)
    }
}

/// Supplies the presentation window for ASWebAuthenticationSession.
final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static var key: UInt8 = 0
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
