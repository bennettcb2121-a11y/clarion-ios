import Foundation
import SwiftUI

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
            let calendar = Calendar.current
            let end = Date()
            let backfillDays = lastSyncedAt == nil ? Config.firstSyncBackfillDays : Config.incrementalSyncDays
            let start = calendar.date(byAdding: .day, value: -backfillDays, to: end) ?? end

            let daily = try await DailyNormalizer.build(start: start, end: end, health: health)
            let workouts = try await WorkoutNormalizer.build(start: start, end: end, health: health)

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
            status = .failed(error.localizedDescription)
        }
    }
}
