import SwiftUI

/// A native sheet as tall as its content: the detent follows the content's measured height, and once the content is
/// taller than the screen the sheet scrolls. For the example sentences, the widget steps and the export.
struct FittedSheet<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 300

    var body: some View {
        ScrollView {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }
}
