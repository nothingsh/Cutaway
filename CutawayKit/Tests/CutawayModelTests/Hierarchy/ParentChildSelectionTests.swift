import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// Selecting the selected layer's parent (⌘↑) and first child (⌘↓), on the `hierarchy`
/// fixture (C-ATTR-16).
@MainActor
final class ParentChildSelectionTests: XCTestCase {
    /// A model showing the `hierarchy` fixture, with no connection behind it.
    private func model() throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(
                channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")),
            newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        return model
    }

    func test_C_ATTR_16_theParentAndTheFirstChildAreSelected() throws {
        let model = try model()
        model.select(5)
        XCTAssertEqual(model.selectedParentID, 4)
        model.selectParent()
        XCTAssertEqual(model.selectedLayerID, 4)
        model.selectParent()
        XCTAssertEqual(model.selectedLayerID, 2)
        // The first child as the list shows it: the first on the wire.
        XCTAssertEqual(model.selectedFirstChildID, 3)
        model.selectFirstChild()
        XCTAssertEqual(model.selectedLayerID, 3)
    }

    func test_C_ATTR_16_aRootHasNoParentAndALeafNoChild() throws {
        let model = try model()
        XCTAssertNil(model.selectedParentID, "nothing is selected")
        XCTAssertNil(model.selectedFirstChildID)
        model.select(1)
        XCTAssertNil(model.selectedParentID)
        model.selectParent()
        XCTAssertEqual(model.selectedLayerID, 1)
        model.select(3)
        XCTAssertNil(model.selectedFirstChildID)
        model.selectFirstChild()
        XCTAssertEqual(model.selectedLayerID, 3)
    }

    func test_C_ATTR_16_aCollapsedLayerOpensForItsFirstChild() throws {
        let model = try model()
        model.setExpanded(6, false)
        model.select(6)
        model.selectFirstChild()
        XCTAssertEqual(model.selectedLayerID, 7)
        XCTAssertTrue(model.isExpanded(6))
    }

    func test_C_ATTR_16_theParentOfTheFocusLeavesTheFocus() throws {
        let model = try model()
        model.focus(on: 6)
        model.select(6)
        model.selectParent()
        XCTAssertNil(model.focusedLayerID)
        XCTAssertEqual(model.selectedLayerID, 2)
    }

    func test_C_ATTR_16_underASearchTheFirstChildIsOneItKeeps() throws {
        let model = try model()
        model.setSearchText("label")
        model.select(2)
        // 3 and 6 are kept under 2, 4 is not.
        XCTAssertEqual(model.selectedFirstChildID, 3)
        model.select(4)
        XCTAssertNil(model.selectedFirstChildID, "the search keeps none of its children")
    }
}
