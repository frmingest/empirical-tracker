import UIKit

/// A single, quiet success haptic for completed logging actions (food entry,
/// body metric, applied lab import, planned meal logged to the diary).
/// Deliberately no celebration animations or badges — acknowledgment, not
/// gamification, fits this product's clinical posture.
@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
