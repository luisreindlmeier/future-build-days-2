import simd
import SwiftUI

typealias Vec = SIMD3<Float>

/// Three colours from shade to light. A face takes its place between them by how much light falls on it.
struct Ramp {
    let dark: Vec
    let mid: Vec
    let light: Vec

    init(_ dark: UInt32, _ mid: UInt32, _ light: UInt32) {
        self.dark = Ramp.rgb(dark)
        self.mid = Ramp.rgb(mid)
        self.light = Ramp.rgb(light)
    }

    func at(_ shade: Float) -> Vec {
        shade < 0.5 ? simd_mix(dark, mid, Vec(repeating: shade * 2)) : simd_mix(mid, light, Vec(repeating: (shade - 0.5) * 2))
    }

    private static func rgb(_ hex: UInt32) -> Vec {
        Vec(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }
}

/// What the tree is made of. Leaves, bark and soil follow the web dashboard's tree (`projects-section/js/tree3d.js`).
enum Material: Int, CaseIterable {
    case leafHealthy, leafWilting, leafRotten, canopy, fresh
    case bark, groove, root, rootWeak
    case grass, blade, turf
    case topsoil, soilA, soilB, soilC, soilDeep, rock, pebble, stone
    case fruit, blossom, pollen, petalCream, petalPink, petalBlue, petalPeach
    case cloud, stormCloud, white

    var ramp: Ramp {
        switch self {
        case .leafHealthy: Ramp(0x1C6B3C, 0x3CA552, 0x93DC6E)
        case .leafWilting: Ramp(0x8C6A14, 0xD6A626, 0xF7DC6A)
        case .leafRotten: Ramp(0x6E2C14, 0xB7572B, 0xE5935C)
        case .canopy: Ramp(0x154D2E, 0x2A7A40, 0x58B158)
        case .fresh: Ramp(0x3DA85E, 0x74D07C, 0xC2F0B4)
        case .bark: Ramp(0x4A2E1B, 0x7C502D, 0xAE7A47)
        case .groove: Ramp(0x24150B, 0x351F11, 0x4A2E1B)
        case .root: Ramp(0x9A7146, 0xCDA571, 0xF0D7AB)
        case .rootWeak: Ramp(0x75624E, 0xA38D75, 0xC8B8A2)
        case .grass: Ramp(0x58A043, 0x86C65A, 0xBCE583)
        case .blade: Ramp(0x3F8A3A, 0x62B04E, 0x9EDB76)
        case .turf: Ramp(0x478F38, 0x6FB34C, 0x9AD268)
        case .topsoil: Ramp(0x40281A, 0x5E3C24, 0x7C5232)
        case .soilA: Ramp(0x6F4A2B, 0x94663B, 0xB5834F)
        case .soilB: Ramp(0x815A33, 0xA97848, 0xC9965F)
        case .soilC: Ramp(0x644226, 0x865C36, 0xA47648)
        case .soilDeep: Ramp(0x55381F, 0x754F2E, 0x92683F)
        case .rock: Ramp(0x5A5566, 0x878296, 0xB4AFC2)
        case .pebble: Ramp(0xA08C6C, 0xD2BC96, 0xEBDDBF)
        case .stone: Ramp(0x77738A, 0xA5A1B6, 0xD3D0DE)
        case .fruit: Ramp(0x8F2A1E, 0xC8402E, 0xEC7A66)
        case .blossom: Ramp(0xD999B2, 0xF2BFD0, 0xFFE9F0)
        case .pollen: Ramp(0xC99A2A, 0xF0B429, 0xF6E39A)
        case .petalCream: Ramp(0xE6D98C, 0xFFF1A8, 0xFFFBE0)
        case .petalPink: Ramp(0xDFA3B7, 0xF6C9D8, 0xFFE9F0)
        case .petalBlue: Ramp(0xA3B0EE, 0xC9D3FF, 0xECF0FF)
        case .petalPeach: Ramp(0xE6B08A, 0xFFD2B0, 0xFFEBDC)
        case .cloud: Ramp(0xC3CDE8, 0xE9EEFA, 0xFFFFFF)
        case .stormCloud: Ramp(0x4C5270, 0x767D9A, 0xA4AAC2)
        case .white: Ramp(0xFFFFFF, 0xFFFFFF, 0xFFFFFF)
        }
    }
}

/// Every material at every step of light, resolved once. `dimmed` is the same, stepped back towards the sky.
enum Palette {
    static let steps = 24
    static let colors = build(fade: 0)
    static let dimmed = build(fade: 0.4)

