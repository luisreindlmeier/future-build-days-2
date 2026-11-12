import SwiftUI

struct Grain: View {
    var body: some View {
        ZStack {
            Image("grain-coarse").resizable(resizingMode: .tile).opacity(0.5)
            Image("grain-fine").resizable(resizingMode: .tile)
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The one coloured surface: navy with the grain and a blue light from the top right. The primary button and the score block.
struct BrandSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .brandSoft, location: 0),
                    .init(color: .brand, location: 0.5),
                    .init(color: .brandDeep, location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GeometryReader { proxy in
                let reach = max(proxy.size.width, proxy.size.height)
                RadialGradient(colors: [Color.white.opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: reach * 0.7)
                RadialGradient(colors: [Color.accent.opacity(0.5), .clear], center: .topTrailing, startRadius: 0, endRadius: reach * 0.75)
            }
            Grain().opacity(0.55)
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Text on the navy surface.
    func onBrand() -> some View {
        foregroundStyle(Color.white)
    }

    /// A block on the navy surface with the hero corners.
    func brandBlock(padding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                BrandSurface().clipShape(RoundedRectangle(cornerRadius: Radius.heroBlock, style: .continuous))
            }
    }
}
