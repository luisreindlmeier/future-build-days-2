import SwiftUI

/// The app's haptics, two ticks of its own next to the system's. `.firm` marks a decision: X or check on a card,
/// "I don't know it", "I already know this", an answer in the placement test, a word bookmarked, added or started
/// over, "Learn 5". `.soft` marks a smaller step: a card or a sentence revealed, a switch flipped, a tile turned, an
/// answer taken back. `.selection` marks a choice (a picker, the background, a word marked in a sentence) and the
/// edge of a drag, where letting go would decide. `.success`, `.warning` and `.error` tell a typed answer's result,
/// and `.success` a round or the onboarding done. Each sits on the view whose state it follows, through
/// `sensoryFeedback`, so a swipe and a tap feel the same.
extension SensoryFeedback {
    static let firm = SensoryFeedback.impact(flexibility: .rigid, intensity: 1)
    static let soft = SensoryFeedback.impact(weight: .light, intensity: 1)
}
