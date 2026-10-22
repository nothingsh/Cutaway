import AppKit
import Combine
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-ATTR-23: the groups the host app adds (P-ATTR-19) have a section of their own, App,
/// after Content and before Appearance, each group under its title, in the order they came.
/// The fixtures give one such group, on virtual node 10; a label with two is made in
/// `Protocol12Extras`.
@MainActor
final class AppSectionTests: XCTestCase {
    private static func ids(
        _ listing: AttributesViewModel.Listing, _ kind: AttributesViewModel.Listing.Kind
    ) -> [String?] {
        (listing.section(kind)?.attributes ?? []).map(\.id)
    }

    // MARK: - The listing

    func test_C_ATTR_23_theAppSectionComesAfterContentAndBeforeAppearance() throws {
        let listing = AttributesViewModel.listing(of: try Protocol12Extras.layerThreeWithHostAppGroups())
        XCTAssertEqual(
            listing.sections.map(\.kind),
            [.content, .app, .appearance, .layout, .behavior, .accessibility, .object])
        // Whatever section their attributes name: Highlight and Shows Sign say Appearance.
        XCTAssertEqual(
            Self.ids(listing, .app),
            ["app.price.amount", "app.price.currency", "app.price.highlight", "app.format.showsSign"])
        XCTAssertFalse(Self.ids(listing, .appearance).contains { $0?.hasPrefix("app.") == true })
        XCTAssertFalse(Self.ids(listing, .content).contains { $0?.hasPrefix("app.") == true })
    }

    func test_C_ATTR_23_theAppsGroupsKeepTheOrderTheyCameIn() throws {
        let listing = AttributesViewModel.listing(of: try Protocol12Extras.layerThreeWithHostAppGroups())
        XCTAssertEqual(listing.section(.app)?.parts.map(\.groupTitle), ["Price", "Formatting"])
        let reversed = AttributesViewModel.listing(of: Protocol12Extras.hostAppGroups().reversed())
        XCTAssertEqual(reversed.section(.app)?.parts.map(\.groupTitle), ["Formatting", "Price"])
    }

    func test_C_ATTR_23_withoutFromAppTheGroupsGoBySection() throws {
        let row = try Fixtures.attributes(of: 10, scenario: "layer-details")
        let listing = AttributesViewModel.listing(of: row)
        XCTAssertEqual(listing.sections.map(\.kind), [.app])
        XCTAssertEqual(Self.ids(listing, .app), ["app.row.title", "app.row.amount", "app.row.color"])

        let old = AttributesViewModel.listing(of: Fixtures.withoutProtocol12(row))
        XCTAssertEqual(old.sections.map(\.kind), [.content, .appearance])
        XCTAssertEqual(Self.ids(old, .content), ["app.row.title", "app.row.amount"])
        XCTAssertEqual(Self.ids(old, .appearance), ["app.row.color"])
    }

    func test_C_ATTR_23_noAppGroupsNoAppSection() throws {
        let listing = AttributesViewModel.listing(of: try Fixtures.attributes(of: 3, scenario: "layer-details"))
        XCTAssertNil(listing.section(.app))
    }

    // MARK: - The panel

    /// A panel showing `layer`, on a server that answers by content: the fixtures' app, with
    /// layer 3 a label of the app's own class with two of its groups.
    private func panel(
        selecting layer: UInt64
    ) async throws -> (AttributesViewController, NSWindow, InspectionStore, Session, MockServer) {
        var responder = try MockResponder.demo()
        responder.details[3]?.attributeGroups = try Protocol12Extras.layerThreeWithHostAppGroups()
        let steps = try MockScript.fixtures("handshake").steps
        let server = try await MockServer.start(script: MockScript(steps: steps + [.respond(responder)]))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 14 }
        XCTAssertTrue(tree)
        let summary = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", inputs: AttributesPanelInputs(layer: summary), loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 900), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.layoutIfNeeded()
        model.select(layer)
        let loaded = await Wait.until {
            await MainActor.run {
                if case .loaded = model.attributes.state { return !controller.attributeRows.isEmpty }
                return false
            }
        }
        XCTAssertTrue(loaded)
        return (controller, window, model, session, server)
    }

    private func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    func test_C_ATTR_23_filteringAndFoldingIncludeTheAppSection() async throws {
        let (controller, window, model, session, server) = try await panel(selecting: 3)
        let field = controller.filterField
        field.stringValue = "amount"
        field.sendAction(field.action, to: field.target)
        let app = try XCTUnwrap(controller.section(.app))
        let amount = try XCTUnwrap(controller.attributeRows.first { $0.row.attributeID == "app.price.amount" })
        XCTAssertTrue(isShown(amount.row))
        XCTAssertTrue(isShown(app))
        XCTAssertFalse(controller.attributeRows
            .contains { $0.row.attributeID == "app.price.currency" && isShown($0.row) })
        field.stringValue = ""
        field.sendAction(field.action, to: field.target)

        // Folded, it stays folded on another layer and back (C-ATTR-15).
        app.toggle(all: false)
        XCTAssertTrue(app.isCollapsed)
        model.select(10)
        let other = await Wait.until {
            await MainActor.run { controller.section(.app)?.rows.count == 3 }
        }
        XCTAssertTrue(other)
        XCTAssertTrue(controller.collapsed.contains("app"))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }
}
