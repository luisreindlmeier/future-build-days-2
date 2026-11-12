import simd
import SwiftUI

/// A part of the tree that can be tapped.
enum TreePart: Hashable {
    case leaf(String), root(String), branch(String), trunk, soil
}

/// Builds the wealth tree in space from the backend's `TreeState`, the way the web dashboard draws it: a block of
/// grass and soil cut open at the front, with the roots (savings) in the cut, a trunk (investing), one leafy bough
/// per spending category around it, and a side branch per project. A bough is lush when the spending is in line,
/// yellowing when it is above peers, thin and brown with falling leaves when it is far above. Shapes are round and
/// few, like a game board piece, not a botanical drawing.
struct TreeModel {
    private var scene = Scene3D()
    private var chance = Chance(11)
    private let tree: TreeState
    private let grow: Float
    private let foot = Vec(-0.42, -0.42, 0)
    private var floorLeft: [Float] = []
    private var floorRight: [Float] = []

    private static let columns = 10
    /// Where the roots show in each side of the cut, measured from the front corner: right below the trunk.
    private static let rootStart: Float = 0.07

    static func scene(for tree: TreeState, weather: String) -> Scene3D {
        var model = TreeModel(tree: tree)
        model.clouds(weather)
        model.block()
        model.roots()
        model.turf()
        model.meadow()
        model.trunk()
        model.crown()
        model.projects()
        return model.scene
    }

    private init(tree: TreeState) {
        self.tree = tree
        grow = switch tree.stage {
        case "SAPLING": 0.74
        case "YOUNG": 0.88
        default: 1
        }
        scene.foot = foot
    }

    private var trunkHeight: Float { (0.72 + 0.7 * Float(tree.trunk.height)) * grow }
    private var trunkRadius: Float { (0.09 + 0.13 * Float(tree.trunk.thickness)) * grow.squareRoot() }

    private mutating func add(_ mesh: Mesh) {
        guard !mesh.faces.isEmpty else { return }
        _ = scene.index(of: mesh.part)
        scene.meshes.append(mesh)
    }

    private mutating func add(_ dot: Dot) {
        _ = scene.index(of: dot.part)
        scene.dots.append(dot)
    }

    private mutating func add(_ ball: Ball) {
        _ = scene.index(of: ball.part)
        scene.balls.append(ball)
    }

    // MARK: Shapes

    /// A limb: a smooth tube that follows a path and thins along it. `flare` widens its start into lobes, like the foot of a trunk.
    private func tube(into mesh: inout Mesh, along path: [Vec], radii: [Float], sides: Int, _ material: Material, tone: Float = 0, flare: Float = 0) {
        let start = mesh.points.count
        var side = Vec.zero
        for index in path.indices {
            let along = simd_normalize(path[min(index + 1, path.count - 1)] - path[max(index - 1, 0)])
            if index == 0 {
                side = simd_normalize(simd_cross(abs(along.z) < 0.92 ? Vec(0, 0, 1) : Vec(1, 0, 0), along))
            } else {
                side = simd_normalize(side - along * simd_dot(side, along))
            }
            let over = simd_cross(along, side)
            for step in 0..<sides {
                let angle = Float(step) / Float(sides) * 2 * .pi
                let lobes = 1 + flare * exp(-Float(index) * 1.1) * cos(4 * angle + 0.6)
                mesh.points.append(path[index] + (side * cos(angle) + over * sin(angle)) * (radii[index] * lobes))
            }
        }
        for index in 0..<(path.count - 1) {
            for step in 0..<sides {
                let next = (step + 1) % sides
                let a = start + index * sides + step, b = start + index * sides + next
                let c = start + (index + 1) * sides + next, d = start + (index + 1) * sides + step
                var normal = simd_normalize(simd_cross(mesh.points[c] - mesh.points[a], mesh.points[d] - mesh.points[b]))
                let middle = (mesh.points[a] + mesh.points[b] + mesh.points[c] + mesh.points[d]) / 4
                if simd_dot(normal, middle - (path[index] + path[index + 1]) / 2) < 0 { normal = -normal }
                mesh.faces.append(Face(a: Int32(a), b: Int32(b), c: Int32(c), d: Int32(d), normal: normal, material: material, tone: tone))
            }
        }
    }

