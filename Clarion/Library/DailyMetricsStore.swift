import Foundation
import SwiftUI

/// The Daily-inputs store: today's self-reported metrics + the 90-day history
/// behind the week strip and averages, written through PUT /api/protocol-log/metrics
/// with REPLACE semantics (the full merged object every time — the route upserts
/// metrics without touching checks, so dose logs can never be clobbered).
@MainActor
final class DailyMetricsStore: ObservableObject {
    enum State {
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .loading
    /// Today's metrics — optimistically patched on edit, reverted on failure,
    /// then re-synced to the server's clamped echo on success.
    @Published private(set) var today = DailyMetrics()
    /// Last ~90 days ascending by logDate (the week strip + averages input).
    @Published private(set) var history: [ProtocolLogRow] = []
    /// True when a REAL wearable snapshot exists (isDemo false) — the inputs
    /// page then hides its counter and points to Vitals, mirroring the web.
    @Published private(set) var hasWearable = false
    @Published private(set) var saving = false

    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) { self.auth = auth }

    var todayIso: String { LocalDay.todayIso() }

    func load() async {
        do {
            let end = todayIso
            let start = LocalDay.toIso(LocalDay.addDays(Date(), -90))
            var comps = URLComponents(
                url: Config.apiBase.appendingPathComponent("api/protocol-log"),
                resolvingAgainstBaseURL: false
            )!
            comps.queryItems = [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end),
            ]
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(ProtocolLogRangeResponse.self, from: data)
            history = decoded.rows
            today = decoded.rows.first(where: { $0.logDate == end })?.metrics ?? DailyMetrics()
            state = .ready
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") }) {
                applyDemo()
                return
            }
            #endif
            state = .error("Couldn't load your daily inputs. Pull to retry.")
        }
        await probeWearable()
    }

    /// Best-effort wearable signal (the web's `loadWearableSnapshot != null`):
    /// GET /api/wearables/snapshot, honoring the server's isDemo flag. Any
    /// failure just means "no wearable" — never blocks the inputs page.
    private func probeWearable() async {
        struct Probe: Codable {
            struct Snap: Codable { var isDemo: Bool? }
            var snapshot: Snap?
        }
        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/wearables/snapshot"))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let probe = try JSONDecoder().decode(Probe.self, from: data)
            hasWearable = probe.snapshot?.isDemo == false
        } catch {
            hasWearable = false
        }
    }

    /// Patch today's metrics: optimistic locally, clamp client-side, PUT the
    /// FULL merged object (replace semantics), adopt the server's clamped echo.
    /// On failure the optimistic patch reverts with a warning haptic.
    func update(_ mutate: (inout DailyMetrics) -> Void) async {
        let previous = today
        var next = today
        mutate(&next)
        next = next.clamped()
        today = next
        saving = true
        defer { saving = false }

        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/protocol-log/metrics"))
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONEncoder().encode(MetricsPutRequest(logDate: todayIso, metrics: next))
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let echoed = try JSONDecoder().decode(MetricsPutResponse.self, from: data)
            today = echoed.metrics
            upsertHistoryRow(echoed.metrics)
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") }) {
                upsertHistoryRow(next) // demo mode: keep the optimistic value
                return
            }
            #endif
            today = previous
            Haptics.warning()
        }
    }

    private func upsertHistoryRow(_ metrics: DailyMetrics) {
        let iso = todayIso
        if let idx = history.firstIndex(where: { $0.logDate == iso }) {
            history[idx].metrics = metrics
        } else {
            history.append(ProtocolLogRow(logDate: iso, checks: [:], metrics: metrics))
            history.sort { $0.logDate < $1.logDate }
        }
    }

    #if DEBUG
    /// A believable mid-afternoon: sleep + sun + training in, hydration not yet
    /// logged (exercises the amber warn path), a week of partial history.
    private func applyDemo() {
        today = DailyMetrics(activity_level: 3, sun_minutes: 25, sleep_hours: 7.5)
        var rows: [ProtocolLogRow] = []
        for i in stride(from: 6, through: 1, by: -1) {
            let iso = LocalDay.toIso(LocalDay.addDays(Date(), -i))
            let logged = i != 2 // one gap so the strip isn't a lie
            rows.append(ProtocolLogRow(
                logDate: iso,
                checks: [:],
                metrics: logged
                    ? DailyMetrics(activity_level: Double(1 + (i % 4)), sun_minutes: 20, hydration_cups: 6, sleep_hours: 7)
                    : DailyMetrics()
            ))
        }
        rows.append(ProtocolLogRow(logDate: todayIso, checks: [:], metrics: today))
        history = rows
        hasWearable = false
        state = .ready
    }
    #endif
}
