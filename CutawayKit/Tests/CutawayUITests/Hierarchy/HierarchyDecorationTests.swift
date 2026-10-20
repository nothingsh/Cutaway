import AppKit
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// What the list shows besides its rows: the guides (C-HIER-12), the sticky ancestors
/// (C-HIER-13), following the selection sideways (C-HIER-14), and the hover (C-HIER-15).
final class HierarchyDecorationTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    @MainActor
    private func model() -> InspectionStore {
        InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
    }

    /// A controller in a window that is never shown.
    @MainActor
    private func controllerInWindow(
        for model: InspectionStore, width: CGFloat = 280, height: CGFloat = 300
    ) -> (HierarchyViewController, NSWindow) {
        let controller = HierarchyViewController(store: model, appName: "Demo")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: width, height: height))
        window.layoutIfNeeded()
        return (controller, window)
    }

    /// A chain of layers, each inside the one before.
    private func chain(depth: Int, title: String = "UIView") -> Hierarchy {
        let nodes = (1...depth).map { id in
            LayerNode(
                id: UInt64(id), parentID: UInt64(id - 1), className: "CALayer",
                displayClassName: "CALayer", viewClassName: title, viewDisplayClassName: title,
                bounds: nil, position: nil, anchorPoint: nil, transform: nil, zPosition: 0,
                isHidden: false, opacity: 1, masksToBounds: false)
        }
        return Hierarchy(nodes: nodes, keyWindowID: 1)
    }

    @MainActor
    private func rowView(
        _ id: UInt64, in controller: HierarchyViewController
    ) throws -> HierarchyTableRowView {
        let row = controller.row(of: id)
        XCTAssertGreaterThanOrEqual(row, 0, "layer \(id) has a row")
        return try XCTUnwrap(
            controller.outlineView.rowView(atRow: row, makeIfNecessary: true) as? HierarchyTableRowView)
    }

    @MainActor
    private func guides(
        _ id: UInt64, in controller: HierarchyViewController
    ) throws -> [HierarchyGuide.Style] {
        try rowView(id, in: controller).guides.map(\.style)
    }

    @MainActor
    private func scroll(_ controller: HierarchyViewController, toRow row: Int) {
        let outline = controller.outlineView
        outline.scroll(NSPoint(x: outline.visibleRect.minX, y: outline.rect(ofRow: row).minY))
    }

    /// A mouse event at the middle of a row, in the window.
    @MainActor
    private func event(
        _ type: NSEvent.EventType, atRow row: Int, of controller: HierarchyViewController,
        in window: NSWindow
    ) throws -> NSEvent {
        let outline = controller.outlineView
        let rect = outline.rect(ofRow: row)
        let point = outline.convert(NSPoint(x: outline.visibleRect.midX, y: rect.midY), to: nil)
        if type == .mouseMoved {
            return try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0,
                pressure: 0))
        }
        return try XCTUnwrap(NSEvent.enterExitEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0,
            userData: nil))
    }

    // MARK: - C-HIER-13: sticky ancestors

    @MainActor
    func test_C_HIER_13_theNearestFourAncestorsStickAtTheTop() throws {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(chain(depth: 30))
        window.layoutIfNeeded()

        // Row 6 at the top: below four sticky rows comes row 10, layer 11, inside 1 to 10.
        scroll(controller, toRow: 6)
        let sticky = controller.stickyView
        XCTAssertEqual(sticky.rows.map(\.id), [7, 8, 9, 10])
        XCTAssertEqual(sticky.moreAbove, 6)
        XCTAssertFalse(sticky.isHidden)
        let more = try XCTUnwrap(AppListViewTests.descendant(
            of: sticky, identifier: HierarchyStickyView.moreIdentifier) as? NSTextField)
        XCTAssertEqual(more.stringValue, "\u{22EF}6")
        XCTAssertFalse(more.isHidden)

        // Each sticky row stands where its row is, sideways, and scrolls sideways with it.
        let outline = controller.outlineView
        let cell = outline.frameOfCell(atColumn: 0, row: controller.row(of: 7))
        XCTAssertEqual(sticky.rows[0].cellX, cell.minX - outline.visibleRect.minX)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_HIER_13_fewerAncestorsStickNearTheTopOfTheTree() throws {
        let model = model()
        // Room for four or five rows: the nine rows of the fixture's layers of 1.1 scroll.
        let (controller, window) = controllerInWindow(for: model, height: 170)
        model.apply(try Fixtures.hierarchyBeforeProtocol12())
        window.layoutIfNeeded()

        // Rows 1 to 9, levels 0 1 2 2 3 2 3 2 2. Row 2 (layer 3) at the top: below three
        // sticky rows comes row 5 (layer 6, inside 1 and 2), which has two; below two comes
        // row 4 (layer 5, inside 1, 2, 4).
        scroll(controller, toRow: 2)
        XCTAssertEqual(controller.stickyView.rows.map(\.id), [2, 4])
        XCTAssertEqual(controller.stickyView.moreAbove, 1)
        withExtendedLifetime(window) {}
    }

    // MARK: - C-HIER-14: following the selection sideways

    @MainActor
    func test_C_HIER_14_selectingADeepLayerScrollsItsRowIntoViewSideways() {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(chain(depth: 40, title: "UICollectionViewListCell"))
        window.layoutIfNeeded()
        let outline = controller.outlineView
        XCTAssertEqual(outline.visibleRect.minX, 0)

        // As from the preview: the store's selection changes. Deeper rows follow, so the
        // list can scroll as far as it likes.
        model.select(30)
        let cell = outline.frameOfCell(atColumn: 0, row: controller.row(of: 30))
        let visible = outline.visibleRect
        XCTAssertGreaterThan(visible.minX, 0, "scrolled sideways")
        // Two levels of indentation and the triangle before the icon.
        XCTAssertEqual(cell.minX - visible.minX, 2 * 12 + 10)
        XCTAssertLessThanOrEqual(cell.minX + 62, visible.maxX)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_HIER_14_onlyAChangeOfTheSelectionScrollsSideways() {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(chain(depth: 40, title: "UICollectionViewListCell"))
        window.layoutIfNeeded()
        let outline = controller.outlineView
        model.select(40)
        XCTAssertGreaterThan(outline.visibleRect.minX, 0)

        // The user scrolls back to the left edge; a reload and a hover leave that.
        outline.scroll(NSPoint(x: 0, y: outline.visibleRect.minY))
        model.apply(chain(depth: 40, title: "UICollectionViewListCell"))
        window.layoutIfNeeded()
        model.hover(40)
        XCTAssertEqual(outline.visibleRect.minX, 0)
        withExtendedLifetime(window) {}
    }

    // MARK: - C-HIER-15: hover

    @MainActor
    func test_C_HIER_15_nothingIsHoveredOnceDisconnected() throws {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(try Fixtures.hierarchy())
        window.layoutIfNeeded()

        model.connectionLost()
        let outline = controller.outlineView
        outline.mouseMoved(with: try event(.mouseMoved, atRow: 3, of: controller, in: window))
        XCTAssertNil(model.hoveredLayerID)
        controller.stickyView.onHover?(2)
        XCTAssertNil(model.hoveredLayerID)
    }
}