    private static func curve(from start: Vec, via middle: Vec, to end: Vec, steps: Int) -> [Vec] {
        (0...steps).map { step in
            let part = Float(step) / Float(steps), rest = 1 - part
            return start * (rest * rest) + middle * (2 * rest * part) + end * (part * part)
        }
    }

    private static func thinning(from start: Float, to end: Float, steps: Int) -> [Float] {
        (0...steps).map { start + (end - start) * Float($0) / Float(steps) }
    }

    /// A point on one of the two cut sides of the block: `along` from the front corner, `height` below the grass.
    private func wall(_ left: Bool, _ along: Float, _ height: Float, out: Float = 0) -> Vec {
        left ? Vec(-1 - out, -1 + along, height) : Vec(-1 + along, -1 - out, height)
    }

    private func wallNormal(_ left: Bool) -> Vec { left ? Vec(-1, 0, 0) : Vec(0, -1, 0) }

    /// The underside of the block along a side: deepest at the front corner.
    private func floor(_ left: Bool, at along: Float) -> Float {
        let levels = left ? floorLeft : floorRight
        let position = max(0, min(Float(Self.columns) - 0.001, along / 0.2))
        let column = Int(position), part = position - Float(column)
        return levels[column] * (1 - part) + levels[column + 1] * part
    }

    /// From a place on the page, in the tree's units, to a point in space that lands there.
    private static func behind(across: Float, down: Float, away: Float) -> Vec {
        let height = (-down - away * 0.5) / 0.86603
        return Vec((across + away) / 1.41421, (away - across) / 1.41421, height)
    }

    // MARK: The block of soil