    static func index(_ material: Material, shade: Float) -> Int {
        material.rawValue * steps + min(steps - 1, max(0, Int(shade * Float(steps))))
    }

    private static func build(fade: Float) -> [Color] {
        let sky = Vec(0.91, 0.93, 0.99)
        return Material.allCases.flatMap { material -> [Color] in
            let ramp = material.ramp
            return (0..<steps).map { step in
                let color = simd_mix(ramp.at((Float(step) + 0.5) / Float(steps)), sky, Vec(repeating: fade))
                return Color(.sRGB, red: Double(color.x), green: Double(color.y), blue: Double(color.z))
            }
        }
    }
}

/// A numbered source of chance, so the tree looks the same on every redraw and for every viewer.
struct Chance {
    private var state: UInt64

    init(_ seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678_9ABC_DEF1
    }

    /// 0 up to 1.
    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float((state >> 40) & 0xFFFFFF) / Float(0x1000000)
    }

    /// -1 up to 1.
    mutating func signed() -> Float { next() * 2 - 1 }

    mutating func between(_ low: Float, _ high: Float) -> Float { low + (high - low) * next() }
}

struct Face {
    var a: Int32
    var b: Int32
    var c: Int32
    /// Below zero for a triangle.
    var d: Int32
    var normal: Vec
    var material: Material
    /// Added to the light on the face: its own variation and how hidden it sits.
    var tone: Float
}

/// How a mesh follows the tree: not at all, leaning with it in the wind, or also turning around the trunk.
enum Motion {
    case fixed, lean, turn
}

struct Mesh {
    var points: [Vec] = []
    var faces: [Face] = []
    var layer: Int
    var motion: Motion = .fixed
    var part: TreePart?
    /// Thin things, seen from both sides.
    var twoSided = false

    mutating func triangle(_ a: Vec, _ b: Vec, _ c: Vec, facing: Vec? = nil, _ material: Material, tone: Float = 0) {
        var normal = simd_normalize(simd_cross(b - a, c - a))
        if let facing, simd_dot(normal, facing) < 0 { normal = -normal }
        let start = Int32(points.count)
        points.append(contentsOf: [a, b, c])
        faces.append(Face(a: start, b: start + 1, c: start + 2, d: -1, normal: normal, material: material, tone: tone))
    }

    mutating func quad(_ a: Vec, _ b: Vec, _ c: Vec, _ d: Vec, facing: Vec? = nil, _ material: Material, tone: Float = 0) {
        var normal = simd_normalize(simd_cross(c - a, d - b))
        if let facing, simd_dot(normal, facing) < 0 { normal = -normal }
        let start = Int32(points.count)
        points.append(contentsOf: [a, b, c, d])
        faces.append(Face(a: start, b: start + 1, c: start + 2, d: start + 3, normal: normal, material: material, tone: tone))
    }
}

/// A round mark that always faces the viewer: a petal, a pebble's glint, the tip of a root.
struct Dot {
    var center: Vec
    /// In the tree's own measure, or in points when `fixedSize` is set.
    var radius: Float
    var fixedSize = false
    var material: Material
    var shade: Float = 0.6
    var alpha: Float = 1
    var ring = false
    var layer: Int
    var motion: Motion = .fixed
    var part: TreePart?
    /// Pulls the mark towards the viewer in the drawing order.
    var forward: Float = 0
}

/// A round lump: a clump of leaves, a stone, a fruit, a cloud. It is painted as a shaded ball, light from the top left.
struct Ball {
    var center: Vec
    var radius: Float
    /// How flat it is: 1 is a sphere.
    var squash: Float = 0.9
    var material: Material
    var tone: Float = 0
    var layer: Int
    var motion: Motion = .fixed
    var part: TreePart?
}

/// A flat, see-through shape on the ground: a shadow.
struct Decal {
    var outline: [Vec]
    var color: Color
    var layer: Int
}

