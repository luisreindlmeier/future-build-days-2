import SwiftUI
import UIKit

/// The wealth tree, drawn in space from the backend's `TreeState` and seen from the front corner. Tap a part to
/// choose it, drag sideways to turn the crown. It turns slowly by itself until it is touched.
struct TreeCanvas: View {
    let tree: TreeState
    @Binding var selected: TreePart?
    /// Degrees the tree leans to the right: the storm test.
    var lean: Double = 0
    /// Overrides the weather of the tree, for the storm test.
    var weather: String?
    var interactive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keeper = SceneKeeper()
    @State private var turn = 0.35
    @State private var turningSince: Date? = Date()
    @State private var grabbed: Double?
    @State private var size = CGSize.zero

    /// The direction the viewer looks from, as an angle around the trunk.
    private static let front = 1.25 * Double.pi

    init(tree: TreeState, selected: Binding<TreePart?> = .constant(nil), lean: Double = 0, weather: String? = nil, interactive: Bool = true) {
        self.tree = tree
        _selected = selected
        self.lean = lean
        self.weather = weather
        self.interactive = interactive
    }

    private var sky: String { weather ?? tree.weather.type }

    var body: some View {
        let scene = keeper.scene(for: tree, weather: sky)
        ZStack {
            Ground(scene: scene, selected: selected)
                .equatable()
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                Standing(scene: scene, selected: selected, turn: turned(at: timeline.date), lean: lean + sway(at: timeline.date),
                         time: reduceMotion ? nil : timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap(at: $0.location) })
        .gesture(TurnGesture(began: { hold(); grabbed = turn }, moved: { turn = (grabbed ?? turn) + $0 * 0.012 }))
        .allowsHitTesting(interactive)
        .onChange(of: selected) { face(selected) }
        .accessibilityElement()
        .accessibilityLabel(Text("Your wealth tree. \(tree.headline)"))
    }

    private func turned(at date: Date) -> Double {
        guard let turningSince, !reduceMotion else { return turn }
        return turn + date.timeIntervalSince(turningSince) * 0.09
    }

    /// The wind in the crown, in degrees: more of it in rougher weather.
    private func sway(at date: Date) -> Double {
        guard !reduceMotion else { return 0 }
        let gust = switch sky {
        case "BREEZY": 0.7
        case "WINDY": 1.4
        case "STORM": 2.4
        default: 0.3
        }
        let time = date.timeIntervalSinceReferenceDate
        return gust * (0.6 * sin(time * 1.3) + 0.4 * sin(time * 2.9 + 1))
    }

    /// Ends the slow turning where it is.
    private func hold() {
        turn = turned(at: Date())
        turningSince = nil
    }

    private func tap(at point: CGPoint) {
        hold()
        let scene = keeper.scene(for: tree, weather: sky)
        let part = scene.part(at: point, size: size, pose: Pose(turn: Float(turn), lean: Float(lean * .pi / 180)))
        withAnimation(.easeOut(duration: 0.15)) { selected = part == selected ? nil : part }
    }

    /// Turns the crown so that the chosen bough faces the viewer.
    private func face(_ part: TreePart?) {
        guard case let .leaf(id) = part, let angle = keeper.scene(for: tree, weather: sky).boughAngles[id] else { return }
        hold()
        var target = Self.front - Double(angle)
        while target - turn > .pi { target -= 2 * .pi }
        while target - turn < -.pi { target += 2 * .pi }
        if reduceMotion {
            turn = target
        } else {
            withAnimation(.spring(duration: 0.8, bounce: 0.15)) { turn = target }
        }
    }
}

/// Builds the scene once per tree and weather, not on every frame.
private final class SceneKeeper {
    private var tree: TreeState?
    private var weather = ""
    private var scene = Scene3D()

    func scene(for tree: TreeState, weather: String) -> Scene3D {
        if tree != self.tree || weather != self.weather {
            scene = TreeModel.scene(for: tree, weather: weather)
            self.tree = tree
            self.weather = weather
        }
        return scene
    }
}

/// What stands still: the clouds, the block of soil with its roots, and the shadows on the grass.
private struct Ground: View, Equatable {
    let scene: Scene3D
    let selected: TreePart?

    static func == (left: Ground, right: Ground) -> Bool {
        left.scene.id == right.scene.id && left.selected == right.selected
    }

    var body: some View {
        Canvas { context, size in
            let camera = Camera(size: size)
            let under = camera.project(Vec(-1, -1, -1.0))
            let reach = CGFloat(camera.scale)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: reach * 0.07))
                layer.fill(Path(ellipseIn: CGRect(x: CGFloat(under.x) - reach * 0.9, y: CGFloat(under.y) - reach * 0.02, width: reach * 1.8, height: reach * 0.17)), with: .color(Color.brand.opacity(0.2)))
            }
            scene.draw(&context, size: size, layers: 0...3, pose: Pose(), selected: selected)
        }
    }
}

/// What moves: the trunk, the crown and everything else that stands on the grass.
private struct Standing: View, Animatable {
    let scene: Scene3D
    let selected: TreePart?
    var turn: Double
    var lean: Double
    var time: Double?

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(turn, lean) }
        set {
            turn = newValue.first
            lean = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            scene.draw(&context, size: size, layers: Scene3D.standing...Scene3D.standing, pose: Pose(turn: Float(turn), lean: Float(lean * .pi / 180), time: time), selected: selected)
        }
    }
}

/// A sideways drag. A drag that starts up or down is left to the page, so the tree does not block scrolling.
private struct TurnGesture: UIGestureRecognizerRepresentable {
    let began: () -> Void
    let moved: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began: began()
        case .changed: moved(recognizer.translation(in: recognizer.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let speed = pan.velocity(in: pan.view)
            return abs(speed.x) > abs(speed.y)
        }
    }
}
