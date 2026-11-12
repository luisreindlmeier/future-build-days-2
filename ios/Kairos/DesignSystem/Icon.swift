import SwiftUI

/// A Lucide icon from the asset catalog, drawn in ink, never on a background.
struct Icon: View {
    let name: String
    let size: CGFloat
    @Environment(\.inkColor) private var ink

    init(_ name: String, size: CGFloat = 22) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("lucide-\(name)")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(ink)
            .accessibilityHidden(true)
    }
}
