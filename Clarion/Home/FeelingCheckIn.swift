import SwiftUI

/// A local, per-day subjective wellness check-in — "How are you feeling?" — for the days
/// (and devices, like the simulator with no synced Health data) when a wearable can't supply
/// readiness. Stored on-device only, keyed by user + local day. When the wearable is quiet,
/// this drives the hero ring so Home is never a blank "New day."
///
/// Deliberately NOT written to the server: DailyMetrics has no subjective field, and a
/// same-day RPE/wellness tap is a device-local nicety, not a lab input. If we later add a
/// `feeling` column to the metrics API, this becomes its client cache.
@MainActor
final class FeelingStore: ObservableObject {
    /// 1 (drained) … 5 (great). nil = not answered yet today.
    @Published private(set) var today: Int?

    private let key: String

    init(userId: String?) {
        self.key = "clarion_feeling_\(userId ?? "demo")_\(LocalDay.todayIso())"
        let stored = UserDefaults.standard.integer(forKey: key) // 0 when absent
        var value: Int? = stored == 0 ? nil : stored
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_FEELING") { value = 4 }
        #endif
        self.today = value
    }

    func set(_ level: Int) {
        let clamped = min(5, max(1, level))
        today = clamped
        UserDefaults.standard.set(clamped, forKey: key)
        Haptics.commit()
    }

    /// Subjective readiness the ring can show when there's no wearable reading. Mapped onto
    /// the same bands the hero caption uses (rest → take it easy → well recovered → charged).
    var readiness: Int? {
        switch today {
        case 1: return 38
        case 2: return 52
        case 3: return 66
        case 4: return 80
        case 5: return 92
        default: return nil
        }
    }

    /// The word beside the ring when readiness is self-reported (not the wearable tier).
    var word: String? {
        switch today {
        case 1: return "Drained"
        case 2: return "Running low"
        case 3: return "Steady"
        case 4: return "Good"
        case 5: return "Great"
        default: return nil
        }
    }

    static let levels: [(level: Int, label: String)] = [
        (1, "Drained"),
        (2, "Tired"),
        (3, "Steady"),
        (4, "Good"),
        (5, "Great"),
    ]
}