    private mutating func block() {
        let soil = tree.soil
        let rich = Float(max(0, min(1, soil.richness)))
        floorLeft = (0...Self.columns).map { -(0.9 - 0.16 * Float($0) * 0.2) + 0.018 * sin(Float($0) * 1.9) }
        floorRight = (0...Self.columns).map { -(0.9 - 0.16 * Float($0) * 0.2) - 0.018 * sin(Float($0) * 1.9) }

        let strata = max(1, min(3, soil.layers))
        let topsoil = -(0.17 + 0.2 * rich)
        var edges: [Float] = [0, -0.055, topsoil]
        for layer in 1...strata { edges.append(topsoil + (-0.64 - topsoil) * Float(layer) / Float(strata)) }
        edges.append(-3)
        let materials: [Material] = [.turf, .topsoil] + [Material.soilA, .soilB, .soilC].prefix(strata) + [.soilDeep]

        var sides = Mesh(layer: 1, part: .soil)
        for left in [true, false] {
            let normal = wallNormal(left), turn: Float = left ? 1 : -1
            func wave(_ edge: Int, _ along: Float) -> Float {
                edge < 2 ? 0 : 0.022 * sin(along * (2.6 + Float(edge) * 0.7) * turn)
            }
            for column in 0..<Self.columns {
                let near = Float(column) * 0.2, far = near + 0.2
                let floorNear = floor(left, at: near), floorFar = floor(left, at: min(far, 1.999))
                let rockNear = floorNear + 0.14, rockFar = floorFar + 0.14
                for band in materials.indices {
                    let topNear = max(edges[band] + wave(band, near), rockNear), topFar = max(edges[band] + wave(band, far), rockFar)
                    let lowNear = max(edges[band + 1] + wave(band + 1, near), rockNear), lowFar = max(edges[band + 1] + wave(band + 1, far), rockFar)
                    guard (topNear - lowNear) + (topFar - lowFar) > 0.004 else { continue }
                    sides.quad(wall(left, near, topNear), wall(left, far, topFar), wall(left, far, lowFar), wall(left, near, lowNear), facing: normal, materials[band])
                }
                sides.quad(wall(left, near, rockNear), wall(left, far, rockFar), wall(left, far, floorFar), wall(left, near, floorNear),
                           facing: normal, .rock, tone: column.isMultiple(of: 2) ? 0.03 : -0.03)
            }
        }
        add(sides)

        // The grass: smooth, with one soft lighter patch and a mound at the foot of the trunk.
        let cells = 8
        var heights = [[Float]](repeating: [Float](repeating: 0, count: cells + 1), count: cells + 1)
        func spot(_ column: Int, _ row: Int) -> Vec {
            Vec(-1 + 2 * Float(column) / Float(cells), -1 + 2 * Float(row) / Float(cells), heights[column][row])
        }
        for column in 1..<cells {
            for row in 1..<cells {
                let place = spot(column, row)
                heights[column][row] = 0.06 * exp(-simd_length_squared(Vec(place.x - foot.x, place.y - foot.y, 0)) / 0.1)
            }
        }
        var grass = Mesh(layer: 1, part: .soil)
        for column in 0..<cells {
            for row in 0..<cells {
                let a = spot(column, row), b = spot(column + 1, row), c = spot(column + 1, row + 1), d = spot(column, row + 1)
                let middle = (a + c) / 2
                let lighter = 0.07 * exp(-simd_length_squared(Vec(middle.x - 0.45, middle.y - 0.35, 0)) / 0.25)
                let darker = 0.03 * exp(-simd_length_squared(Vec(middle.x + 0.6, middle.y - 0.55, 0)) / 0.2)
                grass.quad(a, b, c, d, facing: Vec(0, 0, 1), .grass, tone: lighter - darker)
            }
        }
        add(grass)

        var pebbles = Mesh(layer: 2, part: .soil)
        for _ in 0..<12 {
            let left = chance.next() < 0.5, along = chance.between(0.15, 1.8)
            let lowest = floor(left, at: along) + 0.2
            guard lowest < -0.2 else { continue }
            let height = chance.between(lowest, -0.2), size = chance.between(0.02, 0.036)
            let rim = (0..<8).map { step -> Vec in
                let angle = Float(step) / 8 * 2 * .pi
                return wall(left, along + cos(angle) * size, height + sin(angle) * size * 0.72, out: 0.003)
            }
            let tone = 0.1 * chance.signed()
            for step in 1..<7 { pebbles.triangle(rim[0], rim[step], rim[step + 1], facing: wallNormal(left), .pebble, tone: tone) }
        }
        add(pebbles)
    }

    // MARK: Roots, in the cut

