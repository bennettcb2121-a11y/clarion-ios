import Foundation
import SwiftUI
import HealthKit

/// Orchestrates a sync: window selection (90-day backfill on first run, 14-day incremental
/// after), HealthKit reads → normalize → POST, and user-visible status. Foreground "open the
/// app" sync is the reliability floor; observer-triggered background syncs are a bonus.
@MainActor
final class SyncCoordinator: ObservableObject {
    enum Status: Equatable {
        case idle
        case syncing
        case done(daily: Int, workouts: Int, at: Date)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSummary: [WearableDailyMetrics] = []

    private let auth: SupabaseAuth
    private let health = HealthStore.shared
    private var inFlight = false

    private static let lastSyncKey = "clarion_last_sync_at"

    init(auth: SupabaseAuth) {
        self.auth = auth
    }

    var lastSyncedAt: Date? {
        UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    func sync() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        status = .syncing

        do {
            let token = try await auth.validAccessToken()
            // Request Health access RIGHT BEFORE the first read. Otherwise a fresh session
            // (or a stale "connected" flag) hits errorAuthorizationNotDetermined the instant
            // DailyNormalizer queries. Idempotent — the sheet shows only if undecided.
            try? await health.requestAuthorization()
            let calendar = Calendar.current
            let end = Date()
            let backfillDays = lastSyncedAt == nil ? Config.firstSyncBackfillDays : Config.incrementalSyncDays
            let start = calendar.date(byAdding: .day, value: -backfillDays, to: end) ?? end

            let daily = try await DailyNormalizer.build(start: start, end: end, health: health)
            let workouts = try await WorkoutNormalizer.build(start: start, end: end, health: health)

            // Reading succeeded but there's nothing on the wearable — common in the
            // simulator, or before a watch/Oura is ever paired. Don't POST an empty
            // payload (the ingest endpoint rejects it → looked like a sync failure) and
            // don't alarm the user: it's "up to date", not "failed".
            if daily.isEmpty && workouts.isEmpty {
                lastSummary = []
                UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
                status = .done(daily: 0, workouts: 0, at: Date())
                return
            }

            // Workouts cap matches the server (200/request); chunk the backfill if needed.
            var remainingWorkouts = workouts
            var postedDaily = 0
            var postedWorkouts = 0
            var firstChunk = true
            repeat {
                let chunk = Array(remainingWorkouts.prefix(200))
                remainingWorkouts = Array(remainingWorkouts.dropFirst(200))
                let response = try await IngestClient.post(
                    daily: firstChunk ? daily : [],
                    workouts: chunk,
                    accessToken: token
                )
                postedDaily += response.daily ?? 0
                postedWorkouts += response.workouts ?? 0
                firstChunk = false
            } while !remainingWorkouts.isEmpty

            UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
            lastSummary = Array(daily.suffix(3))
            status = .done(daily: postedDaily, workouts: postedWorkouts, at: Date())
        } catch {
            #if DEBUG
            print("[Sync] failed — raw error: \(error) | \((error as NSError).domain)#\((error as NSError).code)")
            #endif
            status = .failed(Self.friendlyMessage(for: error))
        }
    }

    /// Turn raw HealthKit/network errors into something a person can act on — never the
    /// bare "Authorization not determined" the user was seeing.
    private static func friendlyMessage(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == HKError.errorDomain {
            switch ns.code {
            case HKError.Code.errorAuthorizationNotDetermined.rawValue,
                 HKError.Code.errorAuthorizationDenied.rawValue:
                return "Apple Health access is off — allow it in Settings › Health › Clarion, then pull to refresh."
            default:
                return "Couldn't read Health data. Pull to refresh."
            }
        }
        return "Sync failed — check your connection and pull to refresh."
    }
}
