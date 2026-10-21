import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-HIER-16: a virtual node is a row like a layer's, titled by its name, of the Virtual
/// kind, found by its name; the inspector shows no address for it, and nothing that exports
/// a screenshot. In the `hierarchy` fixture, the card 4 draws the rows 10 "Total" and 12 "Tax",
/// and the badge 11 "New" inside row 10.
@MainActor
final class VirtualNodeRowTests: XCTestCase {
    private func tree(_ hierarchy: Hierarchy? = nil) throws -> LayerTree {
        try LayerTree(hierarchy ?? Fixtures.hierarchy())
    }

    func test_C_HIER_16_virtualRowsComeBeforeTheParentsSublayers() throws {
        let tree = try tree()
        XCTAssertEqual(tree.children(of: 4), [10, 12, 5])
        XCTAssertEqual(tree.children(of: 10), [11])
    }

    func test_C_HIER_16_aVirtualRowIsTitledByItsNameWithItsTypeAsTheDetail() throws {
        let tree = try tree()
        let rows = [10, 11, 12].map { HierarchyRow(tree, $0, filter: nil) }
        XCTAssertEqual(rows.map(\.title), ["Total", "New", "Tax"])
        XCTAssertEqual(rows.map(\.detail), ["CardRow", "CardBadge", "CardRow"])
        XCTAssertEqual(tree.shortTitle(of: 10), "Total", "the path and the tags say it too")
    }

    func test_C_HIER_16_withoutANameTheTypeIsTheTitleAndThereIsNoDetail() throws {
        var hierarchy = try Fixtures.hierarchy()
        let ten = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 10 })
        hierarchy.nodes[ten].name = nil
        let row = HierarchyRow(try tree(hierarchy), 10, filter: nil)
        XCTAssertEqual(row.title, "CardRow")
        XCTAssertNil(row.detail)
    }

    func test_C_HIER_16_aVirtualNodeIsOfTheVirtualKind() throws {
        let tree = try tree()
        for id: UInt64 in [10, 11, 12] {
            XCTAssertEqual(
                LayerIcon(tree.node(id)), LayerIcon(.virtual, .diamond, isAppClass: true),
                "node \(id)")
        }
        XCTAssertNotNil(LayerIconImage.glyph(.diamond))
        XCTAssertEqual(LayerIconImage.color(.virtual), .systemMint)
        // A 1.1 peer sends no kinds: a layer that backs no view, as before.
        let old = try self.tree(Fixtures.withoutProtocol12(Fixtures.hierarchy()))
        XCTAssertEqual(LayerIcon(old.node(10)).category, .layer)
    }

    func test_C_HIER_16_searchingFindsAVirtualNodeByName() throws {
        let tree = try tree()
        let filter = try XCTUnwrap(HierarchyFilter(text: "tax", tree: tree, within: nil))
        XCTAssertEqual(filter.matches, [12])
        XCTAssertEqual(filter.shown, [1, 2, 4, 12])
        XCTAssertEqual(HierarchyFilter(text: "TOT", tree: tree, within: nil)?.matches, [10])
    }

    func test_C_HIER_16_theObjectSectionHasNoAddressesForAVirtualNode() throws {
        let tree = try tree()
        let lines = IdentityLinesView(copy: { _ in })
        lines.show(LayerSummary(tree, 10))
        XCTAssertEqual(lines.lines.map(\.title.title), ["Virtual Node"])
        let identifiers = AppListViewTests.descendants(of: lines).map { $0.accessibilityIdentifier() }
        XCTAssertTrue(identifiers.contains(IdentityLinesView.classIdentifier))
        for absent in [
            IdentityLinesView.layerAddressIdentifier, IdentityLinesView.viewAddressIdentifier,
            IdentityLinesView.controllerIdentifier, IdentityLinesView.copyIdentifier,
        ] {
            XCTAssertFalse(identifiers.contains(absent), absent)
        }
        // A layer that backs no view keeps its line and its address.
        lines.show(LayerSummary(tree, 8))
        XCTAssertEqual(lines.lines.first?.title.title, "Layer")
        XCTAssertTrue(
            AppListViewTests.descendants(of: lines)
                .contains { $0.accessibilityIdentifier() == IdentityLinesView.layerAddressIdentifier })
    }

    func test_C_HIER_16_aVirtualNodeCannotBeExported() throws {
        let session = Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        let model = InspectionStore(session: session)
        model.apply(try Fixtures.hierarchy())
        let inspector = InspectorWindowController(
            location: .simulator(port: 48160), entry: nil, store: model)
        addTeardownBlock { @MainActor in inspector.close() }

        func enabled(_ action: Selector, _ id: UInt64) -> Bool {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.representedObject = id
            return inspector.validateMenuItem(item)
        }
        for action in [
            #selector(InspectorWindowController.exportLayerScreenshot(_:)),
            #selector(InspectorWindowController.exportScreenshotWithSublayers(_:)),
        ] {
            XCTAssertFalse(enabled(action, 10))
            XCTAssertFalse(enabled(action, 11))
            XCTAssertTrue(enabled(action, 4), "the layer that draws them can be")
        }

        let menu = NSMenu()
        LayerContextMenu(store: model).fill(menu, for: 10)
        XCTAssertFalse(menu.items.contains { $0.identifier == LLDBMenu.identifier }, "no address")
        XCTAssertFalse(menu.items.isEmpty)
        let layerMenu = NSMenu()
        LayerContextMenu(store: model).fill(layerMenu, for: 4)
        XCTAssertTrue(layerMenu.items.contains { $0.identifier == LLDBMenu.identifier })
    }
}
