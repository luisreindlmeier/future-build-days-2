import SwiftUI
import UIKit

extension Font {
    /// Titles and key numbers: the system face, bold, a little tighter.
    static func display(_ size: CGFloat, relativeTo style: TextStyle = .largeTitle) -> Font {
        .system(size: size, weight: .bold)
    }
}

private struct AppFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let size: CGFloat
    let weight: Font.Weight
    let style: UIFont.TextStyle
    let lineHeight: CGFloat?

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
        content
            .font(.system(size: scaled, weight: weight))
            .lineHeight(lineHeight.map { .exact(points: scaled * $0) })
    }
}

extension View {
    /// SF Pro at a design size that follows Dynamic Type. `lineHeight` is a multiple of the font size, as in the design.
    func appFont(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: UIFont.TextStyle = .body, lineHeight: CGFloat? = nil) -> some View {
        modifier(AppFont(size: size, weight: weight, style: style, lineHeight: lineHeight))
    }
}
