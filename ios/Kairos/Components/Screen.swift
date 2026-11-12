import SwiftUI

/// The page behind every screen: the light background with a blue wash that falls in from the top right.
struct Backdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.appBackground
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xDCE3FA), location: 0),
                        .init(color: Color(hex: 0xE9EDFB), location: 0.45),
                        .init(color: Color.appBackground.opacity(0), location: 1),
                    ],
                    startPoint: .topTrailing,
                    endPoint: UnitPoint(x: 0.2, y: 0.62)
                )
                .frame(height: size.height * 0.62)
                .frame(maxHeight: .infinity, alignment: .top)
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.3, y: 0))
                    path.addLine(to: CGPoint(x: size.width, y: 0))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * 0.34))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// The app background behind every screen.
    func screenBackground() -> some View {
        background { Backdrop() }
    }
}
