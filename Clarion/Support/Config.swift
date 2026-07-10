import Foundation

/// Central configuration. Values are safe to ship in the binary: the Supabase anon key is a
/// public client key (RLS enforces access), same as the web app exposes.
enum Config {
    /// The Clarion web backend that receives normalized metrics.
    static let apiBase = URL(string: "https://clarionlabs.tech")!

    /// Supabase project — SAME project as the web app so accounts are shared.
    /// TODO(charlie): paste the real values from bloodwise-frontend/.env.local
    /// (NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY) before first build.
    static let supabaseURL = URL(string: "https://YOUR-PROJECT.supabase.co")!
    static let supabaseAnonKey = "YOUR-ANON-KEY"

    /// Sent with every ingest request so the server can detect stale installed versions.
    static var clientVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "ios-\(v)+\(b)"
    }

    /// How much history the FIRST sync backfills. 90 days gives baselines + the money story;
    /// later syncs only cover the recent window.
    static let firstSyncBackfillDays = 90
    static let incrementalSyncDays = 14
}