    private mutating func roots() {
        for (index, root) in tree.roots.prefix(4).enumerated() {
            let left = index.isMultiple(of: 2), far = index >= 2
            let part = TreePart.root(root.id)
            let missing = root.status == "MISSING"
            let depth = missing ? 0.34 : Float(max(0, min(1, root.depth)))
            var endAlong: Float = far ? 1.0 + 0.6 * depth : 0.52 + 0.45 * depth
            var endHeight: Float = far ? -(0.22 + 0.36 * depth) : -(0.28 + 0.5 * depth)
            endAlong = min(endAlong, 1.82)
            endHeight = max(endHeight, floor(left, at: endAlong) + 0.2)
            let start = SIMD2<Float>(Self.rootStart, -0.03), end = SIMD2<Float>(endAlong, endHeight)
            let bend = SIMD2<Float>(start.x + (end.x - start.x) * 0.35, end.y * 0.94)
            func spot(_ along: Float) -> SIMD2<Float> {
                let rest = 1 - along
                return start * (rest * rest) + bend * (2 * rest * along) + end * (along * along)
            }
            let tip = wall(left, end.x, end.y, out: 0.03)
            scene.anchors.append(Anchor(point: tip, motion: .fixed, part: part))
            scene.anchors.append(Anchor(point: wall(left, spot(0.55).x, spot(0.55).y, out: 0.03), motion: .fixed, part: part))

            if missing {
                // No root yet: a dotted line where one could grow.
                for step in 1..<8 {
                    let place = spot(Float(step) / 8)
                    add(Dot(center: wall(left, place.x, place.y, out: 0.01), radius: 0.015, material: .white, alpha: 0.55, layer: 2, part: part))
                }
                add(Dot(center: tip, radius: 5, fixedSize: true, material: .white, alpha: 0.6, ring: true, layer: 2, part: part))
                continue
            }

            let weak = root.status == "NEEDS_CARE"
            let material: Material = weak ? .rootWeak : .root
            let thick = 0.034 + 0.06 * Float(max(0, min(1, root.thickness)))
            var mesh = Mesh(layer: 2, part: part)
            let steps = 10
            let path = (0...steps).map { step -> Vec in
                let place = spot(Float(step) / Float(steps))
                let radius = thick + (0.012 - thick) * Float(step) / Float(steps)
                return wall(left, place.x, place.y, out: radius * 0.5)
            }
            tube(into: &mesh, along: path, radii: Self.thinning(from: thick, to: 0.012, steps: steps), sides: 8, material)
            for rootlet in 0..<(weak ? 1 : 2) {
                let from = spot(0.45 + 0.28 * Float(rootlet))
                let reach = SIMD2<Float>(chance.between(-0.04, 0.14), -chance.between(0.1, 0.17))
                let lowest = floor(left, at: min(1.9, max(0.05, from.x + reach.x))) + 0.18
                let to = SIMD2<Float>(from.x + reach.x, max(from.y + reach.y, lowest))
                let middle = SIMD2<Float>(from.x + reach.x * 0.3, from.y + (to.y - from.y) * 0.7)
                let line = Self.curve(from: wall(left, from.x, from.y, out: 0.014), via: wall(left, middle.x, middle.y, out: 0.012), to: wall(left, to.x, to.y, out: 0.008), steps: 4)
                tube(into: &mesh, along: line, radii: Self.thinning(from: thick * 0.5, to: 0.008, steps: 4), sides: 6, material, tone: -0.04)
            }
            add(mesh)
            add(Dot(center: tip, radius: 5, fixedSize: true, material: .white, ring: true, layer: 2, part: part, forward: 0.2))
        }
    }

    /// The edge of the grass, hanging over the cut in round tongues.
    private mutating func turf() {
        var lip = Mesh(layer: 2, part: .soil)
        for left in [true, false] {
            var along: Float = 0.06, count = 0
            while along < 1.96 {
                let size = chance.between(0.058, 0.09)
                let center = wall(left, along, -0.035, out: 0.006)
                let arc = (0...6).map { step -> Vec in
                    let angle = Float.pi + Float(step) / 6 * .pi
                    return wall(left, along + cos(angle) * size, -0.035 + sin(angle) * size * 1.15, out: 0.006)
                }
                for step in 0..<6 { lip.triangle(center, arc[step], arc[step + 1], facing: wallNormal(left), .turf, tone: count.isMultiple(of: 2) ? 0.05 : -0.02) }
                along += size * 1.5
                count += 1
            }
        }
        add(lip)
    }

    // MARK: On the grass

