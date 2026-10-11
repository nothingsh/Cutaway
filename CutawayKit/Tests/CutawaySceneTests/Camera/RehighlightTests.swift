import CutawayScene
import XCTest

/// A new selection or hover on a list already projected: the list highlighted again is the
/// one a new projection gives (C-PREV-01, C-PREV-03).
final class RehighlightTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)
    private let ids: [UInt64?] = [nil, 2, 3, 4, 8, 5, 42]

    private func fixtureLayout() throws -> SceneLayout {
        SceneLayout(layers: try SceneFixtures.hierarchyLayers(), expanded: SceneFixtures.allIDs)
    }

    /// For every camera and every change from one pair to another, the list highlighted
    /// again equals the projection with the new pair. Marks are kept as they were.
    private func assertRehighlighting(
        from old: (selected: UInt64?, hovered: UInt64?),
        to new: [(selected: UInt64?, hovered: UInt64?)], layout: SceneLayout,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let marks: [SceneMark] = [.layer(4), .layer(8)]
        for camera in [Camera.flat, .standard3D] {
            let before = layout.project(
                camera: camera, viewport: viewport, selected: old.selected, hovered: old.hovered,
                marks: marks)
            for pair in new {
                let expected = layout.project(
                    camera: camera, viewport: viewport, selected: pair.selected,
                    hovered: pair.hovered, marks: marks)
                XCTAssertEqual(
                    before.rehighlighting(selected: pair.selected, hovered: pair.hovered),
                    expected, "\(old) to \(pair), \(camera)", file: file, line: line)
            }
        }
    }

    func test_C_PREV_03_aNewHoverOnAProjectedListIsTheProjectionWithIt() throws {
        let layout = try fixtureLayout()
        for selected in ids {
            for hovered in ids {
                assertRehighlighting(
                    from: (selected, hovered), to: ids.map { (selected, $0) }, layout: layout)
            }
        }
    }

    func test_C_PREV_01_aNewSelectionOnAProjectedListIsTheProjectionWithIt() throws {
        let layout = try fixtureLayout()
        for selected in ids {
            for hovered in ids {
                assertRehighlighting(
                    from: (selected, hovered), to: ids.map { ($0, hovered) }, layout: layout)
            }
        }
    }

    func test_C_PREV_03_theSameHighlightsGiveTheSameList() throws {
        let list = try fixtureLayout().project(
            camera: .standard3D, viewport: viewport, selected: 3, hovered: 8)
        XCTAssertEqual(list.rehighlighting(selected: 3, hovered: 8), list)
        XCTAssertEqual(DrawList.empty.rehighlighting(selected: 3, hovered: 8), .empty)
    }
}
