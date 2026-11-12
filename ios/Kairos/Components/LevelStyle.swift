import SwiftUI

/// One spectrum for everything that is rated: three blues, light to deep, as the backend's tree has three states.
enum Health: Int, Comparable, Sendable {
    case missing, needsCare, growing, strong

    static func < (left: Health, right: Health) -> Bool { left.rawValue < right.rawValue }

    /// A score of 100, with the backend's own steps (`PartStatus.of`): 75 and up is strong, 40 and up growing.
    init(score: Int?) {
        guard let score else { self = .missing; return }
        self = score >= 75 ? .strong : score >= 40 ? .growing : .needsCare
    }

    /// A part status or a habit's health, as the backend names them.
    init(status: String) {
        switch status {
        case "STRONG", "HEALTHY": self = .strong
        case "GROWING", "WILTING": self = .growing
        case "NEEDS_CARE", "ROTTEN": self = .needsCare
        default: self = .missing
        }
    }

    /// A value the backend normalised to 0...1 for drawing.
    init(share: Double) {
        self.init(score: Int((share * 100).rounded()))
    }

    /// On the page the better state is the deeper blue.
    var color: Color {
        switch self {
        case .strong: Color(hex: 0x1423A0)
        case .growing: Color(hex: 0x3D5AE6)
        case .needsCare: Color(hex: 0x8FA6F6)
        case .missing: Color(hex: 0xCDD3E8)
        }
    }

    /// On the navy the better state is the brighter blue.
    var colorOnBrand: Color {
        switch self {
        case .strong: Color(hex: 0xF1F4FF)
        case .growing: Color(hex: 0xB9C7FF)
        case .needsCare: Color(hex: 0x8497F7)
        case .missing: Color.white.opacity(0.25)
        }
    }

    /// The fill of a label with this state's word.
    var tint: Color {
        switch self {
        case .strong: Color(hex: 0xBFCAF8)
        case .growing: Color(hex: 0xD8DFFB)
        case .needsCare: Color(hex: 0xEAEEFC)
        case .missing: Color.well
        }
    }

    var title: String {
        switch self {
        case .strong: "Strong"
        case .growing: "Growing"
        case .needsCare: "Needs care"
        case .missing: "Not set up"
        }
    }
}

/// A word on the tint of its state.
struct HealthChip: View {
    let health: Health
    var text: String?
    var compact = false

    var body: some View {
        Text(text ?? health.title)
            .appFont(compact ? 12 : 13, .medium, relativeTo: .footnote)
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(health.tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Three steps, filled up to the state. Each step has its own blue, so a full bar shows the whole spectrum.
struct HealthBar: View {
    let health: Health
    var segment = CGSize(width: 18, height: 5)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(step <= health.rawValue ? (Health(rawValue: step) ?? health).color : Color.track)
                    .frame(width: segment.width, height: segment.height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A short label on a tint of the navy: what an action is worth.
struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .appFont(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(Color.accent)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.brandTint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
