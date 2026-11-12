import SwiftUI

extension View {
    /// White buttons and chips.
    func keyShadow() -> some View {
        shadow(color: Color.brand.opacity(0.10), radius: 0, y: 0.5)
            .shadow(color: Color.brand.opacity(0.06), radius: 1, y: 1)
            .shadow(color: Color.brand.opacity(0.09), radius: 5, y: 4)
    }

    func brandButtonShadow() -> some View {
        shadow(color: Color.brandDeep.opacity(0.18), radius: 0.5, y: 1)
            .shadow(color: Color.brand.opacity(0.30), radius: 9, y: 8)
    }

    /// White tiles on the page background.
    func tileShadow() -> some View {
        shadow(color: Color.brand.opacity(0.05), radius: 1, y: 1)
            .shadow(color: Color.brand.opacity(0.09), radius: 16, y: 8)
    }

}

extension ShapeStyle where Self == AnyShapeStyle {
    /// The recessed fill of inputs and pressed chips.
    static func recessed(_ color: Color, opacity: Double = 0.09) -> AnyShapeStyle {
        AnyShapeStyle(color.shadow(.inner(color: .ink.opacity(opacity), radius: 1, y: 1)))
    }
}