    private mutating func meadow() {
        let crownReach = (0.66 + 0.34) * grow
        // The shadow of the crown falls away from the light, and stays on the block.
        let shade = (0..<28).map { step -> Vec in
            let angle = Float(step) / 28 * 2 * .pi
            let x = foot.x + 0.28 + cos(angle) * crownReach * 0.98, y = foot.y + 0.1 + sin(angle) * crownReach * 0.82
            return Vec(max(-0.99, min(0.99, x)), max(-0.99, min(0.99, y)), 0.012)
        }
        scene.decals.append(Decal(outline: shade, color: Color(hex: 0x1D4A22, opacity: 0.22), layer: 3))
        let contact = (0..<16).map { step -> Vec in
            let angle = Float(step) / 16 * 2 * .pi
            return Vec(foot.x + 0.06 + cos(angle) * trunkRadius * 3, foot.y + 0.02 + sin(angle) * trunkRadius * 2.4, 0.05)
        }
        scene.decals.append(Decal(outline: contact, color: Color(hex: 0x1D4A22, opacity: 0.24), layer: 3))

        // A few tufts of grass and small flowers, no more.
        var blades = Mesh(layer: 4, twoSided: true)
        let tufts: [(Float, Float)] = [(0.62, -0.7), (0.8, 0.15), (0.3, 0.72), (-0.35, 0.7), (-0.8, 0.3), (-0.78, -0.2), (0.15, -0.86), (0.72, 0.72), (-0.1, 0.25), (0.45, -0.2)]
        for (index, tuft) in tufts.enumerated() {
            let place = Vec(tuft.0, tuft.1, 0.005)
            for blade in -1...1 {
                let lean = Vec(Float(blade) * 0.045, Float(blade) * -0.02, blade == 0 ? 0.15 : 0.11)
                let base = Camera.right * 0.022
                blades.triangle(place - base, place + base, place + lean, .blade, tone: blade == 0 ? 0.1 : -0.04)
            }
            if index.isMultiple(of: 3) {
                add(Dot(center: place + Vec(0.06, 0.04, 0.05), radius: 0.024, material: index.isMultiple(of: 2) ? .petalPink : .petalCream, shade: 0.75, layer: 4))
            }
        }
        add(blades)

        for (x, y, size) in [(Float(0.58), Float(-0.5), Float(0.085)), (-0.68, 0.52, 0.1), (0.3, 0.55, 0.06)] {
            add(Ball(center: Vec(x, y, size * 0.4), radius: size, squash: 0.68, material: .stone, layer: 4))
        }

        // One flower for every training finished, as on the dashboard.
        let petals: [Material] = [.petalPink, .petalCream, .petalBlue, .petalPeach]
        var stems = Mesh(layer: 4, twoSided: true)
        for flower in 0..<min(tree.soil.trainingsCompleted ?? 0, 6) {
            let angle = 3.4 + Float(flower) * 0.62, reach = 0.36 + 0.07 * Float(flower % 3)
            let ground = Vec(foot.x + cos(angle) * reach, foot.y + sin(angle) * reach, 0.01)
            let head = ground + Vec(0, 0, 0.16)
            stems.quad(ground - Camera.right * 0.007, ground + Camera.right * 0.007, head + Camera.right * 0.006, head - Camera.right * 0.006, .blade, tone: -0.1)
            for petal in 0..<5 {
                let around = Float(petal) / 5 * 2 * .pi
                add(Dot(center: head + (Camera.right * cos(around) + Camera.up * sin(around)) * 0.034, radius: 0.03, material: petals[flower % petals.count], shade: 0.7, layer: 4, forward: 0.01))
            }
            add(Dot(center: head, radius: 0.022, material: .pollen, shade: 0.6, layer: 4, forward: 0.02))
        }
        add(stems)

        // Roots spread from the foot of the trunk and dip into the grass.
        var surface = Mesh(layer: 4, part: .trunk)
        for (angle, length) in [(Float(0.4), Float(0.32)), (1.7, 0.36), (3.0, 0.3), (4.1, 0.34), (5.3, 0.33)] {
            let away = Vec(cos(angle), sin(angle), 0)
            let aside = Vec(-away.y, away.x, 0) * 0.05
            let line = Self.curve(from: foot + away * trunkRadius * 0.9 + Vec(0, 0, 0.04), via: foot + away * length * 0.6 + aside + Vec(0, 0, 0.02), to: foot + away * length * grow - Vec(0, 0, 0.03), steps: 5)
            tube(into: &surface, along: line, radii: Self.thinning(from: trunkRadius * 0.42, to: 0.012, steps: 5), sides: 8, .bark, tone: -0.02)
        }
        add(surface)
    }

    // MARK: The trunk

