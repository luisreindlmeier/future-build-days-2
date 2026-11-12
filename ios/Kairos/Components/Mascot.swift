import SwiftUI

/// The coach: three stones with a face. It breathes, floats, blinks and hops, so it reads as alive.
struct Mascot: View {
    enum Motion { case still, idle, looking }

    var mood: Mood = .idle
    var size: CGFloat = 120
    var motion: Motion = .idle
    /// Pops in when it appears, after this many seconds.
    var enters: Double?
    /// Hops whenever this changes.
    var beat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hops = 0
    @State private var strength = 1.0
    @State private var taps = 0
    @State private var blinking = false
    @State private var winking = false
    @State private var arrived = false
    @State private var phase = Double.random(in: 0..<20)

    private struct Hop {
        var lift = 0.0
        var stretch = 1.0
        var tilt = 0.0
    }

    private var alive: Bool { motion != .still && !reduceMotion }
    private var shown: Bool { enters == nil || arrived }

    private var pose: String {
        if winking { return Mood.wink.rawValue }
        if blinking, mood != .happy, mood != .wink { return Mood.happy.rawValue }
        return mood.rawValue
    }

    var body: some View {
        KeyframeAnimator(initialValue: Hop(), trigger: hops) { hop in
            TimelineView(.animation(paused: !alive)) { timeline in
                figure(hop, at: alive ? timeline.date.timeIntervalSinceReferenceDate + phase : nil)
            }
        } keyframes: { _ in
            KeyframeTrack(\.stretch) {
                CubicKeyframe(1 - 0.12 * strength, duration: 0.10)
                CubicKeyframe(1 + 0.08 * strength, duration: 0.14)
                CubicKeyframe(1, duration: 0.14)
                CubicKeyframe(1 + 0.05 * strength, duration: 0.12)
                CubicKeyframe(1 - 0.10 * strength, duration: 0.08)
                CubicKeyframe(1 + 0.03 * strength, duration: 0.10)
                CubicKeyframe(1, duration: 0.12)
            }
            KeyframeTrack(\.lift) {
                CubicKeyframe(0, duration: 0.10)
                CubicKeyframe(strength, duration: 0.20)
                CubicKeyframe(0, duration: 0.20)
                CubicKeyframe(0.1 * strength, duration: 0.09)
                CubicKeyframe(0, duration: 0.09)
            }
            KeyframeTrack(\.tilt) {
                CubicKeyframe(0, duration: 0.10)
                CubicKeyframe(-4 * strength, duration: 0.20)
                CubicKeyframe(3 * strength, duration: 0.20)
                CubicKeyframe(0, duration: 0.18)
            }
        }
        .scaleEffect(shown ? 1 : 0.35, anchor: .bottom)
        .opacity(shown ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard motion != .still, size >= 90 else { return }
            taps += 1
            hop()
            Task {
                winking = true
                try? await Task.sleep(for: .milliseconds(650))
                winking = false
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .onChange(of: mood) { hop(0.45) }
        .onChange(of: beat) { hop(0.6) }
        .task {
            guard let enters, !arrived else { return }
            guard !reduceMotion else { arrived = true; return }
            try? await Task.sleep(for: .milliseconds(Int(enters * 1000)))
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { arrived = true }
            try? await Task.sleep(for: .milliseconds(420))
            hop(0.7)
        }
        .task(id: alive) {
            guard alive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 2400...5200)))
                for _ in 0..<(Int.random(in: 0..<4) == 0 ? 2 : 1) {
                    blinking = true
                    try? await Task.sleep(for: .milliseconds(130))
                    blinking = false
                    try? await Task.sleep(for: .milliseconds(140))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func hop(_ amount: Double = 1) {
        guard !reduceMotion, motion != .still || enters != nil else { return }
        strength = amount
        hops += 1
    }

    /// The figure on its ground shadow. The shadow stays on the ground and shrinks as the figure lifts.
    private func figure(_ hop: Hop, at time: Double?) -> some View {
        var lift = hop.lift, stretch = hop.stretch, tilt = hop.tilt, shift = 0.0
        if let time {
            lift += 0.07 * (1 + sin(time * 2 * .pi / 3.3))
            stretch *= 1 + 0.016 * sin(time * 2 * .pi / 2.7 + 0.8)
            tilt += 1.2 * sin(time * 2 * .pi / 4.6)
            if motion == .looking {
                tilt += 5 * sin(time * 2 * .pi / 1.9)
                shift = 0.035 * sin(time * 2 * .pi / 1.9)
            }
        }
        let height = size * 774 / 876
        return ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.brandDeep.opacity(0.22 - 0.1 * min(lift, 1)))
                .frame(width: size * 0.7 * (1 - 0.25 * min(lift, 1)), height: size * 0.09)
                .blur(radius: size * 0.04)
                .offset(y: size * 0.035)
            Image("mascot-\(pose)")
                .resizable()
                .frame(width: size, height: height)
                .scaleEffect(x: 1 / stretch.squareRoot(), y: stretch, anchor: .bottom)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .offset(x: shift * size, y: -lift * size * 0.2)
        }
        .frame(width: size, height: height)
    }
}

/// What the coach says, beside its face.
struct CoachLine: View {
    let text: String
    var mood: Mood = .smile
    var size: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Mascot(mood: mood, size: size, enters: 0.1)
            Text(text)
                .appFont(16, lineHeight: 1.4)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Facts in two columns: what was looked at, and its value.
struct FactList: View {
    let facts: [Fact]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(fact.label)
                        .appFont(15, relativeTo: .subheadline)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(fact.value)
                        .appFont(15, .medium, relativeTo: .subheadline)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 11)
                if index < facts.count - 1 { Hairline() }
            }
        }
    }
}

/// Labelled bars for an explainer: one of them can be the point.
struct BarList: View {
    let bars: [Bar]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let most = max(bars.map(\.value).max() ?? 1, 0.0001)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(bars) { bar in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(bar.label)
                            .appFont(14, relativeTo: .subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer(minLength: 8)
                        Text(bar.text)
                            .appFont(14, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(Color.ink)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.track)
                            Capsule()
                                .fill(bar.highlighted ? Color.brand : Color.brandLight)
                                .frame(width: max(4, proxy.size.width * (grown ? bar.value / most : 0)))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .onAppear {
            if reduceMotion { grown = true } else { withAnimation(.easeOut(duration: 0.7).delay(0.15)) { grown = true } }
        }
    }
}
