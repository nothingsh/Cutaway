import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// Which of an inspector window's commands can be used, without the window: C-DET-05,
/// C-DET-07, C-ARCH-02, C-ARCH-05, C-ARCH-06, C-HIER-04 to C-HIER-06, C-WIN-03.
final class InspectorCommandsTests: XCTestCase {
    /// A live inspection whose session never connected, with the fixtures' tree.
    @MainActor
    private func model() throws -> InspectionStore {
        let session = Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        let model = InspectionStore(session: session)
        model.apply(try Fixtures.hierarchy())
        return model
    }

    @MainActor
    private func commands(
        _ model: InspectionStore, archive: Bool = false, disconnected: Bool = false
    ) -> InspectorCommands {
        InspectorCommands(store: model, isArchive: archive, isDisconnected: disconnected)
    }

    @MainActor
    func test_C_DET_05_refreshingNeedsTheConnection() throws {
        let model = try model()
        XCTAssertTrue(commands(model).canAskTheApp)
        XCTAssertTrue(commands(model).canRefresh)
        XCTAssertFalse(commands(model, disconnected: true).canRefresh)
    }

    @MainActor
    func test_C_ARCH_02_savingNeedsTheConnection() throws {
        let model = try model()
        XCTAssertTrue(commands(model).canSaveArchive)
        XCTAssertFalse(commands(model, disconnected: true).canSaveArchive)
    }

    @MainActor
    func test_C_ARCH_05_anArchiveIsNeitherRefreshedNorSaved() throws {
        let model = try model()
        model.canRefreshSubtrees = true
        model.select(4)
        let archive = commands(model, archive: true)
        XCTAssertFalse(archive.canAskTheApp)
        XCTAssertFalse(archive.canRefresh)
        XCTAssertFalse(archive.canRefreshSelectedSubtree)
        XCTAssertFalse(archive.canSaveArchive)
        XCTAssertTrue(archive.canChangePreview)
        XCTAssertTrue(archive.canFindLayer)
    }

    @MainActor
    func test_C_DET_07_aSubtreeIsRefreshedFromTheSelectedLayer() throws {
        let model = try model()
        model.select(4)
        XCTAssertFalse(commands(model).canRefreshSelectedSubtree, "a source that sends no subtrees")
        model.canRefreshSubtrees = true
        XCTAssertTrue(commands(model).canRefreshSelectedSubtree)
        model.select(nil)
        XCTAssertFalse(commands(model).canRefreshSelectedSubtree, "nothing selected")
        model.select(4)
        XCTAssertFalse(commands(model, disconnected: true).canRefreshSelectedSubtree)
    }

    @MainActor
    func test_C_ARCH_06_aLayerInTheTreeCanBeExported() throws {
        let model = try model()
        XCTAssertTrue(commands(model).canExport(.solo, of: 4))
        XCTAssertTrue(commands(model).canExport(.group, of: 4))
        XCTAssertFalse(commands(model).canExport(.solo, of: nil), "no layer")
        XCTAssertFalse(commands(model).canExport(.solo, of: 999), "not in the tree")
        XCTAssertFalse(commands(model, disconnected: true).canExport(.solo, of: 4))
    }

    @MainActor
    func test_C_HIER_04_findNeedsTheLayers() throws {
        let session = Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        let empty = InspectionStore(session: session)
        XCTAssertFalse(commands(empty).canFindLayer, "not loaded")
        let model = try model()
        XCTAssertTrue(commands(model).canFindLayer)
        XCTAssertFalse(commands(model, disconnected: true).canFindLayer)
    }

    @MainActor
    func test_C_HIER_05_focusNeedsASelectionAndShowAllAFocus() throws {
        let model = try model()
        XCTAssertFalse(commands(model).canFocusOnSelectedLayer, "nothing selected")
        XCTAssertFalse(commands(model).canShowAllLayers, "no focus")
        model.select(4)
        XCTAssertTrue(commands(model).canFocusOnSelectedLayer)
        model.focus(on: 4)
        XCTAssertFalse(commands(model).canFocusOnSelectedLayer, "focused on it already")
        XCTAssertTrue(commands(model).canShowAllLayers)
        XCTAssertFalse(commands(model, disconnected: true).canShowAllLayers)
    }

    @MainActor
    func test_C_HIER_06_expandingAndCollapsingAllNeedLayersAndNoSearch() throws {
        let model = try model()
        XCTAssertTrue(commands(model).canExpandOrCollapseAll)
        model.setSearchText("label")
        XCTAssertFalse(commands(model).canExpandOrCollapseAll, "not during a search")
        model.setSearchText("")
        XCTAssertTrue(commands(model).canExpandOrCollapseAll)
        XCTAssertFalse(commands(model, disconnected: true).canExpandOrCollapseAll)
    }

    @MainActor
    func test_C_ATTR_16_parentAndChildNeedTheConnectionAndNoTextBeingEdited() throws {
        let model = try model()
        model.select(4)
        XCTAssertTrue(commands(model).canSelectParent)
        XCTAssertTrue(commands(model).canSelectFirstChild)
        XCTAssertFalse(commands(model, disconnected: true).canSelectParent)
        XCTAssertFalse(commands(model, disconnected: true).canSelectFirstChild)
        let editing = InspectorCommands(store: model, isArchive: false, isDisconnected: false, isEditingText: true)
        XCTAssertFalse(editing.canSelectParent)
        XCTAssertFalse(editing.canSelectFirstChild)
        XCTAssertTrue(commands(model, archive: true).canSelectParent, "an archive too")
    }
}
