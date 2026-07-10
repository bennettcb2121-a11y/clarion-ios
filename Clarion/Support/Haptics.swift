import UIKit

/// One tap-feel vocabulary for the whole app. Every interactive control routes through these
/// so the app has a consistent physical personality: light for taps, medium for commits,
/// success/warning notifications for outcomes.
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let selectionGen = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()

    /// Small tap — buttons, chips, cards.
    static func tap() { light.impactOccurred() }

    /// Softer touch — passive elements, pull-to-refresh start.
    static func touch() { soft.impactOccurred(intensity: 0.7) }

    /// Commit — primary actions (sync now, save, sign in).
    static func commit() { medium.impactOccurred() }

    /// Selection change — tab switches, pickers, reorder.
    static func selection() { selectionGen.selectionChanged() }

    static func success() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
}
