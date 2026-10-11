import XCTest

@testable import CutawayScene

/// Which layer is under a point of the viewport (C-SCENE-05).
final class HitTestTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)

    private func fixtureLayout() throws -> SceneLayout {
        SceneLayout(layers: try SceneFixtures.hierarchyLayers(), expanded: SceneFixtures.allIDs)
    }

    /// A window point in the viewport under the flat camera, worked out here:
    /// the fixture's content box is 0, 0, 393, 852.
    private func flatViewPoint(_ x: Double, _ y: Double) -> ScenePoint {
        let scale = min((480 - 2 * Camera.margin) / 393, (900 - 2 * Camera.margin) / 852)
        return ScenePoint(x: 240 + (x - 196.5) * scale, y: 450 + (y - 426) * scale)
    }

    /// The frontmost item whose corners, split into two triangles, hold the point. Written
    /// apart from the code under test.
    private func bruteForce(_ list: DrawList, _ p: ScenePoint) -> UInt64? {
        func cross(_ o: ScenePoint, _ u: ScenePoint, _ v: ScenePoint) -> Double {
            (u.x - o.x) * (v.y - o.y) - (u.y - o.y) * (v.x - o.x)
        }
        func inTriangle(_ a: ScenePoint, _ b: ScenePoint, _ c: ScenePoint) -> Bool {
            guard abs(cross(a, b, c)) > 1e-9 else { return false }
            let d1 = cross(a, b, p), d2 = cross(b, c, p), d3 = cross(c, a, p)
            let negative = d1 < 0 || d2 < 0 || d3 < 0
            let positive = d1 > 0 || d2 > 0 || d3 > 0
            return !(negative && positive)
        }
        for item in list.items.reversed() {
            let q = item.points
            if inTriangle(q[0], q[1], q[3]) || inTriangle(q[0], q[3], q[2]) { return item.layerID }
        }
        return nil
    }

    func test_C_SCENE_05_eachLayersCenterHitsIt() throws {
        let layout = try fixtureLayout()
        for camera in [Camera.flat, .standard3D] {
            let list = layout.project(camera: camera, viewport: viewport, selected: nil, hovered: nil)
            for id: UInt64 in [3, 4, 7, 8] {
                let center = try XCTUnwrap(list.items.first { $0.layerID == id }?.center)
                XCTAssertEqual(
                    layout.hitTest(point: center, camera: camera, viewport: viewport), id,
                    "layer \(id), \(camera)")
            }
        }
    }

    func test_C_SCENE_05_aTurnedLayerIsHitByItsShapeNotItsBox() throws {
        // (40, 160) is inside layer 4's bounding box but outside the turned card; layer 2 is
        // behind it.
        let layout = try fixtureLayout()
        XCTAssertEqual(
            layout.hitTest(point: flatViewPoint(40, 160), camera: .flat, viewport: viewport), 2)
    }

    func test_C_SCENE_05_aPointOutsideEveryLayerHitsNothing() throws {
        let layout = try fixtureLayout()
        for camera in [Camera.flat, .standard3D] {
            XCTAssertNil(
                layout.hitTest(point: ScenePoint(x: 5, y: 5), camera: camera, viewport: viewport))
        }
        XCTAssertNil(
            SceneLayout(layers: [], expanded: [])
                .hitTest(point: ScenePoint(x: 5, y: 5), camera: .flat, viewport: viewport))
    }

    func test_C_SCENE_05_aHiddenLayerIsNeverHit() throws {
        // Where the hidden layer 5 is, the card it sits on is hit.
        let layout = try fixtureLayout()
        let center = try XCTUnwrap(layout.quad(of: 5)).center
        XCTAssertEqual(
            layout.hitTest(
                point: flatViewPoint(center.x, center.y), camera: .flat, viewport: viewport), 4)
    }

    func test_C_SCENE_05_aLayerWithoutAreaIsNeverHit() throws {
        let layout = try fixtureLayout()
        let list = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertFalse(list.items.contains { $0.layerID == 9 })
        XCTAssertNotEqual(
            layout.hitTest(point: flatViewPoint(300, 700), camera: .flat, viewport: viewport), 9)

        // Frontmost and without area: the layer under it is hit.
        let thin = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, x: 50, y: 0, width: 0, height: 100),
            ],
            expanded: [1, 2])
        let thinList = thin.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(thinList.items.map(\.layerID), [1])
        XCTAssertEqual(thinList.layer(at: thinList.items[0].center), 1)
    }

    func test_C_SCENE_05_aMirroredLayerIsHit() {
        var mirrored = SceneFixtures.layer(1, x: 100, y: 0, width: 100, height: 100)
        mirrored.transform.m11 = -1  // reaches from x 0 to 100
        let layout = SceneLayout(layers: [mirrored], expanded: [1])
        let list = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(list.layer(at: list.items[0].center), 1)
    }

    func test_C_SCENE_05_theResultAgreesWithTheDrawListForAnyCamera() throws {
        let layout = try fixtureLayout()
        let angles = [-150.0, -45, 0, 30, 120].map { $0 * .pi / 180 }
        var hits = 0
        for projection in [Projection.orthographic, .perspective] {
            for yaw in angles {
                for pitch in angles {
                    let camera = Camera(
                        projection: projection, yaw: yaw, pitch: pitch, zoom: 1.3,
                        pan: ScenePoint(x: -15, y: 20), layerSpacing: 40)
                    let list = layout.project(
                        camera: camera, viewport: viewport, selected: nil, hovered: nil)
                    // A grid that avoids landing exactly on edges.
                    for x in stride(from: 0.37, to: 480, by: 23) {
                        for y in stride(from: 0.41, to: 900, by: 23) {
                            let p = ScenePoint(x: x, y: y)
                            let expected = bruteForce(list, p)
                            if expected != nil { hits += 1 }
                            XCTAssertEqual(
                                layout.hitTest(point: p, camera: camera, viewport: viewport),
                                expected, "\(p), \(camera)")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(hits, 1000, "the grid has to land on layers to mean anything")
    }

    func test_C_SCENE_05_theTestOfFourCornersAgreesWithTheTestOfThePolygon() {
        func corners(_ points: [(Double, Double)]) -> Corners<ScenePoint> {
            let p = points.map { ScenePoint(x: $0.0, y: $0.1) }
            return Corners(p[0], p[1], p[2], p[3])
        }
        // Top left, top right, bottom left, bottom right.
        let quads = [
            corners([(10, 10), (90, 10), (10, 60), (90, 60)]),
            corners([(50, 0), (100, 50), (0, 50), (50, 100)]),  // turned
            corners([(90, 10), (10, 10), (90, 60), (10, 60)]),  // mirrored
            corners([(20, 10), (80, 30), (10, 70), (95, 90)]),  // in perspective
            corners([(10, 10), (90, 10), (10, 10), (90, 10)]),  // without area
            corners([(0, 0), (1e7, 0), (0, 1e-9), (1e7, 1e-9)]),  // a sliver
        ]
        var points: [ScenePoint] = []
        for x in stride(from: -5.0, through: 105, by: 2.5) {
            for y in stride(from: -5.0, through: 105, by: 2.5) {
                points.append(ScenePoint(x: x, y: y))
            }
        }
        var inside = 0
        for quad in quads {
            // Exactly on the corners and the middles of the edges too.
            let outline = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
            var tried = points + outline
            for i in 0..<4 {
                let p = outline[i], q = outline[(i + 1) % 4]
                tried.append(ScenePoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2))
            }
            for point in tried {
                let expected = Polygon.contains(outline, point)
                if expected { inside += 1 }
                XCTAssertEqual(Polygon.contains(quad, point), expected, "\(point) in \(quad)")
            }
        }
        XCTAssertGreaterThan(inside, 500, "the points have to land inside to mean anything")
    }

    /// Found in review: summed in another order, the area of a nearly flat quad at large
    /// coordinates came out otherwise, and a point the polygon test held was turned away; a
    /// point that is not a number, or a corner that is infinite, gave another answer too.
    /// The test of four corners now gives the polygon test's answer, bit for bit.
    func test_C_SCENE_05_theTestOfFourCornersGivesThePolygonsAnswerAtTheEdgesOfArithmetic() {
        let far = ScenePoint(x: -372416, y: 263151)
        let quads = [
            Corners(ScenePoint(x: -4.6e-13, y: 0), ScenePoint(x: 0, y: 0), far, far),
            Corners(
                ScenePoint(x: 0, y: 0), ScenePoint(x: .infinity, y: 0), ScenePoint(x: 0, y: 10),
                ScenePoint(x: 10, y: 10)),
            Corners(
                ScenePoint(x: 10, y: 10), ScenePoint(x: 90, y: 10), ScenePoint(x: 10, y: 60),
                ScenePoint(x: 90, y: 60)),
        ]
        var random = SystemRandomNumberGenerator()
        for quad in quads {
            let outline = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
            var tried = outline + [
                ScenePoint(x: .nan, y: 0), ScenePoint(x: 5, y: .nan), ScenePoint(x: .nan, y: .nan),
                ScenePoint(x: -1e9, y: .nan),
            ]
            for _ in 0..<2000 {
                let a = outline[Int.random(in: 0..<4, using: &random)]
                let b = outline[Int.random(in: 0..<4, using: &random)]
                let t = Double.random(in: -0.1...1.1, using: &random)
                tried.append(ScenePoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y)))
            }
            for point in tried {
                XCTAssertEqual(
                    Polygon.contains(quad, point), Polygon.contains(outline, point),
                    "\(point) in \(quad)")
            }
        }
    }
}
