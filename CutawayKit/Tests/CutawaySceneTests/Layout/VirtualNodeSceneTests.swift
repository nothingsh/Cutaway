import CutawayTestSupport
import XCTest

@testable import CutawayScene

/// Virtual nodes are placed, levelled and hit as layers are (C-SCENE-13): in the `hierarchy`
/// fixture the card, node 4, draws two rows, 10 and 12, and a badge, 11, inside row 10; they
/// come before the card's sublayer 5 (P-HIER-21).
final class VirtualNodeSceneTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)

    /// The fourteen nodes, with the card's sublayer 5 shown so that it overlaps the rows.
    private func layout() throws -> SceneLayout {
        var layers = try SceneInput.hierarchyFixture()
        let five = try XCTUnwrap(layers.firstIndex { $0.id == 5 })
        layers[five].isHidden = false
        return SceneLayout(layers: layers, expanded: Set(layers.map(\.id)))
    }

    func test_C_SCENE_13_virtualNodesAreConvertedAsTheFixtureSays() throws {
        let layout = try layout()
        // Worked out apart from the code: the rows and the badge in the card's coordinates,
        // (0, 0, 300, 40), (250, 10, 40, 20) through row 10, and (0, 40, 300, 80), then through
        // the card's turn of 30° about its centre, at (196.5, 300) in the window.
        let reference: [UInt64: [(Double, Double)]] = [
            10: [
                (111.5961894323342, 147.05771365940052), (371.4038105676658, 297.0577136594005),
                (91.5961894323342, 181.69872981077805), (351.4038105676658, 331.69872981077805),
            ],
            11: [
                (323.1025403784439, 280.7179676972449), (357.74355652982143, 300.7179676972449),
                (313.1025403784439, 298.0384757729337), (347.74355652982143, 318.0384757729337),
            ],
            12: [
                (91.5961894323342, 181.69872981077805), (351.4038105676658, 331.69872981077805),
                (71.5961894323342, 216.33974596215563), (331.4038105676658, 366.33974596215563),
            ],
        ]
        for (id, corners) in reference {
            let quad = try XCTUnwrap(layout.quad(of: id), "node \(id)")
            let actual = [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight]
            for (index, (point, expected)) in zip(actual, corners).enumerated() {
                XCTAssertEqual(point.x, expected.0, accuracy: 1e-6, "node \(id) corner \(index)")
                XCTAssertEqual(point.y, expected.1, accuracy: 1e-6, "node \(id) corner \(index)")
            }
        }
    }

    /// A point given in the card's own coordinates, in the viewport under the flat camera: the
    /// card's projected corners are an affine image of its bounds.
    private func cardPoint(_ x: Double, _ y: Double, in list: DrawList) throws -> ScenePoint {
        let card = try XCTUnwrap(list.items.first { $0.layerID == 4 }).points
        let (u, v) = (x / 300, y / 180)
        return ScenePoint(
            x: card[0].x + (card[1].x - card[0].x) * u + (card[2].x - card[0].x) * v,
            y: card[0].y + (card[1].y - card[0].y) * u + (card[2].y - card[0].y) * v)
    }

    private func hit(_ x: Double, _ y: Double) throws -> UInt64? {
        let layout = try layout()
        let list = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        return layout.hitTest(
            point: try cardPoint(x, y, in: list), camera: .flat, viewport: viewport)
    }

    func test_C_SCENE_13_aPointInAVirtualNodeOutsideEverySublayerHitsIt() throws {
        XCTAssertEqual(try hit(120, 20), 10)
        XCTAssertEqual(try hit(120, 60), 12)
        XCTAssertEqual(try hit(270, 20), 11, "the badge inside row 10")
        XCTAssertEqual(try hit(120, 130), 4, "the card outside its rows")
    }

    func test_C_SCENE_13_aPointWhereASublayerOverlapsHitsTheSublayer() throws {
        // The card's sublayer 5 is (20, 20, 40, 40): over the end of both rows.
        XCTAssertEqual(try hit(40, 30), 5)
        XCTAssertEqual(try hit(40, 50), 5)
    }

    func test_C_SCENE_13_inThreeDAVirtualNodesLevelIsBetweenItsParentAndTheFirstSublayer() throws {
        let layout = try layout()
        let card = try XCTUnwrap(layout.level(of: 4))
        let rows = try [10, 12].map { try XCTUnwrap(layout.level(of: $0)) }
        let badge = try XCTUnwrap(layout.level(of: 11))
        let sublayer = try XCTUnwrap(layout.level(of: 5))
        XCTAssertEqual(rows, [card + 1, card + 1], "the rows do not overlap each other")
        XCTAssertEqual(badge, card + 2)
        XCTAssertEqual(sublayer, card + 2, "above both rows it overlaps")
        XCTAssertGreaterThan(sublayer, rows[0])
    }

    func test_C_SCENE_13_hiddenVirtualNodesAreNotDrawnNorHit() throws {
        var layers = try SceneInput.hierarchyFixture()
        let twelve = try XCTUnwrap(layers.firstIndex { $0.id == 12 })
        layers[twelve].isHidden = true
        let layout = SceneLayout(layers: layers, expanded: Set(layers.map(\.id)))
        XCTAssertFalse(layout.isDisplayed(12))
        let list = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(
            layout.hitTest(point: try cardPoint(120, 60, in: list), camera: .flat, viewport: viewport),
            4)
    }
}
