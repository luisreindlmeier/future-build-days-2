import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// The page: almost white, with a breath of blue. `Backdrop` lays the blue wash over it.
    static let appBackground = Color(hex: 0xF7F8FD)
    static let surface = Color(hex: 0xFFFFFF)
    /// Text and icons: the navy, deep enough to read as ink.
    static let ink = Color(hex: 0x12143A)
    static let textSecondary = Color(hex: 0x3A3D62)
    static let textMuted = Color(hex: 0x6B6F90)
    static let divider = Color(hex: 0xE5E8F3)
    static let track = Color(hex: 0xE2E6F5)
    static let well = Color(hex: 0xECEFF9)
    static let pressed = Color(hex: 0xE2E6F5)

    /// The main colour: a deep navy. The primary button, the score block.
    static let brand = Color(hex: 0x16184B)
    static let brandSoft = Color(hex: 0x2A2F86)
    static let brandDeep = Color(hex: 0x0E1035)
    /// A tint of the navy for labels and coach cards on the page.
    static let brandTint = Color(hex: 0xE6EAFA)
    /// The blue of the drawings, for bars that belong to them.
    static let brandLight = Color(hex: 0x9FB0F0)
    /// The lively blue: the selected tab, links, progress, sliders.
    static let accent = Color(hex: 0x2A41D0)
    static let onBrandMuted = Color.white.opacity(0.7)

    /// The colour between this one and another, in sRGB.
    func mixed(with other: Color, by amount: Double) -> Color {
        mix(with: other, by: amount, in: .device)
    }
}

extension EnvironmentValues {
    @Entry var inkColor: Color = .ink
}