    private mutating func trunk() {
        let height = trunkHeight, radius = trunkRadius
        let pale = Float(1 - max(0, min(1, tree.trunk.barkHealth))) * 0.25
        let levels: [Float] = [0, 0.04, 0.1, 0.2, 0.34, 0.48, 0.62, 0.76, 0.88, 1]
        let path = levels.map { level in foot + Vec(0.03 * sin(level * .pi) * grow, -0.02 * sin(level * .pi * 2) * grow, level * height) }
        let radii = levels.map { level in radius * (1 + 0.85 * exp(-level * 12)) * (1 - 0.36 * level) }
        var mesh = Mesh(layer: 4, motion: .lean, part: .trunk)
        tube(into: &mesh, along: path, radii: radii, sides: 16, .bark, tone: pale, flare: 0.14)

        // A knot, cracks for risks and a band for every year of regular investing: all on the side that faces the viewer.
        func surface(_ level: Float, _ angle: Float, out: Float = 0.006) -> Vec {
            let position = level * Float(levels.count - 1)
            let index = min(levels.count - 2, Int(position)), part = position - Float(index)
            let center = path[index] * (1 - part) + path[index + 1] * part
            let reach = (radii[index] * (1 - part) + radii[index + 1] * part) + out
            return center + Vec(cos(angle), sin(angle), 0) * reach
        }
        let front: Float = 1.25 * .pi
        func ribbon(_ points: [Vec], width: Float, facing: Vec, _ material: Material, tone: Float) {
            for index in 0..<(points.count - 1) {
                let along = simd_normalize(points[index + 1] - points[index])
                let across = simd_normalize(simd_cross(along, facing)) * width
                mesh.quad(points[index] - across, points[index] + across, points[index + 1] + across, points[index + 1] - across, facing: facing, material, tone: tone)
            }
        }
        for (offset, from, to) in [(Float(-0.7), Float(0.2), Float(0.72)), (0.55, 0.3, 0.85)] {
            let angle = front + offset
            let line = (0...5).map { step in surface(from + (to - from) * Float(step) / 5, angle + 0.05 * sin(Float(step) * 1.4)) }
            ribbon(line, width: 0.006, facing: Vec(cos(angle), sin(angle), 0), .groove, tone: 0.3)
        }
        for ring in 0..<min(tree.trunk.rings, 5) {
            let level = 0.2 + 0.11 * Float(ring)
            let line = (0...10).map { step in surface(level, front - 1.3 + 2.6 * Float(step) / 10, out: 0.008) }
            for index in 0..<(line.count - 1) {
                let angle = front - 1.3 + 2.6 * (Float(index) + 0.5) / 10
                let rise = Vec(0, 0, 0.013)
                mesh.quad(line[index] - rise, line[index + 1] - rise, line[index + 1] + rise, line[index] + rise, facing: Vec(cos(angle), sin(angle), 0), .groove, tone: 0.3)
            }
        }
        for crack in 0..<min(tree.trunk.cracks, 3) {
            let angle = front + 0.18 - 0.45 * Float(crack)
            let top = 0.64 - 0.16 * Float(crack)
            let line = (0...4).map { step in surface(top - 0.06 * Float(step), angle + (step.isMultiple(of: 2) ? 0.11 : -0.11), out: 0.009) }
            ribbon(line, width: 0.01, facing: Vec(cos(angle), sin(angle), 0), .groove, tone: -0.3)
        }
        add(mesh)
        add(Dot(center: surface(0.46, front - 0.3, out: 0.01), radius: 0.03 * grow, material: .groove, shade: 0.8, alpha: 0.75, layer: 4, motion: .lean, part: .trunk, forward: 0.02))
        add(Dot(center: surface(0.46, front - 0.3, out: 0.012), radius: 0.014 * grow, material: .groove, shade: 0.1, alpha: 0.85, layer: 4, motion: .lean, part: .trunk, forward: 0.03))
    }

    // MARK: The crown

