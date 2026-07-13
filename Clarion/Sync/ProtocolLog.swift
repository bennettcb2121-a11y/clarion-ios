import Foundation

/// One-tap dose logging against the same `protocol_log` table the web logbook reads.
/// The web writes this table directly from the client through RLS (no API route exists),
/// so the app does the same via PostgREST: read today's row, merge the check, upsert.
///
/// Check keys: canonical `entry:<stackEntryId>` (from /api/report's `logKey`), with the
/// supplement name accepted as a legacy key by the web — so logs align in both directions.
@MainActor
final class ProtocolLogStore: ObservableObject {
    /// Today's checks, keyed by protocol log key. Optimistically updated on toggle.
    @Published private(set) var checks: [String: Bool] = [:]
    @Published private(set) var loaded = false

    /// Recent days (local YYYY-MM-DD → any dose checked that day) — the streak +
    /// re-engage inputs the web reads from getProtocolLogHistory(14).
    @Published private(set) var recentDays: [String: Bool] = [:]
    /// Newest log_date on file (any row counts, like the web's lastLogDate memo).
    @Published private(set) var lastLogDate: String?

    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) { self.auth = auth }

    /// User-local YYYY-MM-DD, matching the web's log_date convention.
    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// True when this stack row is checked today (canonical or legacy name key).
    func isDone(_ item: StackItem) -> Bool {
        checks[item.protocolKey] == true || checks[item.name] == true
    }

    var doneCount: Int { checks.values.filter { $0 }.count }

    func load() async {
        if let fresh = try? await fetchTodayChecks() {
            checks = fresh
        }
        if let rows = try? await fetchRecentRows() {
            var byDate: [String: Bool] = [:]
            for row in rows {
                byDate[row.date] = row.checks.values.contains(true)
            }
            recentDays = byDate
            lastLogDate = rows.map(\.date).max()
        }
        loaded = true // never block the UI on the logbook
    }

    /// Whole days since the newest log row (0 = today). Mirrors the web's
    /// daysSinceLog: floor((now − Date(log_date)) / day) with UTC-midnight parsing.
    var daysSinceLog: Int? {
        guard let lastLogDate else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = lastLogDate.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let d = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return Int(floor(Date().timeIntervalSince(d) / 86_400))
    }

    /// Consecutive logged days ending today — the web's streak loop: history days
    /// count when ANY dose was checked; today counts only when COMPLETE.
    func streakDays(todayComplete: Bool) -> Int {
        var byDate = recentDays
        byDate[Self.todayKey()] = todayComplete
        var streak = 0
        let cal = Calendar.current
        for i in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: -i, to: Date()) else { break }
            if byDate[Self.todayKey(day)] == true { streak += 1 } else { break }
        }
        return streak
    }

    private struct HistoryRow: Codable {
        var log_date: String
        var checks: [String: Bool]?
    }

    private func fetchRecentRows() async throws -> [(date: String, checks: [String: Bool])] {
        guard let session = auth.session else { throw AuthError.noSession }
        let token = try await auth.validAccessToken()
        var comps = URLComponents(url: Config.supabaseURL.appendingPathComponent("rest/v1/protocol_log"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
            URLQueryItem(name: "select", value: "log_date,checks"),
            URLQueryItem(name: "order", value: "log_date.desc"),
            URLQueryItem(name: "limit", value: "14"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let rows = (try? JSONDecoder().decode([HistoryRow].self, from: data)) ?? []
        return rows.map { ($0.log_date, $0.checks ?? [:]) }
    }

    /// Toggle a dose for today. Optimistic locally; the write re-reads the server row and
    /// merges just this key so it can't clobber checks made on the web since launch.
    func toggle(_ item: StackItem) async {
        let key = item.protocolKey
        let newValue = !isDone(item)
        let previous = checks
        checks[key] = newValue
        // Clear a legacy name-key so unchecking actually unchecks rows logged by name.
        if !newValue { checks[item.name] = false }

        do {
            guard let session = auth.session else { throw AuthError.noSession }
            let token = try await auth.validAccessToken()

            // Merge against the freshest server state, changing only this row's key(s).
            var merged = (try? await fetchTodayChecks()) ?? previous
            merged[key] = newValue
            if !newValue { merged[item.name] = false }

            var comps = URLComponents(url: Config.supabaseURL.appendingPathComponent("rest/v1/protocol_log"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,log_date")]
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "POST"
            req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")

            let iso = ISO8601DateFormatter().string(from: Date())
            let payload: [String: Any] = [
                "user_id": session.userId,
                "log_date": Self.todayKey(),
                "checks": merged,
                "updated_at": iso,
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: [payload])
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            checks = merged
        } catch {
            checks = previous // revert the optimistic flip
            Haptics.warning()
        }
    }

    private func fetchTodayChecks() async throws -> [String: Bool] {
        guard let session = auth.session else { throw AuthError.noSession }
        let token = try await auth.validAccessToken()
        var comps = URLComponents(url: Config.supabaseURL.appendingPathComponent("rest/v1/protocol_log"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(session.userId)"),
            URLQueryItem(name: "log_date", value: "eq.\(Self.todayKey())"),
            URLQueryItem(name: "select", value: "checks"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Row: Codable { var checks: [String: Bool]? }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        return rows.first?.checks ?? [:]
    }
}
