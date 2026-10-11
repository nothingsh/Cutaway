import CutawayScene
import XCTest

/// Where a layout guide is (C-SCENE-08) and the marks on the other ends of the selected
/// layer's constraints (C-LAYOUT-04).
final class ConstraintEndTests: XCTestCase {
    /// The safe area of layer 2 in the `layout-constraints` fixture.
    private static let safeArea = SceneRect(x: 0, y: 59, width: 393, height: 759)
    private static let portrait = Viewport(width: 480, height: 900)

    private func fixtureLayout(
        expanded: Set<UInt64> = SceneFixtures.allIDs, focus: UInt64? = nil,
        showsHidden: Bool = false
    ) throws -> SceneLayout {
        SceneLayout(
            layers: try SceneFixtures.hierarchyLayers(), expanded: expanded, focus: focus,
            showsHidden: showsHidden)
    }

    private func corners(_ quad: Quad) -> [ScenePoint] {
        [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight]
    }

    private func assertClose(
        _ actual: some Collection<ScenePoint>, _ expected: some Collection<ScenePoint>,
        _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, message, file: file, line: line)
        for (index, (a, e)) in zip(actual, expected).enumerated() {
            XCTAssertEqual(a.x, e.x, accuracy: 1e-6, "\(message) corner \(index)", file: file, line: line)
            XCTAssertEqual(a.y, e.y, accuracy: 1e-6, "\(message) corner \(index)", file: file, line: line)
        }
    }

    private func assertClose(
        _ actual: some Collection<ClipPoint>, _ expected: some Collection<ClipPoint>,
        _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, message, file: file, line: line)
        for (index, (a, e)) in zip(actual, expected).enumerated() {
            for (x, y) in [(a.x, e.x), (a.y, e.y), (a.z, e.z), (a.w, e.w)] {
                XCTAssertEqual(x, y, accuracy: 1e-9, "\(message) corner \(index)", file: file, line: line)
            }
        }
    }

    /// A point of `rect`, in the layer's bounds, placed by interpolating the layer's four
    /// corners: an affine map takes the bounds' corners to them.
    private func interpolated(
        _ x: Double, _ y: Double, in bounds: SceneRect, _ quad: Quad
    ) -> ScenePoint {
        let u = (x - bounds.minX) / bounds.size.width
        let v = (y - bounds.minY) / bounds.size.height
        return ScenePoint(
            x: quad.topLeft.x + u * (quad.topRight.x - quad.topLeft.x)
                + v * (quad.bottomLeft.x - quad.topLeft.x),
            y: quad.topLeft.y + u * (quad.topRight.y - quad.topLeft.y)
                + v * (quad.bottomLeft.y - quad.topLeft.y))
    }

    private func interpolatedCorners(
        of rect: SceneRect, in bounds: SceneRect, _ quad: Quad
    ) -> [ScenePoint] {
        [
            interpolated(rect.minX, rect.minY, in: bounds, quad),
            interpolated(rect.maxX, rect.minY, in: bounds, quad),
            interpolated(rect.minX, rect.maxY, in: bounds, quad),
            interpolated(rect.maxX, rect.maxY, in: bounds, quad),
        ]
    }

    // MARK: - C-SCENE-08: where a layout guide is

    func test_C_SCENE_08_theSafeAreaOfLayer2HasTheFixturesCorners() throws {
        let quad = try XCTUnwrap(try fixtureLayout().quad(of: Self.safeArea, in: 2))
        assertClose(
            corners(quad),
            [
                ScenePoint(x: 0, y: 59), ScenePoint(x: 393, y: 59), ScenePoint(x: 0, y: 818),
                ScenePoint(x: 393, y: 818),
            ],
            "safe area")
    }

    func test_C_SCENE_08_aGuideOnARotatedLayerFollowsTheLayersTransform() throws {
        let layout = try fixtureLayout()
        let layer4 = try XCTUnwrap(layout.quad(of: 4))
        let bounds = SceneRect(x: 0, y: 0, width: 300, height: 180)
        let quad = try XCTUnwrap(layout.quad(of: Self.safeArea, in: 4))
        assertClose(
            corners(quad), interpolatedCorners(of: Self.safeArea, in: bounds, layer4),
            "safe area on layer 4")
    }

    func test_C_SCENE_08_aGuideOnAScrolledLayerCountsItsBoundsOrigin() throws {
        let layout = try fixtureLayout()
        // Layer 6 is scrolled down by 100 points: its bounds start at (0, 100).
        let layer6 = try XCTUnwrap(layout.quad(of: 6))
        let bounds = SceneRect(x: 0, y: 100, width: 300, height: 200)
        let guide = SceneRect(x: 10, y: 120, width: 50, height: 20)
        let quad = try XCTUnwrap(layout.quad(of: guide, in: 6))
        assertClose(
            corners(quad), interpolatedCorners(of: guide, in: bounds, layer6), "guide on layer 6")
        // The visible top of layer 6 is bounds y 100, so y 120 is 20 points below it.
        XCTAssertEqual(quad.topLeft.y, layer6.topLeft.y + 20, accuracy: 1e-6)
    }

    func test_C_SCENE_08_aGuideOfAnUnknownLayerHasNoCorners() throws {
        XCTAssertNil(try fixtureLayout().quad(of: Self.safeArea, in: 99))
    }

    // MARK: - C-LAYOUT-04: the marks

    func test_C_LAYOUT_04_in2DALayersMarkHasTheLayersCornersAndAGuidesFollowsItsOwner() throws {
        let list = try fixtureLayout().project(
            camera: .flat, viewport: Self.portrait, selected: 3, hovered: nil,
            marks: [.layer(4), .area(Self.safeArea, in: 2)])
        XCTAssertEqual(list.marks.map(\.mark), [.layer(4), .area(Self.safeArea, in: 2)])
        let item4 = try XCTUnwrap(list.items.first { $0.layerID == 4 })
        XCTAssertEqual(list.marks[0].points, item4.points)
        XCTAssertEqual(list.marks[0].corners, item4.corners)

        // Layer 2 fills the window, so its drawn corners place every window point.
        let item2 = try XCTUnwrap(list.items.first { $0.layerID == 2 })
        let drawn2 = Quad(
            topLeft: item2.points[0], topRight: item2.points[1], bottomLeft: item2.points[2],
            bottomRight: item2.points[3])
        assertClose(
            list.marks[1].points,
            interpolatedCorners(
                of: Self.safeArea, in: SceneRect(x: 0, y: 0, width: 393, height: 852), drawn2),
            "safe area")
    }

    func test_C_LAYOUT_04_in3DAMarkIsOnTheLevelOfItsLayer() throws {
        let list = try fixtureLayout().project(
            camera: .standard3D, viewport: Self.portrait, selected: 3, hovered: nil,
            marks: [.layer(4), .area(SceneRect(x: 0, y: 0, width: 393, height: 852), in: 2)])
        let item4 = try XCTUnwrap(list.items.first { $0.layerID == 4 })
        let item2 = try XCTUnwrap(list.items.first { $0.layerID == 2 })
        XCTAssertEqual(list.marks.count, 2)
        assertClose(list.marks[0].corners, item4.corners, "layer 4")
        assertClose(list.marks[1].corners, item2.corners, "bounds of layer 2")
        assertClose(list.marks[1].points, item2.points, "bounds of layer 2")
    }

    func test_C_LAYOUT_04_aHiddenLayerIsMarkedOnlyWhenHiddenLayersAreShown() throws {
        // Layer 5 is hidden.
        let hidden = try fixtureLayout().project(
            camera: .flat, viewport: Self.portrait, selected: 3, hovered: nil,
            marks: [.layer(5), .area(Self.safeArea, in: 5)])
        XCTAssertEqual(hidden.marks, [])
        let shown = try fixtureLayout(showsHidden: true).project(
            camera: .flat, viewport: Self.portrait, selected: 3, hovered: nil,
            marks: [.layer(5)])
        let item5 = try XCTUnwrap(shown.items.first { $0.layerID == 5 })
        XCTAssertEqual(shown.marks.map(\.points), [item5.points])
    }

    func test_C_LAYOUT_04_aLayerOutsideTheFocusIsNotMarked() throws {
        let list = try fixtureLayout(focus: 4, showsHidden: true).project(
            camera: .flat, viewport: Self.portrait, selected: 4, hovered: nil,
            marks: [.layer(2), .area(Self.safeArea, in: 2), .layer(5)])
        XCTAssertEqual(list.marks.map(\.mark), [.layer(5)])
    }

    func test_C_LAYOUT_04_aLayerInsideACollapsedNodeIsMarkedWhereItIsOnTheNodesLevel() throws {
        var expanded = SceneFixtures.allIDs
        expanded.remove(4)
        let layout = try fixtureLayout(expanded: expanded, showsHidden: true)
        XCTAssertFalse(layout.isDisplayed(5))
        // Layer 5 (40 by 40 about (40, 40)) is the rectangle (20, 20, 40, 40) of layer 4's
        // bounds; as an area of layer 4 it is on layer 4's level.
        let list = layout.project(
            camera: .standard3D, viewport: Self.portrait, selected: 3, hovered: nil,
            marks: [.layer(5), .area(SceneRect(x: 20, y: 20, width: 40, height: 40), in: 4)])
        XCTAssertEqual(list.marks.count, 2)
        assertClose(list.marks[0].corners, list.marks[1].corners, "layer 5")
    }

    func test_C_LAYOUT_04_marksKeepTheirOrderAndUnknownLayersAreLeftOut() throws {
        let list = try fixtureLayout().project(
            camera: .flat, viewport: Self.portrait, selected: 3, hovered: nil,
            marks: [.layer(4), .layer(99), .area(Self.safeArea, in: 99), .layer(2)])
        XCTAssertEqual(list.marks.map(\.mark), [.layer(4), .layer(2)])
    }

    func test_C_LAYOUT_04_marksChangeNeitherTheLayersNorWhatIsHit() throws {
        let layout = try fixtureLayout()
        for camera in [Camera.flat, .standard3D] {
            let plain = layout.project(
                camera: camera, viewport: Self.portrait, selected: 3, hovered: 6)
            let marked = layout.project(
                camera: camera, viewport: Self.portrait, selected: 3, hovered: 6,
                marks: [.layer(4), .area(SceneRect(x: -500, y: -500, width: 2000, height: 2000), in: 2)])
            XCTAssertEqual(marked.items, plain.items, "\(camera)")
            XCTAssertEqual(plain.marks, [])
            let point = try XCTUnwrap(plain.items.first { $0.layerID == 3 }).center
            XCTAssertEqual(marked.layer(at: point), plain.layer(at: point))
        }
    }
}
