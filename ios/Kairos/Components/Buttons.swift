import SwiftUI

/// The one navy button per screen.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var radius: CGFloat = Radius.button
    var fontSize: CGFloat = 17
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .appFont(fontSize, .semibold, relativeTo: .headline)
            .onBrand()
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                BrandSurface()
                    .clipShape(shape)
                    .overlay(alignment: .top) {
                        shape.stroke(
                            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)),
                            lineWidth: 1
                        )
                    }
                    .brandButtonShadow()
            }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// White, no border, key shadow.
struct SecondaryButtonStyle: ButtonStyle {
    var small = false
    var fill = true
    var fontSize: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: small ? Radius.buttonSmall : Radius.button, style: .continuous)
        configuration.label
            .appFont(fontSize ?? (small ? 15 : 16), .semibold, relativeTo: .callout)
            .foregroundStyle(Color.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: fontSize != nil ? 64 : small ? 40 : 52)
            .background {
                shape
                    .fill(configuration.isPressed ? Color.pressed : Color.surface)
                    .keyShadow()
            }
            .contentShape(shape)
    }
}

/// Label in ink, no background, 44 pt high.
struct TextButtonStyle: ButtonStyle {
    @Environment(\.inkColor) private var ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(15, .medium, relativeTo: .subheadline)
            .foregroundStyle(ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryCompact: PrimaryButtonStyle { PrimaryButtonStyle(height: 46, radius: Radius.buttonSmall) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var secondarySmall: SecondaryButtonStyle { SecondaryButtonStyle(small: true, fill: false) }
}

extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
}

/// Label for text buttons: icon, 8 pt gap, text.
struct IconLabel: View {
    let title: LocalizedStringKey
    let icon: String
    var iconSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            Icon(icon, size: iconSize)
            Text(title)
        }
    }
}
