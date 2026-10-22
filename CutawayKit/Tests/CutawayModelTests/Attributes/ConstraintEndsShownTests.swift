import CutawayScene
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel

/// Which ends of the selected view's constraints the preview marks, and which of them it
/// stresses: all of them with the switch on, otherwise only those of the constraints the
/// pointer is on (C-LAYOUT-04, C-LAYOUT-06, C-LAYOUT-07, C-PREV-18).
final class ConstraintEndsShownTests: XCTestCase {
    private func shown(
        of id: UInt64, showsAll: Bool, pointing: ConstraintPointing? = nil,
        chip: SceneMark? = nil
    ) throws -> ConstraintEnd.Shown {
        ConstraintEnd.shown(
            of: try Fixtures.constraints(of: id), selected: id, showsAll: showsAll,
            pointing: pointing, chip: chip)
    }

    func test_C_LAYOUT_07_theFoldedUIKitRowMarksItsEndsOncePlainly() throws {
        let indices = Array(try Fixtures.constraints(of: 9).indices)
        let shown = try shown(
            of: 9, showsAll: false, pointing: ConstraintPointing(indices, stresses: false))
        XCTAssertEqual(shown.ends.map(\.mark), [.layer(2)])
        XCTAssertEqual(shown.stressed, [])
    }

    func test_C_LAYOUT_07_aRowWithoutAnOtherEndMarksNothing() {
        let constraint = LayoutConstraint(
            id: 1, className: "NSLayoutConstraint", identifier: nil, firstItem: .view(layerID: 3),
            firstAttribute: .width, relation: .equal, secondItem: nil,
            secondAttribute: .notAnAttribute, multiplier: 1, constant: 30, priority: 1000,
            status: .satisfied)
        let shown = ConstraintEnd.shown(
            of: [constraint], selected: 3, showsAll: false, pointing: ConstraintPointing([0]),
            chip: nil)
        XCTAssertEqual(shown.ends, [])
    }

    func test_C_LAYOUT_07_rowsThatAreNotThereMarkNothing() throws {
        let shown = try shown(of: 3, showsAll: false, pointing: ConstraintPointing([7]))
        XCTAssertEqual(shown.ends, [])
    }

    func test_C_LAYOUT_06_aChipStressesItsEndOnlyWithTheSwitchOffOrOn() throws {
        for showsAll in [false, true] {
            let shown = try shown(
                of: 3, showsAll: showsAll, pointing: ConstraintPointing([3]), chip: .layer(4))
            XCTAssertEqual(shown.stressed, [.layer(4)], "showsAll \(showsAll)")
            XCTAssertTrue(shown.ends.contains { $0.mark == .layer(4) })
        }
    }

    func test_C_LAYOUT_06_aChipThatIsNotAnEndIsNotShown() throws {
        let shown = try shown(of: 3, showsAll: false, chip: .layer(9))
        XCTAssertEqual(shown.ends, [])
        XCTAssertEqual(shown.stressed, [])
    }
}