    private mutating func crown() {
        let top = foot + Vec(0, 0, trunkHeight)
        let leaves = Array(tree.leaves.prefix(8))
        let middle = top.z + 0.36 * grow, half = 0.7 * grow
        func height(_ point: Vec) -> Float { 0.1 * max(-1, min(1, (point.z - middle) / half)) }

        // A dark heart, so the boughs read as one crown.
        for step in 0..<5 {
            let angle = Float(step) / 5 * 2 * .pi + 0.4
            let center = top + Vec(cos(angle) * 0.24, sin(angle) * 0.24, 0.26 + 0.2 * Float(step % 3)) * grow
            add(Ball(center: center, radius: (0.3 + 0.03 * Float(step % 2)) * grow, material: .canopy, tone: height(center) - 0.04, layer: 4, motion: .turn))
        }

        for (index, leaf) in leaves.enumerated() {
            let part = TreePart.leaf(leaf.id)
            let angle = Float(index) / Float(max(leaves.count, 1)) * 2 * .pi
            scene.boughAngles[leaf.id] = angle
            let upper = !index.isMultiple(of: 2)
            let reach = (upper ? 0.42 : 0.72) * grow
            let size = (0.28 + 0.21 * Float(max(0, min(1, leaf.size)))) * grow
            let direction = Vec(cos(angle), sin(angle), 0), across = Vec(-sin(angle), cos(angle), 0)
            let center = top + direction * reach + Vec(0, 0, (upper ? 0.62 : 0.18) * grow)
            scene.anchors.append(Anchor(point: center, motion: .turn, part: part))

            let thin = leaf.health == "ROTTEN"
            let material: Material = switch leaf.health {
            case "WILTING": .leafWilting
            case "ROTTEN": .leafRotten
            default: .leafHealthy
            }

            var limb = Mesh(layer: 4, motion: .turn, part: part)
            let start = top + direction * trunkRadius * 0.3 - Vec(0, 0, 0.1 * trunkHeight)
            let end = center - Vec(0, 0, size * 0.25)
            let bend = start + direction * reach * 0.55 + Vec(0, 0, (end.z - start.z) * 0.22)
            tube(into: &limb, along: Self.curve(from: start, via: bend, to: end, steps: 6), radii: Self.thinning(from: max(0.04, trunkRadius * 0.5), to: 0.02, steps: 6), sides: 8, .bark, tone: -0.04)
            if thin {
                // Bare twigs show through a thinning bough.
                for twig in 0..<3 {
                    let around = Float(twig) * 2.1 + angle
                    let tip = center + Vec(cos(around) * 0.8, sin(around) * 0.8, 0.35 + 0.25 * Float(twig % 2)) * size
                    tube(into: &limb, along: Self.curve(from: end, via: (end + tip) / 2 + Vec(0, 0, 0.05), to: tip, steps: 3), radii: Self.thinning(from: 0.018, to: 0.007, steps: 3), sides: 5, .bark, tone: -0.1)
                }
            }
            add(limb)

            if thin {
                // What is left of the leaves: two small clumps.
                for (shift, lift, scale) in [(Float(-0.3), Float(0.1), Float(0.46)), (0.34, 0.3, 0.38)] {
                    let place = center + across * shift * size + Vec(0, 0, lift * size)
                    add(Ball(center: place, radius: size * scale, material: material, tone: height(place), layer: 4, motion: .turn, part: part))
                }
                for _ in 0..<4 {
                    scene.falling.append(FallingLeaf(origin: center + Vec(chance.signed() * size * 0.7, chance.signed() * size * 0.7, -size * 0.3), phase: chance.next(), part: part))
                }
            } else {
                // One large clump with three smaller ones around it. A yellowing bough keeps one of them green.
                add(Ball(center: center, radius: size * 0.8, material: material, tone: height(center), layer: 4, motion: .turn, part: part))
                let around: [Vec] = [direction * 0.42 + across * 0.42 + Vec(0, 0, 0.3), direction * 0.38 - across * 0.46 + Vec(0, 0, 0.12), direction * -0.12 + across * 0.1 + Vec(0, 0, 0.62)]
                for (clump, place) in around.enumerated() {
                    let spot = center + place * size
                    let green = leaf.health == "WILTING" && clump == 1
                    add(Ball(center: spot, radius: size * (0.56 - 0.05 * Float(clump)), material: green ? .leafHealthy : material, tone: height(spot), layer: 4, motion: .turn, part: part))
                }
            }
        }
    }

