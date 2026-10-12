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
    /// A client of protocol 0.2: the panel is the read-only one these tests are about, which
    /// cannot change attributes (P-HELLO-04). Editing has its own tests
    /// (AttributeEditingViewTests). Its servers speak 0.5, the same major version.
    private static let readOnlyProtocol = Version(major: 0, minor: 2)

    /// Layer 3 of `layer-details`, attribute by attribute.
    private static let groupTitles = ["Layer", "Label", "View"]
    private static let attributeTitles = [
        "Frame", "Position", "Shadow Offset", "Opacity", "Hidden", "Background Color",
        "Border Color", "Transform", "Text", "Number Of Lines", "Text Alignment", "Layout Margins",
    ]
    private static let values = [
        "96.5, 108, 200, 24", "196.5, 120", "0 × -3", "1", "No", "None", "0 0 0 1", "Identity",
        "Hello", "1", "center", "top 8, left 8, bottom 8, right 8",
    ]

    /// An inspection on a server that plays `script` after the handshake and the hierarchy,
    /// entered, with layer 3 selected and its attributes in.
    @MainActor
    private func inspection(
        _ steps: [MockScript.Step]
    ) async throws -> (InspectionStore, Session, MockServer) {
        let server = try await MockServer.start(script: MockScript(
            steps: try MockScript.fixtures("handshake", "hierarchy").steps + steps
        ).serverSpeaking(Fixtures.zeroMajorProtocol))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, protocolVersion: Self.readOnlyProtocol)
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 9 }
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
            script: MockScript(steps: steps).serverSpeaking(Fixtures.zeroMajorProtocol))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, protocolVersion: Self.readOnlyProtocol,
            requestTimeout: .milliseconds(300))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
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
        for model: InspectionStore, loadingDelay: TimeInterval = 0, onRetry: @escaping () -> Void = {}
    ) -> (AttributesViewController, NSWindow) {
        let layer = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: layer, onRetry: onRetry,
            loadingDelay: loadingDelay)
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

    @MainActor
    private func rows(_ controller: AttributesViewController) -> [AttributeRowView] {
        controller.groupViews.flatMap(\.rows)
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
    func test_C_ATTR_01_theSelectedLayersGroupsAndAttributesAreListed() async throws {
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details").steps)
        let (controller, window) = panel(for: model)

        XCTAssertTrue(isShown(try list(controller)))
        XCTAssertFalse(isShown(try label(AttributesViewController.messageIdentifier, in: controller)))
        XCTAssertEqual(controller.groupViews.map(\.title), Self.groupTitles)
        XCTAssertEqual(controller.groupViews.map(\.rows.count), [8, 3, 1])
        XCTAssertEqual(rows(controller).map(\.title), Self.attributeTitles)
        XCTAssertEqual(rows(controller).map(\.valueView.plainText), Self.values)
        let headers = AppListViewTests.descendants(
            of: controller.view, identifier: AttributeGroupView.headerIdentifier)
        XCTAssertEqual(headers.compactMap { ($0 as? NSButton)?.accessibilityLabel() }, Self.groupTitles)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_theHeaderNamesTheSelectedLayer() async throws {
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details").steps)
        let (controller, window) = panel(for: model)

        let header = try XCTUnwrap(AppListViewTests.descendant(
            of: controller.view, identifier: AttributesViewController.headerIdentifier))
        XCTAssertTrue(isShown(header))
        XCTAssertEqual(
            try label(AttributesViewController.headerTitleIdentifier, in: controller).stringValue,
            "UILabel")
        let subtitle = try label(AttributesViewController.headerSubtitleIdentifier, in: controller)
        XCTAssertTrue(subtitle.stringValue.hasSuffix("ID 3"), subtitle.stringValue)

        // Nothing selected, no header.
        model.select(nil)
        XCTAssertFalse(isShown(header))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_everySymbolOfThePanelExists() {
        for name in AttributesViewController.symbols + LayerSymbol.all {
            XCTAssertNotNil(Theme.symbol(name), name)
        }
    }

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
        ).serverSpeaking(Fixtures.zeroMajorProtocol))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, protocolVersion: Self.readOnlyProtocol)
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 9 }
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
        XCTAssertLessThan(header.frame.height, 100, "the header was stretched")
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
    func test_C_ATTR_01_aSlowAnswerShowsLoading() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps.append(.expect(.getLayerDetails, as: 90))  // never answered
        let server = try await MockServer.start(
            script: MockScript(steps: steps).serverSpeaking(Fixtures.zeroMajorProtocol))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, protocolVersion: Self.readOnlyProtocol)
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 9 }
        XCTAssertTrue(tree)
        let (controller, window) = panel(for: model, loadingDelay: 0.05)
        let message = try label(AttributesViewController.messageIdentifier, in: controller)

        model.select(3)
        XCTAssertFalse(isShown(message))
        let shown = await Wait.until { @MainActor in message.stringValue == "Loading Attributes" }
        XCTAssertTrue(shown)
        XCTAssertTrue(isShown(message))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_tryAgainAsksAgain() async throws {
        let (model, session, server) = try await failingAttributes()
        var asked = 0
        let (controller, window) = panel(for: model, onRetry: { asked += 1 })
        model.select(3)
        let failed = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(failed)

        let retry = try XCTUnwrap(AppListViewTests.descendant(
            of: controller.view, identifier: AttributesViewController.retryIdentifier) as? NSButton)
        retry.performClick(nil)
        XCTAssertEqual(asked, 1)
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
        XCTAssertEqual(split.attributesController.groupViews.count, 3)
        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_rowsFollowTheGroupsInOrder() {
        let groups = [
            AttributeGroup(id: "a", title: "A", attributes: [
                Attribute(id: "x", title: "X", value: .integer(1)),
                Attribute(id: "y", title: nil, value: nil),
            ]),
            AttributeGroup(id: "b", title: nil, attributes: []),
        ]
        XCTAssertEqual(AttributesViewController.rows(for: groups), [
            .group(title: "A"),
            .attribute(title: "X", value: .integer(1)),
            .attribute(title: "y", value: nil),
            .group(title: "b"),
        ])
    }

    @MainActor
    func test_C_ATTR_01_aFoldedGroupStaysFoldedForTheNextLayer() async throws {
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details", "layer-details").steps)
        let (controller, window) = panel(for: model)
        let label = try XCTUnwrap(controller.groupViews.first { $0.title == "Label" })
        XCTAssertFalse(label.isCollapsed)
        XCTAssertTrue(label.rows.allSatisfy(isShown))

        label.toggle(nil)
        XCTAssertTrue(label.isCollapsed)
        XCTAssertFalse(label.rows.contains(where: isShown))

        // Another layer, shown, and back: a new list, with the group still folded.
        model.select(4)
        let moved = await Wait.until { await model.attributes.state != .loading }
        XCTAssertTrue(moved)
        XCTAssertNotEqual(controller.groupViews.map(\.title), ["Layer", "Label", "View"])
        model.select(3)
        let again = await Wait.until { @MainActor in controller.groupViews.count == 3 }
        XCTAssertTrue(again)
        let folded = try XCTUnwrap(controller.groupViews.first { $0.title == "Label" })
        XCTAssertTrue(folded.isCollapsed)
        XCTAssertFalse(try XCTUnwrap(controller.groupViews.first { $0.title == "Layer" }).isCollapsed)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_anotherLayersAttributesStartAtTheTop() async throws {
        // Every answer has both layers: the order of the requests does not matter.
        let many = (0..<30).map {
            Attribute(id: "a\($0)", title: "Attribute \($0)", value: .integer(Int64($0)))
        }
        let four = LayerDetail(
            layerID: 4, status: .ok, solo: nil, group: nil,
            attributeGroups: [AttributeGroup(id: "g", title: "G", attributes: many)])
        let three = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 3 })
        let both = [three, four]
        let (model, session, server) = try await inspection(
            MockScript.layerDetailsSteps(both, as: 40)
                + MockScript.layerDetailsSteps(both, as: 41)
                + MockScript.layerDetailsSteps(both, as: 42))
        let (controller, window) = panel(for: model)
        window.setContentSize(NSSize(width: 300, height: 200))
        window.layoutIfNeeded()
        model.select(4)
        let fourShown = await Wait.until { @MainActor in controller.groupViews.first?.rows.count == 30 }
        XCTAssertTrue(fourShown)
        let scroll = try XCTUnwrap(try list(controller) as? NSScrollView)
        window.layoutIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "scrolled down")

        model.select(3)
        window.layoutIfNeeded()
        XCTAssertEqual(controller.groupViews.count, 3, "shown at once")
        XCTAssertEqual(scroll.contentView.bounds.minY, 0)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    /// A row has no menu of its own (reported by the user); its value can still be selected
    /// and copied with the text's own menu.
    @MainActor
    func test_C_ATTR_02_aRowHasNoMenuButItsValueCanBeSelected() {
        let row = AttributeRowView(
            title: "Frame",
            value: .rect(Rect(origin: Point(x: 1, y: 2), size: Size(width: 3, height: 4))))
        XCTAssertNil(row.menu)
        let labels = AppListViewTests.descendants(of: row) {
            ($0 as? NSTextField)?.isSelectable == true
        }
        XCTAssertFalse(labels.isEmpty, "the value can be selected")
        XCTAssertEqual(row.valueView.plainText, "1, 2, 3, 4")
    }

    // MARK: - C-ATTR-02

    @MainActor
    func test_C_ATTR_02_aNilValueKeepsItsRowAndAColourHasASwatch() async throws {
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details").steps)
        let (controller, window) = panel(for: model)

        let background = try XCTUnwrap(rows(controller).first { $0.title == "Background Color" })
        XCTAssertNil(background.valueView.swatchColor)
        XCTAssertEqual(background.valueView.plainText, "None")
        XCTAssertTrue(isShown(background))
        let none = try XCTUnwrap(AppListViewTests.descendants(of: background.valueView)
            .compactMap { $0 as? NSTextField }.first { $0.stringValue == "None" })
        XCTAssertEqual(none.textColor, .tertiaryLabelColor, "grey, as the identity transform")
        XCTAssertEqual(background.valueView.accessibilityValue() as? String, "None")

        let border = try XCTUnwrap(rows(controller).first { $0.title == "Border Color" })
        XCTAssertEqual(border.valueView.swatchColor, Color(red: 0, green: 0, blue: 0, alpha: 1))
        let swatch = try XCTUnwrap(AppListViewTests.descendant(
            of: border, identifier: AttributeValueView.swatchIdentifier))
        XCTAssertTrue(isShown(swatch))
        XCTAssertTrue(AppWindowsText.labels(in: border.valueView).contains("#000000"))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_02_everyKindOfValueHasItsLook() {
        func labels(_ value: AttributeValue?) -> [String] {
            AppWindowsText.labels(in: AttributeValueView(value: value))
        }
        XCTAssertEqual(labels(nil), ["None"])
        XCTAssertEqual(labels(.bool(true)), ["Yes"])
        XCTAssertEqual(labels(.bool(false)), ["No"])
        XCTAssertEqual(labels(.integer(42)), ["42"])
        XCTAssertEqual(labels(.double(0.25)), ["0.25"])
        XCTAssertEqual(labels(.string("Hello")), ["Hello"])
        XCTAssertEqual(labels(.string("")), ["\"\""], "an empty string is not no value")
        XCTAssertEqual(labels(.point(Point(x: 1, y: 2))), ["X", "1", "Y", "2"])
        XCTAssertEqual(labels(.size(Size(width: 3, height: 4))), ["W", "3", "H", "4"])
        XCTAssertEqual(
            labels(.rect(Rect(origin: Point(x: 1, y: 2), size: Size(width: 3, height: 4)))),
            ["X", "1", "Y", "2", "W", "3", "H", "4"])
        XCTAssertEqual(
            labels(.insets(Insets(top: 1, left: 2, bottom: 3, right: 4))),
            ["T", "1", "L", "2", "B", "3", "R", "4"])
        // Insets take two lines, so that ordinary numbers are not cut.
        let insets = AttributeValueView(
            value: .insets(Insets(top: 34.6667, left: -123.5, bottom: 8, right: 8)))
        let fields = AppListViewTests.descendants(
            of: insets, identifier: AttributeValueView.fieldIdentifier)
        XCTAssertEqual(Set(fields.map { $0.frame.origin.y.rounded() }).count, 1, "per line")
        XCTAssertEqual(fields.first?.toolTip, "34.6667")
        XCTAssertEqual(labels(.transform(.identity)), ["Identity"])
        XCTAssertEqual(
            labels(.enumeration(EnumValue(value: 1, cases: ["left", "center"], caseName: nil))),
            ["center"])
        XCTAssertEqual(
            labels(.color(Color(red: 1, green: 0.5, blue: 0, alpha: 0.5))), ["#FF8000  α 0.5"])
        // Extended sRGB cannot be written as a code: the components, as plain text.
        XCTAssertEqual(
            labels(.color(Color(red: 1.2, green: 0, blue: 0, alpha: 1))), ["1.2 0 0 1"])

        // The plain text is what is copied, whatever the look.
        let rect = AttributeValueView(
            value: .rect(Rect(origin: Point(x: 1, y: 2), size: Size(width: 3, height: 4))))
        XCTAssertEqual(rect.plainText, "1, 2, 3, 4")
        XCTAssertEqual(rect.accessibilityValue() as? String, "1, 2, 3, 4")
    }

    @MainActor
    func test_C_ATTR_02_aMarkStaysBesideItsWordInAWideColumn() throws {
        for value in [AttributeValue.bool(true), .bool(false),
                      .color(Color(red: 1, green: 0, blue: 0, alpha: 1))]
        {
            let view = AttributeValueView(value: value)
            view.frame = NSRect(x: 0, y: 0, width: 240, height: 20)
            view.layoutSubtreeIfNeeded()
            let mark = try XCTUnwrap(AppListViewTests.firstDescendant(of: view) {
                $0 is NSImageView || $0 is SwatchView
            })
            let word = try XCTUnwrap(AppListViewTests.firstDescendant(of: view) {
                $0 is NSTextField
            })
            // Neither takes the room left over (which one would, without a spacer, is up to
            // Auto Layout), so the word sits right after the mark.
            XCTAssertLessThanOrEqual(mark.frame.width, mark.fittingSize.width + 1, "\(value)")
            XCTAssertLessThanOrEqual(word.frame.width, word.fittingSize.width + 1, "\(value)")
            let gap = word.convert(word.bounds, to: view).minX
                - mark.convert(mark.bounds, to: view).maxX
            XCTAssertLessThanOrEqual(gap, 8, "\(value)")
        }
    }

    @MainActor
    func test_C_ATTR_02_aTransformThatIsNotTheIdentityIsAFourByFourGrid() {
        var rotated = Transform3D.identity
        rotated.m11 = 0.8660254037844387
        rotated.m12 = 0.5
        rotated.m21 = -0.5
        rotated.m22 = 0.8660254037844387
        let view = AttributeValueView(value: .transform(rotated))
        let grid = AppListViewTests.firstDescendant(of: view) { $0 is NSGridView } as? NSGridView
        XCTAssertEqual(grid?.numberOfRows, 4)
        XCTAssertEqual(grid?.numberOfColumns, 4)
        let texts = AppWindowsText.labels(in: view)
        XCTAssertEqual(texts.count, 16)
        XCTAssertEqual(Array(texts.prefix(4)), ["0.866", "0.5", "0", "0"])
        XCTAssertEqual(view.plainText.split(separator: "\n").count, 4)
    }

    @MainActor
    func test_C_ATTR_02_valuesCanBeSelectedAndCopied() async throws {
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details").steps)
        let (controller, window) = panel(for: model)

        let texts = rows(controller).flatMap { row in
            AppListViewTests.descendants(of: row.valueView) { $0 is NSTextField }
                .compactMap { $0 as? NSTextField }
                .filter { !["X", "Y", "W", "H", "T", "L", "B", "R"].contains($0.stringValue) }
        }
        XCTAssertFalse(texts.isEmpty)
        XCTAssertTrue(texts.allSatisfy(\.isSelectable))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_02_aLongValueWrapsAndANarrowerPanelWrapsItAgain() async throws {
        let long = String(repeating: "A label with a lot of text in it. ", count: 12)
        let details = [LayerDetail(
            layerID: 3, status: .ok, solo: nil, group: nil,
            attributeGroups: [AttributeGroup(id: "g", title: "G", attributes: [
                Attribute(id: "s", title: "Text", value: .string(long)),
                Attribute(id: "o", title: "Opacity", value: .double(1)),
            ])])]
        let (model, session, server) = try await inspection(
            MockScript.layerDetailsSteps(details, as: 40)
                + MockScript.layerDetailsSteps(details, as: 41))
        let (controller, window) = panel(for: model)
        let text = try XCTUnwrap(rows(controller).first)
        let opacity = try XCTUnwrap(rows(controller).last)
        window.layoutIfNeeded()
        let wide = text.frame.height
        XCTAssertGreaterThan(wide, 2 * opacity.frame.height, "\(wide) vs \(opacity.frame.height)")

        window.setContentSize(NSSize(width: 240, height: 600))
        window.layoutIfNeeded()
        let narrow = text.frame.height
        XCTAssertGreaterThan(narrow, wide, "at 240 points the text takes more lines")

        window.setContentSize(NSSize(width: 300, height: 600))
        window.layoutIfNeeded()
        XCTAssertEqual(text.frame.height, wide, accuracy: 0.5)

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

        XCTAssertEqual(controller.groupViews.map(\.title), Self.groupTitles.map(Fixtures.renamed))
        XCTAssertEqual(rows(controller).map(\.title), Self.attributeTitles.map(Fixtures.renamed))
        XCTAssertEqual(rows(controller).map(\.valueView.plainText), Self.values, "values stay")
        let shown = Set(controller.groupViews.map(\.title) + rows(controller).map(\.title))
        XCTAssertTrue(shown.isDisjoint(with: Self.groupTitles + Self.attributeTitles))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-HIER-07: the header names the view controller and the members

    @MainActor
    func test_C_HIER_07_theHeaderNamesTheViewControllerAndTheMembers() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let (controller, window) = panel(for: model)
        let viewController = try label(
            AttributesViewController.headerControllerIdentifier, in: controller)
        let references = try label(
            AttributesViewController.headerReferencesIdentifier, in: controller)

        model.select(5)
        XCTAssertFalse(isShown(viewController))
        XCTAssertTrue(isShown(references))
        XCTAssertEqual(
            references.stringValue, "CardView.badgeLayer\nHomeViewController.cardBadge")
        XCTAssertTrue(references.isSelectable)

        model.select(2)
        XCTAssertTrue(isShown(viewController))
        XCTAssertEqual(viewController.stringValue, "HomeViewController")
        XCTAssertFalse(isShown(references))

        model.select(1)
        XCTAssertFalse(isShown(viewController))
        XCTAssertFalse(isShown(references))
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_HIER_07_theHeadersValuesLineUp() throws {
        var hierarchy = try Fixtures.hierarchy()
        let two = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 2 })
        hierarchy.nodes[two].memberReferences = [
            MemberReference(ownerClassName: "A", ownerDisplayClassName: "A", name: "one"),
        ]
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(hierarchy)
        let (controller, window) = panel(for: model)
        model.select(2)
        window.layoutIfNeeded()
        let viewController = try label(
            AttributesViewController.headerControllerIdentifier, in: controller)
        let references = try label(
            AttributesViewController.headerReferencesIdentifier, in: controller)
        XCTAssertEqual(
            viewController.convert(viewController.bounds, to: nil).minX,
            references.convert(references.bounds, to: nil).minX, accuracy: 0.5)
        withExtendedLifetime(window) {}
    }

    // MARK: - The same answer again

    @MainActor
    func test_C_ATTR_01_theSameAnswerAgainLeavesTheListAsItIs() async throws {
        // Screenshots, attributes, then the attributes again in the next round.
        let (model, session, server) = try await inspection(
            try MockScript.fixtures("layer-details", "layer-details", "layer-details").steps)
        let (controller, window) = panel(for: model)
        let before = controller.groupViews.map(ObjectIdentifier.init)
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
        XCTAssertEqual(controller.groupViews.map(ObjectIdentifier.init), before)

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
