import CoreGraphics
import Testing
import UIKit
@testable import Kairos

/// The tree in space is built from the backend's tree, so every part of it has to be there, look its state and take a tap.
@MainActor
struct TreeTests {
    private let size = CGSize(width: 360, height: 468)

    @Test func everyPartOfTheTreeIsInTheScene() throws {
        for id in SnapshotTests.customers {
            let tree = try #require(Snapshot.workspace(id)).tree
            let scene = TreeModel.scene(for: tree, weather: tree.weather.type)
            for leaf in tree.leaves { #expect(scene.parts.contains(.leaf(leaf.id)), "\(id): no bough for \(leaf.id)") }
            for root in tree.roots { #expect(scene.parts.contains(.root(root.id)), "\(id): no root for \(root.id)") }
            for branch in tree.branches.prefix(2) { #expect(scene.parts.contains(.branch(branch.id))) }
            #expect(scene.parts.contains(.trunk))
            #expect(scene.parts.contains(.soil))
        }
    }

    @Test func aBoughShowsItsState() throws {
        for id in SnapshotTests.customers {
            let tree = try #require(Snapshot.workspace(id)).tree
            let scene = TreeModel.scene(for: tree, weather: tree.weather.type)
            for leaf in tree.leaves {
                let expected: Material = leaf.health == "ROTTEN" ? .leafRotten : leaf.health == "WILTING" ? .leafWilting : .leafHealthy
                #expect(scene.balls.contains { $0.part == .leaf(leaf.id) && $0.material == expected }, "\(id): \(leaf.id) is not drawn as \(leaf.health)")
            }
            #expect(scene.falling.isEmpty == !tree.leaves.contains { $0.health == "ROTTEN" })
        }
    }

    @Test func aTapChoosesThePartUnderIt() throws {
        let tree = try #require(Snapshot.workspace("maya")).tree
        let scene = TreeModel.scene(for: tree, weather: "CALM")
        let camera = Camera(size: size)
        func spot(_ point: Vec) -> CGPoint {
            let placed = camera.project(point)
            return CGPoint(x: CGFloat(placed.x), y: CGFloat(placed.y))
        }
        #expect(scene.part(at: spot(scene.foot + Vec(-0.1, -0.1, 0.3)), size: size, pose: Pose()) == .trunk)
        #expect(scene.part(at: spot(Vec(0.85, -0.85, 0)), size: size, pose: Pose()) == .soil)
        #expect(scene.part(at: CGPoint(x: 4, y: 4), size: size, pose: Pose()) == nil)
        // Turned to the front, a bough is hit at its middle.
        for leaf in tree.leaves {
            let angle = try #require(scene.boughAngles[leaf.id])
            let anchor = try #require(scene.anchors.first { $0.part == .leaf(leaf.id) })
            let turn = 1.25 * Float.pi - angle
            let offset = anchor.point - scene.foot
            let turned = scene.foot + Vec(offset.x * cos(turn) - offset.y * sin(turn), offset.x * sin(turn) + offset.y * cos(turn), offset.z)
            #expect(scene.part(at: spot(turned), size: size, pose: Pose(turn: turn)) == .leaf(leaf.id), "\(leaf.id) is not hit when it faces the viewer")
        }
    }

    @Test func aStormBringsDarkClouds() throws {
        let tree = try #require(Snapshot.workspace("maya")).tree
        #expect(TreeModel.scene(for: tree, weather: "STORM").balls.contains { $0.material == .stormCloud })
        #expect(!TreeModel.scene(for: tree, weather: "CALM").balls.contains { $0.material == .stormCloud })
    }

    @Test func everyFilmHasACoverAndThreePoints() {
        #expect(Set(Explainer.all.map(\.id)).count == Explainer.all.count)
        for film in Explainer.all {
            #expect(UIImage(named: film.art) != nil, "\(film.id) has no cover")
            #expect(film.points.count == 3)
        }
        for category in CategoryID.allCases { #expect(Explainer.about(category).count >= 3) }
    }

    @Test func theStepsOfThePlanComeWithAFilm() throws {
        for id in SnapshotTests.customers {
            let workspace = try #require(Snapshot.workspace(id))
            #expect(workspace.agentActions.contains { Explainer.before($0) != nil })
            #expect(Explainer.picks(for: workspace).count >= 3)
        }
    }
}
