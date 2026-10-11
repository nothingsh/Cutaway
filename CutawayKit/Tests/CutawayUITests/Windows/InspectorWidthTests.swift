import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The inspector keeps its width whatever the selected layer holds (C-ATTR-01). It once grew
/// to fit a long name, and the preview beside it jumped at the click (2026-10-07, reported in
/// use).
final class InspectorWidthTests: XCTestCase {
    private static let long =
        "PlatterContainerHostingView<NavigationBarPlatterContainerContentView>"

    /// The fixtures with long names everywhere the inspector shows layer 3: its class names
    /// and the member that holds it, its groups and attributes, and its constraints.
    private static func responder() throws -> MockResponder {
        var responder = try MockResponder.demo()
        let three = try XCTUnwrap(responder.hierarchy.nodes.firstIndex { $0.id == 3 })
        responder.hierarchy.nodes[three].viewDisplayClassName = long
        responder.hierarchy.nodes[three].displayClassName = "_" + long + "Layer"
        responder.hierarchy.nodes[three].memberReferences = [
            MemberReference(ownerClassName: long, ownerDisplayClassName: long, name: "titleView"),
        ]
        var detail = try Fixtures.panelDetail(of: 3)
        for g in detail.attributeGroups.indices {
            detail.attributeGroups[g].title = long
            for a in detail.attributeGroups[g].attributes.indices {
                detail.attributeGroups[g].attributes[a].title = long
                if case .string = detail.attributeGroups[g].attributes[a].value {
                    detail.attributeGroups[g].attributes[a].value = .string(long + long)
                }
            }
        }
        XCTAssertFalse(detail.constraints.isEmpty)
        for c in detail.constraints.indices {
            detail.constraints[c].identifier = long
            detail.constraints[c].className = long
        }
        responder.details[3] = detail
        return responder
    }

    /// A name that fits is shown whole, and so is the member that holds the layer: giving way
    /// to the panes' widths must not let the header squeeze them where there is room
    /// (2026-10-07, reported in use).
    @MainActor
    func test_C_ATTR_01_aShortNameAndItsHolderAreShownWhole() throws {
        let model = InspectionStore(session: Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")))
        // As in the report: a name a little longer than the class and ID below it.
        var hierarchy = try Fixtures.hierarchy()
        let three = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 3 })
        hierarchy.nodes[three].viewDisplayClassName = "UINavigationBar"
        model.apply(hierarchy)
        let inspector = InspectorWindowController(
            location: .simulator(port: 48160), entry: nil, store: model)
        let window = try XCTUnwrap(inspector.window)
        model.select(3)
        window.layoutIfNeeded()
        let panel = inspector.splitController.attributesController.view
        func label(_ identifier: String) throws -> NSTextField {
            try XCTUnwrap(AppListViewTests.descendant(of: panel, identifier: identifier) as? NSTextField)
        }
        let title = try label(AttributesViewController.headerTitleIdentifier)
        XCTAssertEqual(title.stringValue, "UINavigationBar")
        XCTAssertGreaterThanOrEqual(title.frame.width + 0.5, title.intrinsicContentSize.width)
        let references = try label(AttributesViewController.headerReferencesIdentifier)
        XCTAssertEqual(references.stringValue, "HomeViewController.titleLabel")
        // It may wrap; every line of it is there.
        let needed = try XCTUnwrap(references.cell).cellSize(forBounds: NSRect(
            x: 0, y: 0, width: references.frame.width, height: .greatestFiniteMagnitude))
        XCTAssertGreaterThan(references.frame.width, 100)
        XCTAssertGreaterThanOrEqual(references.frame.height + 0.5, needed.height)
        inspector.close()
    }

    @MainActor
    func test_C_ATTR_01_longNamesDoNotWidenTheInspector() async throws {
        let server = try await MockServer.start(script: MockScript(
            steps: try MockScript.fixtures("handshake").steps + [.respond(try Self.responder())]))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        // 0.5: the inspector has its constraints, with the fold for UIKit's.
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.5.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session)
        let inspector = InspectorWindowController(
            location: .simulator(port: server.port), entry: nil, store: model)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 9 }
        XCTAssertTrue(tree)
        let window = try XCTUnwrap(inspector.window)
        window.layoutIfNeeded()
        let panes = inspector.splitController.splitView.arrangedSubviews
        let widths = panes.map(\.frame.width)

        model.select(3)
        let loaded = await Wait.until(within: .seconds(5)) {
            await MainActor.run {
                if case .loaded(_, let constraints?) = model.attributes.state {
                    !constraints.isEmpty
                } else {
                    false
                }
            }
        }
        XCTAssertTrue(loaded, "layer 3's attributes and constraints")
        window.layoutIfNeeded()
        XCTAssertEqual(panes.map(\.frame.width), widths)
        let title = try XCTUnwrap(AppListViewTests.descendant(
            of: inspector.splitController.attributesController.view,
            identifier: AttributesViewController.headerTitleIdentifier) as? NSTextField)
        XCTAssertEqual(title.stringValue, Self.long)

        inspector.close()
        await session.close()
        await server.stop()
    }
}
