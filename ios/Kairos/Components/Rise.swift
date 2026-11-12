import SwiftUI

/// Content that fades in and rises a little when it appears, after a delay, so a screen builds up in order.
private struct Rise: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.easeOut(duration: 0.45).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    func rises(after delay: Double) -> some View {
        modifier(Rise(delay: delay))
    }
}
