import CoreGraphics

enum Radius {
    static let button: CGFloat = 12
    static let buttonSmall: CGFloat = 10
    static let input: CGFloat = 10
    static let heroBlock: CGFloat = 16
    static let sheet: CGFloat = 14
    /// The bottom corners of a practice card.
    static let practiceCard: CGFloat = 36
    /// Just under the corners of the iPhone screen, so a card's top corners vanish into them at rest.
    static let screen: CGFloat = 55
    static let bar: CGFloat = 1
    static let wordHighlight: CGFloat = 4
}

enum Spacing {
    static let screenSide: CGFloat = 20
    /// The sides of a text page (the onboarding, the sheets) and of a practice card's content.
    static let pageSide: CGFloat = 28
    static let rowVertical: CGFloat = 13
    static let sectionGap: CGFloat = 28
}
