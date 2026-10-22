import XCTest

@testable import CutawayScene

/// Laying the layers out again keeps the earlier layout's levels when the displayed layers
/// and their places are the same (C-SCENE-02 depends on nothing else), and finds them again
/// otherwise. Either way the layout is the one laying out from nothing gives.
final class LevelReuseTests: XCTestCase {
    /// 1 holds 2, 3 and 4; 2 and 3 overlap, 4 is beside them; 3 holds 5.
    private func layers() -> [SceneLayer] {
        func layer(_ id: UInt64, _ parent: UInt64, x: Double, y: Double, size: Double) -> SceneLayer {
            SceneLayer(
                id: id, parentID: parent,
                bounds: SceneRect(x: 0, y: 0, width: size, height: size),
                position: ScenePoint(x: x, y: y), anchorPoint: ScenePoint(x: 0, y: 0))
        }
        return [
            layer(1, 0, x: 0, y: 0, size: 400),
            layer(2, 1, x: 10, y: 10, size: 100),
            layer(3, 1, x: 50, y: 50, size: 100),
            layer(4, 1, x: 300, y: 300, size: 50),
            layer(5, 3, x: 10, y: 10, size: 20),
        ]
    }

    private let everything: Set<UInt64> = [1, 2, 3, 4, 5]

    /// What the two layouts show: each layer's level, opacity and look, the draw order and
    /// the content box.
    private func assertSame(
        _ layout: SceneLayout, _ expected: SceneLayout, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(layout.entries.map(\.level), expected.entries.map(\.level), file: file, line: line)
        XCTAssertEqual(layout.entries.map(\.opacity), expected.entries.map(\.opacity), file: file, line: line)
        XCTAssertEqual(layout.entries.map(\.isGhost), expected.entries.map(\.isGhost), file: file, line: line)
        XCTAssertEqual(layout.entries.map(\.layer), expected.entries.map(\.layer), file: file, line: line)
        XCTAssertEqual(layout.displayed, expected.displayed, file: file, line: line)
        XCTAssertEqual(layout.drawOrder, expected.drawOrder, file: file, line: line)
        XCTAssertEqual(layout.levelRanges, expected.levelRanges, file: file, line: line)
        XCTAssertEqual(layout.contentBox, expected.contentBox, file: file, line: line)
        XCTAssertEqual(layout.neededTextures, expected.neededTextures, file: file, line: line)
    }

    func test_C_SCENE_02_anotherOpacityKeepsTheLevels() {
        let earlier = SceneLayout(layers: layers(), expanded: everything)
        var changed = layers()
        changed[2].opacity = 0.25
        changed[4].opacity = 0
        let layout = SceneLayout(layers: changed, expanded: everything, keepingLevelsOf: earlier)
        XCTAssertTrue(layout.keptLevels)
        assertSame(layout, SceneLayout(layers: changed, expanded: everything))
        XCTAssertEqual(layout.entries[4].opacity, 0)
    }

    func test_C_SCENE_02_aMovedLayerHasItsLevelsFoundAgain() {
        let earlier = SceneLayout(layers: layers(), expanded: everything)
        var moved = layers()
        // 4 now overlaps 3, so it goes up a level.
        moved[3].position = ScenePoint(x: 60, y: 60)
        let layout = SceneLayout(layers: moved, expanded: everything, keepingLevelsOf: earlier)
        XCTAssertFalse(layout.keptLevels)
        assertSame(layout, SceneLayout(layers: moved, expanded: everything))
        XCTAssertNotEqual(layout.entries[3].level, earlier.entries[3].level)
    }

    func test_C_SCENE_02_otherDisplayedLayersHaveTheirLevelsFoundAgain() {
        let earlier = SceneLayout(layers: layers(), expanded: everything)
        var hidden = layers()
        hidden[1].isHidden = true
        let cases: [(String, SceneLayout, SceneLayout)] = [
            ("collapsed", SceneLayout(layers: layers(), expanded: [1, 2, 4, 5], keepingLevelsOf: earlier),
             SceneLayout(layers: layers(), expanded: [1, 2, 4, 5])),
            ("focused", SceneLayout(layers: layers(), expanded: everything, focus: 3, keepingLevelsOf: earlier),
             SceneLayout(layers: layers(), expanded: everything, focus: 3)),
            ("hidden", SceneLayout(layers: hidden, expanded: everything, keepingLevelsOf: earlier),
             SceneLayout(layers: hidden, expanded: everything)),
        ]
        for (name, layout, fresh) in cases {
            XCTAssertFalse(layout.keptLevels, name)
            assertSame(layout, fresh)
        }
    }

    func test_C_SCENE_02_aLayerThatLosesItsAreaHasTheLevelsFoundAgain() {
        let earlier = SceneLayout(layers: layers(), expanded: everything)
        var flat = layers()
        flat[2].bounds = SceneRect(x: 0, y: 0, width: 100, height: 0)
        let layout = SceneLayout(layers: flat, expanded: everything, keepingLevelsOf: earlier)
        XCTAssertFalse(layout.keptLevels)
        assertSame(layout, SceneLayout(layers: flat, expanded: everything))
    }
}
