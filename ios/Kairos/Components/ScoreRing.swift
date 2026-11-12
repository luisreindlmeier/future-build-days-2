import SwiftUI

/// A ring that fills to a score of 100 in the blue the score has on the spectrum, running from a lighter tone
/// into it, with the number in its middle and, on large rings, a caption under the number.
struct ScoreRing: View {
    let score: Int?
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7
    var onBrand = false
    var caption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var body: some View {
        let health = Health(score: score)
        let tone = onBrand ? health.colorOnBrand : health.color
        let from = onBrand ? tone.mixed(with: .brand, by: 0.3) : tone.mixed(with: .white, by: 0.5)
        ZStack {
            Circle().stroke(onBrand ? Color.white.opacity(0.13) : Color.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown / 100)
                .stroke(
                    AngularGradient(colors: [from, tone], center: .center, startAngle: .zero, endAngle: .degrees(max(shown, 1) * 3.6)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: size * 0.02) {
                if let score {
                    Text("\(score)")
                        .font(.system(size: size * (caption == nil ? 0.36 : 0.32), weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(onBrand ? Color.white : Color.ink)
                        .contentTransition(.numericText())
                } else {
                    Icon("circle", size: size * 0.2)
                        .opacity(0.4)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: size * 0.09, weight: .medium))
                        .foregroundStyle(onBrand ? Color.onBrandMuted : Color.textMuted)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { animate(to: Double(score ?? 0)) }
        .onChange(of: score) { animate(to: Double(score ?? 0)) }
        .accessibilityElement()
        .accessibilityLabel(score.map { Text("\($0) of 100") } ?? Text("Not measured yet"))
    }

    private func animate(to value: Double) {
        if reduceMotion {
            shown = value
        } else {
            withAnimation(.easeOut(duration: 0.9)) { shown = value }
        }
    }
}

/// A number that counts up to its value when it appears.
struct CountUp: View {
    let value: Int
    var font: Font
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        Text("\(shown)")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .task(id: value) {
                guard !reduceMotion else { shown = value; return }
                let start = shown, steps = 24
                for step in 1...steps {
                    try? await Task.sleep(for: .milliseconds(28))
                    withAnimation(.easeOut(duration: 0.1)) {
                        shown = start + (value - start) * step / steps
                    }
                }
                shown = value
            }
    }
}
