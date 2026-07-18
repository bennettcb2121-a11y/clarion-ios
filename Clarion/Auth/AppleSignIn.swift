import Foundation
import CryptoKit

/// Nonce plumbing for native Sign in with Apple. Apple expects the SHA256 of a random nonce in
/// the authorization request; the RAW nonce is kept and handed to Supabase, which re-hashes and
/// matches it against the identity token's `nonce` claim — proving the token was minted for THIS
/// request (replay protection).
enum AppleNonce {
    /// A cryptographically-random raw nonce.
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// Lowercase hex SHA256 — what goes into `ASAuthorizationAppleIDRequest.nonce`.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