/// A leaf that drifts from a thinning bough to the ground.
struct FallingLeaf {
    var origin: Vec
    var phase: Float
    var part: TreePart?
}

/// A point to aim a tap at, for the parts too thin to hit.
struct Anchor {
    var point: Vec
    var motion: Motion
    var part: TreePart
}

/// The viewer: straight from the front corner, looking down at 30 degrees, without perspective.
struct Camera {
    static let view = Vec(0.61237, 0.61237, -0.5)
    static let right = Vec(0.70711, -0.70711, 0)
    static let up = Vec(0.35355, 0.35355, 0.86603)
    /// The picture is this many of the tree's units wide and high; the block is 2 by 2.
    static let frame = CGSize(width: 3.0, height: 3.9)
    static let horizon: CGFloat = 2.3

    let scale: Float
    let centerX: Float
    let centerY: Float

    init(size: CGSize) {
        let fit = min(size.width / Camera.frame.width, size.height / Camera.frame.height)
        scale = Float(fit)
        centerX = Float(size.width / 2)
        centerY = Float((size.height - Camera.frame.height * fit) / 2 + Camera.horizon * fit)
    }

    /// Where a point lands: x and y on the page, and how far it is from the viewer.
    func project(_ point: Vec) -> Vec {
        let across = (point.x - point.y) * 0.70711, away = (point.x + point.y) * 0.70711
        return Vec(centerX + across * scale, centerY - (point.z * 0.86603 + away * 0.5) * scale, away * 0.86603 - point.z * 0.5)
    }
}

/// How the tree stands right now.
struct Pose {
    /// Radians the crown has turned around the trunk.
    var turn: Float = 0
    /// Radians the tree leans to the right.
    var lean: Float = 0
    /// Seconds, for what moves by itself. Without it nothing does.
    var time: Double?
}

/// One thing to paint: a face or a round mark, already placed on the page.
struct Stroke {
    var a = CGPoint.zero
    var b = CGPoint.zero
    var c = CGPoint.zero
    var d = CGPoint.zero
    /// 3 or 4 corners, or 0 for a round mark or a ball with `radius` around `a`.
    var corners = 3
    var radius: CGFloat = 0
    /// A ball: its height on the page, and its colours in the light and in the shade.
    var ball = false
    var radiusY: CGFloat = 0
    var light = 0
    var dark = 0
    var color = 0
    var alpha: Float = 1
    var ring = false
    /// A single leaf or a blade of grass: too small to carry the rim of a chosen part.
    var slight = false
    var depth: Float = 0
    var part = -1
}

/// A tree as faces in space. Built once for a tree, then drawn for any pose.
struct Scene3D {
    let id = UUID()
    static let light = simd_normalize(Vec(-0.52, 0.06, 0.85))
    /// Layers are painted in this order: clouds, the block, what lies on its sides, shadows on the grass,
    /// everything that stands on it. The last layer and the clouds are sorted by distance.
    static let layers = 0...4
    static let standing = 4

    var meshes: [Mesh] = []
    var balls: [Ball] = []
    var dots: [Dot] = []
    var decals: [Decal] = []
    var falling: [FallingLeaf] = []
    var anchors: [Anchor] = []
    var parts: [TreePart] = []
    /// The foot of the trunk: what leans and turns does so around it.
    var foot = Vec.zero
    /// Where each bough of leaves sits around the trunk, in radians.
    var boughAngles: [String: Float] = [:]

    mutating func index(of part: TreePart?) -> Int {
        guard let part else { return -1 }
        if let index = parts.firstIndex(of: part) { return index }
        parts.append(part)
        return parts.count - 1
    }

    private func turning(_ pose: Pose, _ motion: Motion) -> simd_float3x3? {
        guard motion != .fixed else { return nil }
        let lean = simd_float3x3(simd_quatf(angle: pose.lean, axis: simd_normalize(Vec(1, 1, 0))))
        guard motion == .turn else { return pose.lean == 0 ? nil : lean }
        return lean * simd_float3x3(simd_quatf(angle: pose.turn, axis: Vec(0, 0, 1)))
    }

    private func place(_ point: Vec, _ rotation: simd_float3x3?) -> Vec {
        guard let rotation else { return point }
        return rotation * (point - foot) + foot
    }

