import AppKit
import Combine
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The attribute panel as it is shown (C-ATTR-01 to C-ATTR-03). Checked by its views and
/// texts, not by eye.
final class AttributesViewTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")
    /// The app, read-only: the panel these tests are about cannot change attributes. Editing
    /// has its own tests (AttributeEditingViewTests).
    private actor ReadOnlySource: InspectionSource {
        let session: Session

        init(_ session: Session) {
            self.session = session
        }

        nonisolated var isLive: Bool { true }
        var negotiatedVersion: Version? { get async { await session.negotiatedVersion } }
        var capabilities: InspectionCapabilities? {
            InspectionCapabilities(canRefreshSubtrees: true, canEditAttributes: false)
        }

        func hierarchy() async throws -> Hierarchy { try await session.hierarchy() }
        func subtree(of rootID: UInt64) async throws -> Hierarchy {
            try await session.subtree(of: rootID)
        }

        func layerDetails(_ request: GetLayerDetails) async -> LayerDetailsStream {
            await session.layerDetails(request)
        }

        func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult {
            throw RequestError.unsupported
        }
    }

    /// Layer 3 of `layer-details`, attribute by attribute, as listed (C-ATTR-10): the five
    /// sections by what the attributes are for, Object last.
    private static let sectionTitles = ["Label", "Appearance", "Layout", "Behavior", "Accessibility", "Object"]
    private static let attributeTitles = [
        "Text", "Font Size", "Text Style", "Adjusts to Text Size", "Lines", "Text Alignment",
        "Hidden", "Opacity", "Background", "Tint", "Shadow Opacity", "Shadow Offset",
        "Border Width", "Border Color",
        "Layout Margins", "Frame", "Bounds", "Position", "Transform",
        "User Interaction",
        "Label",
        "Tag",
    ]
    private static let values = [
        "Hello", "17", "body", "Yes", "1", "center",
        "No", "1", "None", "0 0.4784 1 1", "0", "0 × -3", "0", "0 0 0 1",
        "top 8, left 8, bottom 8, right 8", "96.5, 108, 200, 24", "0, 0, 200, 24", "196.5, 120",
        "Identity",
        "No",
        "Welcome",
        "0",
    ]

    /// An inspection on a server that plays `script` after the handshake and the hierarchy,
    /// entered, with layer 3 selected and its attributes in. Without `clusters` every
    /// attribute has a row of its own, as the tests of rows by title expect; the compound rows
    /// (C-ATTR-19) are tested with them.
    @MainActor
    private func inspection(
        _ steps: [MockScript.Step], protocol10: Bool = false, clusters: Bool = false
    ) async throws -> (InspectionStore, Session, MockServer) {
        var script = MockScript(steps: try MockScript.fixtures("handshake", "hierarchy").steps + steps)
        // A peer of 1.0 sends no addresses, sections or limits (C-WIRE-10).
        if protocol10 {
            script = script.asProtocol10()
        } else if !clusters {
            script = script.withoutClusters()
        }
        let server = try await MockServer.start(script: script)
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()
        let model = InspectionStore(source: ReadOnlySource(session), newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 14 }
        XCTAssertTrue(tree)
        model.select(3)
        let loaded = await Wait.until {
            if case .loaded = await model.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded, "the attributes did not arrive")
        return (model, session, server)
    }

    /// An entered inspection whose screenshots are all in, on a server that never answers the
    /// first request for attributes (it times out) and answers the next one with
    /// `layer-details`.
    @MainActor
    private func failingAttributes() async throws -> (InspectionStore, Session, MockServer) {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps.append(.expect(.getLayerDetails, as: 90))  // the attributes, never answered
        steps += try MockScript.fixtures("layer-details").steps
        let server = try await MockServer.start(
            script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client,
            requestTimeout: .milliseconds(300))
        _ = try await session.handshake()
        let model = InspectionStore(source: ReadOnlySource(session), newLayers: .expanded)
        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)
        return (model, session, server)
    }

    /// The panel in a window that is never shown, 300 × 600 points.
    @MainActor
    private func panel(
        for model: InspectionStore, loadingDelay: TimeInterval = 0, onRetry: @escaping () -> Void = {},
        copy: @escaping @MainActor (String) -> Void = { _ in }
    ) -> (AttributesViewController, NSWindow) {
        let layer = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", inputs: AttributesPanelInputs(layer: layer),
            actions: AttributesPanelActions(retry: onRetry, copy: copy), loadingDelay: loadingDelay)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 300, height: 600))
        window.layoutIfNeeded()
        return (controller, window)
    }

    @MainActor
    private func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    /// Every attribute row, in the order of the list.
    @MainActor
    private func rows(_ controller: AttributesViewController) -> [AttributeRowView] {
        controller.attributeRows.map(\.row)
    }

    /// Filters as the user does, typing into the filter field.
    @MainActor
    private func filter(_ text: String, in controller: AttributesViewController) {
        let field = controller.filterField
        field.stringValue = text
        field.sendAction(field.action, to: field.target)
    }

    @MainActor
    private func label(
        _ identifier: String, in controller: AttributesViewController
    ) throws -> NSTextField {
        try XCTUnwrap(
            AppListViewTests.descendant(of: controller.view, identifier: identifier)
                as? NSTextField, identifier)
    }

    @MainActor
    private func list(_ controller: AttributesViewController) throws -> NSView {
        try XCTUnwrap(AppListViewTests.descendant(
            of: controller.view, identifier: AttributesViewController.listIdentifier))
    }

    // MARK: - C-ATTR-01

    @MainActor
    func test_C_ATTR_01_theMessageStandsInForTheList() async throws {
        let (model, session, server) = try await failingAttributes()
        let (controller, window) = panel(for: model, loadingDelay: 0.05)
        let message = try label(AttributesViewController.messageIdentifier, in: controller)
        XCTAssertTrue(isShown(message))
        XCTAssertFalse(isShown(try list(controller)))
        XCTAssertEqual(message.stringValue, "No Selection")

        // Selecting asks; the request times out, so the panel offers to try again.
        model.select(3)
        let failed = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(failed)
        XCTAssertEqual(message.stringValue, "Couldn’t Load Attributes")
        let retry = try XCTUnwrap(AppListViewTests.descendant(
            of: controller.view, identifier: AttributesViewController.retryIdentifier) as? NSButton)
        XCTAssertTrue(isShown(retry))
        XCTAssertFalse(isShown(try list(controller)))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aQuickAnswerShowsNoLoadingInBetween() async throws {
        let server = try await MockServer.start(script: MockScript(
            steps: try MockScript.fixtures("handshake", "hierarchy").steps
                + MockScript.fixtures("layer-details", "layer-details").steps
        ))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()
        let model = InspectionStore(source: ReadOnlySource(session), newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 14 }
        XCTAssertTrue(tree)
        let (controller, window) = panel(for: model, loadingDelay: 5)
        let message = try label(AttributesViewController.messageIdentifier, in: controller)

        model.select(3)
        // Asked, not answered yet: nothing but the header for now, and it stays at the top.
        XCTAssertEqual(model.attributes.state, .loading)
        XCTAssertFalse(isShown(message))
        XCTAssertFalse(isShown(try list(controller)))
        window.layoutIfNeeded()
        let header = try XCTUnwrap(AppListViewTests.descendant(
            of: controller.view, identifier: AttributesViewController.headerIdentifier))
        XCTAssertTrue(isShown(header))
        let frame = header.convert(header.bounds, to: controller.view)
        XCTAssertEqual(frame.maxY, controller.view.bounds.maxY, accuracy: 0.5)
        // Its name, what holds it, its ancestors (C-ATTR-16) and the filter.
        XCTAssertLessThan(header.frame.height, 130, "the header was stretched")
        let loaded = await Wait.until {
            if case .loaded = await model.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded)
        XCTAssertTrue(isShown(try list(controller)))
        XCTAssertFalse(isShown(message))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_theSplitViewsRetryAsksTheModelAgain() async throws {
        let (model, session, server) = try await failingAttributes()
        let split = InspectorSplitViewController(store: model, appName: "Demo")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = split
        model.select(3)
        let failed = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(failed)

        let retry = try XCTUnwrap(AppListViewTests.descendant(
            of: split.attributesController.view,
            identifier: AttributesViewController.retryIdentifier) as? NSButton)
        retry.performClick(nil)
        // Asked again, and this time answered.
        let loaded = await Wait.until {
            if case .loaded = await model.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(split.attributesController.sectionViews.count, Self.sectionTitles.count)
        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-03

    @MainActor
    func test_C_ATTR_03_titlesUnknownToTheClientAreShownAsReceived() async throws {
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details").renamingAttributes().steps)
        let (controller, window) = panel(for: model)

        // The Content section takes its group's title; the others are the panel's own.
        XCTAssertEqual(
            controller.sectionViews.map(\.title),
            [Fixtures.renamed("Label"), "Appearance", "Layout", "Behavior", "Accessibility", "Object"])
        XCTAssertEqual(rows(controller).map(\.title), Self.attributeTitles.map(Fixtures.renamed))
        XCTAssertEqual(rows(controller).map(\.plainText), Self.values, "values stay")
        let shown = Set([controller.sectionViews[0].title] + rows(controller).map(\.title))
        XCTAssertTrue(shown.isDisjoint(with: ["Label"] + Self.attributeTitles))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-10: five sections

    @MainActor
    func test_C_ATTR_10_aPeerOfProtocol10HasEverythingInAppearance() async throws {
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details").steps, protocol10: true)
        let (controller, window) = panel(for: model)

        XCTAssertEqual(controller.sectionViews.map(\.title), ["Appearance", "Object"])
        XCTAssertEqual(controller.sectionViews.map(\.rows.count), [22, 0])
        // The Object section still says what the object is.
        let object = try XCTUnwrap(controller.objectSection)
        XCTAssertTrue(isShown(object))
        XCTAssertEqual(object.header.shownText, "Object", "no Tag and no addresses to sum up")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-26: Accessibility

    @MainActor
    func test_C_ATTR_26_filteringLabelKeepsTheAccessibilityLabel() async throws {
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details").steps)
        let (controller, window) = panel(for: model)
        let section = try XCTUnwrap(controller.section(.accessibility))
        XCTAssertEqual(section.title, "Accessibility")

        filter("label", in: controller)
        let row = try XCTUnwrap(rows(controller).first { $0.attributeID == "view.accessibilityLabel" })
        XCTAssertTrue(isShown(row), "kept by its ID")
        XCTAssertTrue(row.isDescendant(of: section))
        XCTAssertTrue(isShown(section))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - The same answer again

    @MainActor
    func test_C_ATTR_01_theSameAnswerAgainLeavesTheListAsItIs() async throws {
        // Screenshots, attributes, then the attributes again in the next round.
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details", "layer-details").steps)
        let (controller, window) = panel(for: model)
        let before = controller.sectionViews.map(ObjectIdentifier.init)
        XCTAssertFalse(before.isEmpty)

        // A new round: the selected layer's attributes are asked for again, and the answer is
        // the same.
        model.apply(try Fixtures.hierarchy())
        let asked = await Wait.until {
            await server.receivedFrames.filter {
                if case .getLayerDetails = $0.body { return true }
                return false
            }.count == 3
        }
        XCTAssertTrue(asked)
        try await Task.sleep(for: .milliseconds(300))
        guard case .loaded = model.attributes.state else {
            XCTFail("the second answer did not arrive")
            return
        }
        // Rebuilding would drop text selected in a value.
        XCTAssertEqual(controller.sectionViews.map(ObjectIdentifier.init), before)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }
}

extension AppListViewTests {
    /// Every view with this accessibility identifier in `view` and below it.
    @MainActor
    static func descendants(of view: NSView, identifier: String) -> [NSView] {
        descendants(of: view) { $0.accessibilityIdentifier() == identifier }
    }

    /// Every view in `view` and below it that matches.
    @MainActor
    static func descendants(of view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
        var found = matches(view) ? [view] : []
        for subview in view.subviews { found += descendants(of: subview, where: matches) }
        return found
    }

    @MainActor
    static func firstDescendant(of view: NSView, where matches: (NSView) -> Bool) -> NSView? {
        descendants(of: view, where: matches).first
    }
}
