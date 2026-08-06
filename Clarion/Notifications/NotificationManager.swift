import Foundation
import UserNotifications

/// Local notifications for the daily protocol reminder.
///
/// Until this existed the app could not deliver a single notification — there was no
/// `import UserNotifications` anywhere in the target. The reminder SETTINGS shipped long ago
/// (daily_reminder, daily_reminder_time, daily_reminder_timezone, daily_reminder_channel), so a
/// user could switch reminders on, pick a time, and their phone would never make a sound. The
/// server quietly emailed them instead. For a product whose whole retention story is a daily
/// loop, the loop had no bell.
///
/// LOCAL, not push, on purpose. A dose reminder is a fixed daily time the device already knows —
/// it needs no server round trip, works in airplane mode, survives a backend outage, and needs
/// no APNs certificates or device-token plumbing. Push is for things the server learns first
/// (a lab result landing); this is not that.
///
/// Pairs with `daily_reminder_channel == "device"` on the server, which makes the cron skip the
/// user entirely (app/api/cron/daily-protocol-reminder). That coupling matters: the existing
/// "push" channel needs a web-push subscription row an iOS app cannot create, so it would fall
/// through to email and the user would get the notification AND the email for the same doses.
@MainActor
final class NotificationManager: ObservableObject {

    static let shared = NotificationManager()

    /// One stable identifier so rescheduling replaces rather than stacks duplicates.
    private static let dailyDoseID = "clarion.daily-dose"

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private init() {}

    // MARK: - Permission

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    /// Ask only at the moment the user turns reminders ON. Prompting at launch — before they've
    /// asked for anything — is how apps burn their one shot at the permission and never get it back.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedule (or reschedule) the daily dose reminder.
    ///
    /// - Parameters:
    ///   - time: "HH:mm" as stored in `daily_reminder_time`.
    ///   - body: the dose summary to show. Kept caller-supplied so the copy can stay in step with
    ///           the server's wording rather than being invented twice.
    func scheduleDailyDose(time: String, body: String) async {
        guard let comps = Self.hourMinute(from: time) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Today's doses"
        content.body = body
        content.sound = .default
        // Deep link target for the tap handler; the daily loop lives on Home.
        content.userInfo = ["route": "home"]

        var date = DateComponents()
        date.hour = comps.hour
        date.minute = comps.minute
        // `repeats: true` on hour+minute fires daily in the DEVICE's current timezone, which is
        // what a person actually means by "remind me at 8am" — it follows them when they travel,
        // where a server-side timezone string does not.
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)

        let request = UNNotificationRequest(identifier: Self.dailyDoseID, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyDoseID])
        try? await center.add(request)
    }

    func cancelDailyDose() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.dailyDoseID])
    }

    /// True when a daily reminder is actually queued — used to show honest state in Settings
    /// rather than trusting the toggle, which can drift from reality if permission was revoked
    /// in iOS Settings after the fact.
    func hasScheduledDailyDose() async -> Bool {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.contains { $0.identifier == Self.dailyDoseID }
    }

    // MARK: - Parsing

    /// "08:30" / "8:30" / "08:30:00" → (8, 30). Nil on anything it can't trust, so a malformed
    /// stored value silently schedules nothing rather than firing at midnight.
    static func hourMinute(from time: String) -> (hour: Int, minute: Int)? {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}
