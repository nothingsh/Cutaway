import XCTest

@testable import CutawayScene

/// The ends the pointer is on in the attribute panel, a chip's or a row's: their marks
/// stressed, the others faded, without projecting again (C-LAYOUT-06, C-LAYOUT-07).
final class MarkEmphasisTests: XCTestCase {
    private let guide = SceneMark.area(SceneRect(x: 0, y: 59, width: 393, height: 759), in: 2)

    private func list() -> DrawList {
        let corners = Corners(
            ClipPoint(x: 0, y: 0, z: 0, w: 1), ClipPoint(x: 1, y: 0, z: 0, w: 1),
            ClipPoint(x: 0, y: 1, z: 0, w: 1), ClipPoint(x: 1, y: 1, z: 0, w: 1))
        let points = Corners(
            ScenePoint(x: 0, y: 0), ScenePoint(x: 1, y: 0), ScenePoint(x: 0, y: 1),
            ScenePoint(x: 1, y: 1))
        return DrawList(items: [], marks: [.layer(2), guide, .layer(4)].map {
            DrawMark(mark: $0, corners: corners, points: points)
        })
    }

    func test_C_LAYOUT_06_aViewsMarkIsStressedAndTheOthersFade() {
        let stressed = list().emphasizing([.layer(4)])
        XCTAssertEqual(stressed.marks.map(\.emphasis), [.faded, .faded, .emphasized])
        XCTAssertEqual(stressed.marks.map(\.points), list().marks.map(\.points), "nothing moved")
    }

    func test_C_LAYOUT_06_aGuidesMarkIsStressedByItsArea() {
        XCTAssertEqual(list().emphasizing([guide]).marks.map(\.emphasis), [.faded, .emphasized, .faded])
        // Another guide of the same owner is another mark.
        let other = SceneMark.area(SceneRect(x: 8, y: 59, width: 377, height: 759), in: 2)
        XCTAssertEqual(list().emphasizing([other]).marks.map(\.emphasis), [.plain, .plain, .plain])
    }

    func test_C_LAYOUT_06_noneStressedLeavesEveryMarkPlain() {
        let stressed = list().emphasizing([.layer(2)])
        XCTAssertEqual(stressed.emphasizing([]), list())
        XCTAssertEqual(list().emphasizing([.layer(9)]), list())
    }

    func test_C_LAYOUT_07_bothEndsOfAConstraintAreStressedTogether() {
        let stressed = list().emphasizing([.layer(4), guide])
        XCTAssertEqual(stressed.marks.map(\.emphasis), [.faded, .emphasized, .emphasized])
        // Ends the list does not have count for nothing.
        XCTAssertEqual(
            list().emphasizing([.layer(9), .layer(2)]).marks.map(\.emphasis),
            [.emphasized, .faded, .faded])
    }
}