    /// Everything of the given layers, placed on the page, in the order to paint it.
    func strokes(layers: ClosedRange<Int>, pose: Pose, camera: Camera) -> [Stroke] {
        var out: [Stroke] = []
        out.reserveCapacity(4096)
        var placed: [Vec] = []
        for layer in layers {
            let first = out.count
            for mesh in meshes where mesh.layer == layer {
                let rotation = turning(pose, mesh.motion)
                let part = mesh.part.flatMap { parts.firstIndex(of: $0) } ?? -1
                placed.removeAll(keepingCapacity: true)
                for point in mesh.points { placed.append(camera.project(place(point, rotation))) }
                for face in mesh.faces {
                    var normal = rotation.map { $0 * face.normal } ?? face.normal
                    if simd_dot(normal, Camera.view) >= 0 {
                        guard mesh.twoSided else { continue }
                        normal = -normal
                    }
                    let shade = 0.24 + 0.6 * max(0, simd_dot(normal, Scene3D.light)) + 0.16 * (normal.z * 0.5 + 0.5) + face.tone
                    let a = placed[Int(face.a)], b = placed[Int(face.b)], c = placed[Int(face.c)]
                    var stroke = Stroke(a: CGPoint(x: CGFloat(a.x), y: CGFloat(a.y)), b: CGPoint(x: CGFloat(b.x), y: CGFloat(b.y)), c: CGPoint(x: CGFloat(c.x), y: CGFloat(c.y)))
                    stroke.color = Palette.index(face.material, shade: shade)
                    stroke.part = part
                    stroke.slight = mesh.twoSided
                    if face.d >= 0 {
                        let d = placed[Int(face.d)]
                        stroke.d = CGPoint(x: CGFloat(d.x), y: CGFloat(d.y))
                        stroke.corners = 4
                        stroke.depth = (a.z + b.z + c.z + d.z) / 4
                    } else {
                        stroke.depth = (a.z + b.z + c.z) / 3
                    }
                    out.append(stroke)
                }
            }
            for ball in balls where ball.layer == layer {
                let center = camera.project(place(ball.center, turning(pose, ball.motion)))
                var stroke = Stroke(a: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)))
                stroke.corners = 0
                stroke.ball = true
                stroke.radius = CGFloat(ball.radius * camera.scale)
                stroke.radiusY = stroke.radius * CGFloat((ball.squash * ball.squash * 0.75 + 0.25).squareRoot())
                stroke.color = Palette.index(ball.material, shade: 0.52 + ball.tone)
                stroke.light = Palette.index(ball.material, shade: 0.96 + ball.tone)
                stroke.dark = Palette.index(ball.material, shade: 0.1 + ball.tone)
                stroke.depth = center.z - 0.12
                stroke.part = ball.part.flatMap { parts.firstIndex(of: $0) } ?? -1
                out.append(stroke)
            }
            for dot in dots where dot.layer == layer {
                let center = camera.project(place(dot.center, turning(pose, dot.motion)))
                var stroke = Stroke(a: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)))
                stroke.corners = 0
                stroke.radius = CGFloat(dot.fixedSize ? dot.radius : dot.radius * camera.scale)
                stroke.color = Palette.index(dot.material, shade: dot.shade)
                stroke.alpha = dot.alpha
                stroke.ring = dot.ring
                stroke.depth = center.z - dot.forward
                stroke.part = dot.part.flatMap { parts.firstIndex(of: $0) } ?? -1
                out.append(stroke)
            }
            if layer == Scene3D.standing, let time = pose.time {
                drift(at: time, pose: pose, camera: camera, into: &out)
            }
            if layer == Scene3D.standing || layer == 0 {
                out[first...].sort { $0.depth > $1.depth }
            }
        }
        return out
    }

    /// The leaves on their way down, where they are at this moment.
    private func drift(at time: Double, pose: Pose, camera: Camera, into out: inout [Stroke]) {
        let rotation = turning(pose, .turn)
        for leaf in falling {
            let cycle = Float((time * 0.16 + Double(leaf.phase)).truncatingRemainder(dividingBy: 1))
            let start = place(leaf.origin, rotation)
            let sway = Vec(sin(cycle * 9 + leaf.phase * 20) * 0.07, cos(cycle * 7 + leaf.phase * 11) * 0.05, 0)
            let center = Vec(start.x, start.y, 0.03 + (start.z - 0.03) * (1 - cycle)) + sway
            let spin = cycle * 14 + leaf.phase * 30
            let long = (Camera.right * cos(spin) + Camera.up * sin(spin)) * 0.04
            let short = (Camera.up * cos(spin) - Camera.right * sin(spin)) * 0.018
            let corners = [center - long, center + short, center + long, center - short].map(camera.project)
            var stroke = Stroke(
                a: CGPoint(x: CGFloat(corners[0].x), y: CGFloat(corners[0].y)), b: CGPoint(x: CGFloat(corners[1].x), y: CGFloat(corners[1].y)),
                c: CGPoint(x: CGFloat(corners[2].x), y: CGFloat(corners[2].y)), d: CGPoint(x: CGFloat(corners[3].x), y: CGFloat(corners[3].y))
            )
            stroke.corners = 4
            stroke.color = Palette.index(.leafRotten, shade: 0.55 + 0.35 * sin(spin))
            stroke.alpha = min(1, sin(cycle * .pi) * 2.2)
            stroke.depth = corners[0].z
            out.append(stroke)
        }
    }

    /// Paints the layers. The chosen part gets a blue rim, and everything else steps back a little.
    func draw(_ context: inout GraphicsContext, size: CGSize, layers: ClosedRange<Int>, pose: Pose, selected: TreePart?) {
        let camera = Camera(size: size)
        let chosen = selected.flatMap { parts.firstIndex(of: $0) } ?? -1
        var rimmed = chosen < 0
        for layer in layers {
            for decal in decals where decal.layer == layer {
                var path = Path()
                path.addLines(decal.outline.map { let point = camera.project($0); return CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)) })
                path.closeSubpath()
                context.drawLayer { soft in
                    soft.addFilter(.blur(radius: CGFloat(camera.scale) * 0.035))
                    soft.fill(path, with: .color(decal.color))
                }
            }
            let painted = strokes(layers: layer...layer, pose: pose, camera: camera)
            var run = Path(), runColor = -1, runFaded = false
            func flush(_ context: inout GraphicsContext) {
                guard runColor >= 0 else { return }
                context.fill(run, with: .color((runFaded ? Palette.dimmed : Palette.colors)[runColor]))
                run = Path()
                runColor = -1
            }
            for stroke in painted {
                let faded = chosen >= 0 && stroke.part != chosen
                if !rimmed, stroke.part == chosen {
                    flush(&context)
                    rim(painted, part: chosen, in: &context)
                    rimmed = true
                }
                if stroke.corners == 0 || stroke.alpha < 1 {
                    flush(&context)
                    paint(stroke, faded: faded, in: &context)
                    continue
                }
                if stroke.color != runColor || faded != runFaded {
                    flush(&context)
                    runColor = stroke.color
                    runFaded = faded
                }
                Scene3D.outline(stroke, into: &run)
            }
            flush(&context)
            // A chosen bough comes forward whole, also where others stand in front of it.
            if chosen >= 0, layer == Scene3D.standing, case .leaf = parts[chosen] {
                rim(painted, part: chosen, in: &context)
                for stroke in painted where stroke.part == chosen { paint(stroke, faded: false, in: &context) }
            }
        }
    }

    private func paint(_ stroke: Stroke, faded: Bool, in context: inout GraphicsContext) {
        let table = faded ? Palette.dimmed : Palette.colors
        let color = table[stroke.color].opacity(Double(stroke.alpha))
        if stroke.ball {
            let shape = Path(ellipseIn: CGRect(x: stroke.a.x - stroke.radius, y: stroke.a.y - stroke.radiusY, width: stroke.radius * 2, height: stroke.radiusY * 2))
            let stops = [Gradient.Stop(color: table[stroke.light], location: 0), .init(color: table[stroke.color], location: 0.52), .init(color: table[stroke.dark], location: 1)]
            let glow = CGPoint(x: stroke.a.x - stroke.radius * 0.34, y: stroke.a.y - stroke.radiusY * 0.44)
            context.fill(shape, with: .radialGradient(Gradient(stops: stops), center: glow, startRadius: 0, endRadius: stroke.radius * 1.5))
        } else if stroke.corners == 0 {
            let circle = Path(ellipseIn: CGRect(x: stroke.a.x - stroke.radius, y: stroke.a.y - stroke.radius, width: stroke.radius * 2, height: stroke.radius * 2))
            context.fill(circle, with: .color(color))
            if stroke.ring { context.stroke(circle, with: .color(Color.brand.opacity(faded ? 0.3 : Double(stroke.alpha))), lineWidth: 1.6) }
        } else {
            var path = Path()
            Scene3D.outline(stroke, into: &path)
            context.fill(path, with: .color(color))
        }
    }

    private func rim(_ strokes: [Stroke], part: Int, in context: inout GraphicsContext) {
        var shape = Path()
        for stroke in strokes where stroke.part == part && !stroke.slight {
            if stroke.ball {
                shape.addEllipse(in: CGRect(x: stroke.a.x - stroke.radius, y: stroke.a.y - stroke.radiusY, width: stroke.radius * 2, height: stroke.radiusY * 2))
            } else if stroke.corners > 0 {
                Scene3D.outline(stroke, into: &shape)
            }
        }
        context.stroke(shape, with: .color(.white), style: StrokeStyle(lineWidth: 7, lineJoin: .round))
        context.stroke(shape, with: .color(.accent), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
    }

    /// Adds a face to a path, a hair larger than it is, so neighbours leave no gap between them.
    private static func outline(_ stroke: Stroke, into path: inout Path) {
        let count = CGFloat(stroke.corners)
        let middle = stroke.corners == 4
            ? CGPoint(x: (stroke.a.x + stroke.b.x + stroke.c.x + stroke.d.x) / count, y: (stroke.a.y + stroke.b.y + stroke.c.y + stroke.d.y) / count)
            : CGPoint(x: (stroke.a.x + stroke.b.x + stroke.c.x) / count, y: (stroke.a.y + stroke.b.y + stroke.c.y) / count)
        func grown(_ point: CGPoint) -> CGPoint {
            let x = point.x - middle.x, y = point.y - middle.y
            let length = max((x * x + y * y).squareRoot(), 0.001)
            return CGPoint(x: point.x + x / length * 0.5, y: point.y + y / length * 0.5)
        }
        path.move(to: grown(stroke.a))
        path.addLine(to: grown(stroke.b))
        path.addLine(to: grown(stroke.c))
        if stroke.corners == 4 { path.addLine(to: grown(stroke.d)) }
        path.closeSubpath()
    }

    /// The part under a tap: the frontmost face there, or else the nearest thin part within reach.
    func part(at point: CGPoint, size: CGSize, pose: Pose) -> TreePart? {
        let camera = Camera(size: size)
        for layer in Scene3D.layers.reversed() {
            for stroke in strokes(layers: layer...layer, pose: pose, camera: camera).reversed() where stroke.part >= 0 {
                if stroke.ball {
                    let x = (point.x - stroke.a.x) / stroke.radius, y = (point.y - stroke.a.y) / stroke.radiusY
                    if x * x + y * y <= 1 { return parts[stroke.part] }
                } else if stroke.corners == 0 {
                    if hypot(stroke.a.x - point.x, stroke.a.y - point.y) <= max(stroke.radius, 18) { return parts[stroke.part] }
                } else if Scene3D.contains(stroke, point) {
                    return parts[stroke.part]
                }
            }
        }
        var best: (distance: CGFloat, part: TreePart)?
        for anchor in anchors {
            let spot = camera.project(place(anchor.point, turning(pose, anchor.motion)))
            let distance = hypot(CGFloat(spot.x) - point.x, CGFloat(spot.y) - point.y)
            if distance < 30, distance < (best?.distance ?? .infinity) { best = (distance, anchor.part) }
        }
        return best?.part
    }

    private static func contains(_ stroke: Stroke, _ point: CGPoint) -> Bool {
        let corners = stroke.corners == 4 ? [stroke.a, stroke.b, stroke.c, stroke.d] : [stroke.a, stroke.b, stroke.c]
        var inside = false
        var previous = corners[corners.count - 1]
        for corner in corners {
            if (corner.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - corner.x) * (point.y - corner.y) / (previous.y - corner.y) + corner.x {
                inside.toggle()
            }
            previous = corner
        }
        return inside
    }
}
