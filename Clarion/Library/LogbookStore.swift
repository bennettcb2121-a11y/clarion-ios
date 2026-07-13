import Foundation
import SwiftUI

/// The Logbook's month store: protocol_log rows for the visible 42-cell grid
/// (GET /api/protocol-log?start&end) plus the lab-day badges and retest anchor
/// (GET /api/logbook/labs — fetched once, timestamps bucketed to LOCAL days
/// on-device because the server can't know the phone's timezone).
@MainActor
final class LogbookStore: ObservableObject {
    enum State {
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .loading
    /// First of the visible month (local midnight).
    @Published private(set) var monthDate: Date = LogbookGrid.firstOfMonth(Date())
    @Published private(set) var month: LogbookMonth?
    @Published private(set) var labs: LogbookLabsResponse?

    private var labDates: Set<String> = []
    private(set) var nextRetestIso: String?
    private var labsLoaded = false

    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) { self.auth = auth }

    /// In-month header stats (web monthStats memo): days logged / items checked.
    var monthStats: (daysLogged: Int, totalChecks: Int) {
        guard let month else { return (0, 0) }
        let inMonth = month.days.filter(\.inMonth)
        return (
            inMonth.filter { $0.checksCompleted > 0 }.count,
            inMonth.reduce(0) { $0 + $1.checksCompleted }
        )
    }

    var nextRetestLabel: String? {
        nextRetestIso.map { NextDrawCountdown.labelFor($0) }
    }

    func load() async {
        await loadLabsIfNeeded()
        await loadMonth()
    }

    func move(byMonths delta: Int) async {
        monthDate = LogbookGrid.firstOfMonth(
            Calendar.current.date(byAdding: .month, value: delta, to: monthDate) ?? monthDate
        )
        await loadMonth()
    }

    // MARK: - Fetches

    private func loadLabsIfNeeded() async {
        guard !labsLoaded else { return }
        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/logbook/labs"))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(LogbookLabsResponse.self, from: data)
            adoptLabs(decoded)
            labsLoaded = true
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") }) {
                adoptLabs(Self.demoLabs())
                labsLoaded = true
                return
            }
            #endif
            // Badges are decoration — the grid still renders without them.
            labsLoaded = false
        }
    }

    private func adoptLabs(_ decoded: LogbookLabsResponse) {
        labs = decoded
        labDates = LocalDay.collectLabDates(saves: decoded.bloodworkSaves, sessions: decoded.labSessions)
        // Retest target = latest local lab day + retest_weeks (default 8) —
        // the same math as the web logbook chip (reusing the DailyLoop port).
        if let lastLab = labDates.max() {
            nextRetestIso = NextDrawCountdown.computeNextRetestDate(
                lastDrawIso: lastLab,
                retestWeeks: decoded.retestWeeks
            )
        } else {
            nextRetestIso = nil
        }
    }

    private func loadMonth() async {
        let range = LogbookGrid.monthGridRange(monthDate)
        do {
            let token = try await auth.validAccessToken()
            var comps = URLComponents(
                url: Config.apiBase.appendingPathComponent("api/protocol-log"),
                resolvingAgainstBaseURL: false
            )!
            comps.queryItems = [
                URLQueryItem(name: "start", value: range.startIso),
                URLQueryItem(name: "end", value: range.endIso),
            ]
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(ProtocolLogRangeResponse.self, from: data)
            rebuildGrid(rows: decoded.rows)
            state = .ready
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") }) {
                rebuildGrid(rows: Self.demoRows())
                state = .ready
                return
            }
            #endif
            state = .error("Couldn't load your logbook. Pull to retry.")
        }
    }

    private func rebuildGrid(rows: [ProtocolLogRow]) {
        month = LogbookGrid.buildMonthGrid(
            monthDate: monthDate,
            todayIso: LocalDay.todayIso(),
            rows: rows,
            labDates: labDates,
            nextRetestIso: nextRetestIso
        )
    }

    // MARK: - Demo (UITEST)

    #if DEBUG
    /// A lab draw four weeks back (retest lands four weeks out on the default
    /// 8-week cadence) and a twelve-day dose streak with one honest gap.
    static func demoLabs() -> LogbookLabsResponse {
        let drawDay = LocalDay.addDays(Date(), -28)
        let iso = ISO8601DateFormatter().string(from: drawDay)
        return LogbookLabsResponse(
            bloodworkSaves: [LabSaveMarker(createdAt: iso, score: 86, markerCount: 24)],
            labSessions: [LabSessionMarker(collectedAt: LocalDay.toIso(drawDay), createdAt: iso, status: "confirmed")],
            retestWeeks: 8
        )
    }

    static func demoRows() -> [ProtocolLogRow] {
        var rows: [ProtocolLogRow] = []
        for i in 0...12 where i != 4 { // one missed day keeps the grid honest
            let iso = LocalDay.toIso(LocalDay.addDays(Date(), -i))
            var checks: [String: Bool] = [
                "Iron — gentle (bisglycinate)": true,
                "Vitamin D3": true,
            ]
            if i % 2 == 0 { checks["Magnesium glycinate"] = true }
            rows.append(ProtocolLogRow(
                logDate: iso,
                checks: checks,
                metrics: i < 7
                    ? DailyMetrics(activity_level: 3, sun_minutes: 20, hydration_cups: 6, sleep_hours: 7.5)
                    : DailyMetrics()
            ))
        }
        return rows.sorted { $0.logDate < $1.logDate }
    }
    #endif
}