    // MARK: Projects: a side branch each, with a bud, a blossom or a fruit

    private mutating func projects() {
        let directions = [Vec(-0.97, 0.24, 0), Vec(0.24, -0.97, 0)]
        for (index, branch) in tree.branches.prefix(2).enumerated() {
            let part = TreePart.branch(branch.id)
            let direction = directions[index]
            let level = 0.44 + 0.16 * Float(index)
            let start = foot + Vec(0, 0, level * trunkHeight) + direction * trunkRadius * 0.4
            let length = (0.36 + 0.36 * Float(max(0, min(1, branch.length)))) * grow
            let end = start + direction * length + Vec(0, 0, 0.17 * grow)
            var mesh = Mesh(layer: 4, motion: .lean, part: part)
            tube(into: &mesh, along: Self.curve(from: start, via: start + direction * length * 0.55 + Vec(0, 0, 0.01), to: end, steps: 5),
                 radii: Self.thinning(from: 0.045 * grow, to: 0.02, steps: 5), sides: 8, .bark)
            add(mesh)
            scene.anchors.append(Anchor(point: end, motion: .lean, part: part))
            if branch.fruit == true {
                add(Ball(center: end - Vec(0, 0, 0.08), radius: 0.085, squash: 0.96, material: .fruit, layer: 4, motion: .lean, part: part))
            } else if branch.blossom == true {
                for petal in 0..<5 {
                    let around = Float(petal) / 5 * 2 * .pi
                    add(Dot(center: end + (Camera.right * cos(around) + Camera.up * sin(around)) * 0.042, radius: 0.036, material: .blossom, shade: 0.65, layer: 4, motion: .lean, part: part, forward: 0.05))
                }
                add(Dot(center: end, radius: 0.024, material: .pollen, shade: 0.75, layer: 4, motion: .lean, part: part, forward: 0.07))
            } else {
                // Not in blossom yet: a bud of fresh leaves.
                let bud: [(Vec, Float)] = [(Vec(0, 0, 0.04), 0.1), (direction * 0.08, 0.075), (direction * -0.05 + Vec(0, 0, 0.1), 0.065)]
                for (offset, size) in bud {
                    add(Ball(center: end + offset, radius: size, squash: 0.85, material: .fresh, layer: 4, motion: .lean, part: part))
                }
            }
        }
    }

    // MARK: Weather

    private mutating func clouds(_ weather: String) {
        let places: [(Float, Float, Float)]
        switch weather {
        case "BREEZY": places = [(-0.95, -1.9, 0.22), (1.05, -2.05, 0.14)]
        case "WINDY": places = [(-0.98, -1.92, 0.24), (1.02, -1.62, 0.18), (0.35, -2.12, 0.13)]
        case "STORM": places = [(-0.85, -1.95, 0.3), (0.2, -2.1, 0.25), (1.0, -1.78, 0.26)]
        default: places = [(1.05, -2.04, 0.15)]
        }
        let material: Material = weather == "STORM" ? .stormCloud : .cloud
        let lumps: [(Float, Float, Float)] = [(-1.05, -0.1, 0.6), (-0.3, 0.25, 0.9), (0.55, 0.12, 0.78), (1.2, -0.12, 0.5)]
        for (across, down, size) in places {
            let center = Self.behind(across: across, down: down, away: 1.3)
            for (shift, lift, scale) in lumps {
                add(Ball(center: center + Camera.right * shift * size + Vec(0, 0, lift * size) + Camera.view * shift * 0.01, radius: size * scale, squash: 0.85, material: material, tone: 0.1, layer: 0))
            }
        }
    }
}
