import AppKit
import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The attribute panel when attributes can be changed (C-ATTR-04, C-ATTR-06): which rows get
/// editors, what a row shows while a change is on its way or after it failed, and that new
/// values come in place.
final class AttributeEditingViewTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.4.0")

    /// An inspection on a 0.3 server, entered, with layer 3 selected and its attributes in;
    /// then `steps`.
    /// With `protocol10`, the server leaves out what protocol 1.1 added (C-ATTR-13). The
    /// attributes come without clusters, each on a row of its own: these tests are about
    /// what one attribute's editor does; `CompoundRowTests` has the compound rows (C-ATTR-19).
    @MainActor
    func inspection(
        _ steps: [MockScript.Step], protocol10: Bool = false
    ) async throws -> (InspectionStore, Session, MockServer) {
        let script = MockScript(
            steps: try MockScript.fixtures("handshake", "hierarchy", "layer-details", "layer-details")
                .steps + steps)
        let server = try await MockServer.start(
            script: protocol10 ? script.asProtocol10() : script.withoutClusters())
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 9 }
        XCTAssertTrue(tree)
        model.select(3)
        let ready = await Wait.until {
            await MainActor.run {
                if case .loaded = model.attributes.state { return model.attributes.canEdit }
                return false
            }
        }
        XCTAssertTrue(ready, "the attributes did not arrive, or cannot be changed")
        // The screenshots too, so that what the test sends next is what the script expects.
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)
        return (model, session, server)
    }

    @MainActor
    func panel(for model: InspectionStore) -> (AttributesViewController, NSWindow) {
        let layer = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: layer,
            connection: model.$connection.eraseToAnyPublisher(), loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 700), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.layoutIfNeeded()
        return (controller, window)
    }

    /// Whether neither the view nor any view above it is hidden.
    @MainActor
    static func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    @MainActor
    func row(_ title: String, in controller: AttributesViewController) throws
        -> AttributeRowView
    {
        try XCTUnwrap(controller.attributeRows.map(\.row).first { $0.title == title }, title)
    }

    /// The text area of a row whose value is a text (C-ATTR-05).
    @MainActor
    func textArea(of row: AttributeRowView) throws -> AttributeTextArea {
        try XCTUnwrap(AppListViewTests.descendants(of: try XCTUnwrap(row.editor)) {
            $0 is AttributeTextArea
        }.first as? AttributeTextArea)
    }

    @MainActor
    func field(of row: AttributeRowView) throws -> AttributeEditField {
        try XCTUnwrap(AppListViewTests.descendants(of: try XCTUnwrap(row.editor)) {
            $0 is AttributeEditField
        }.first as? AttributeEditField)
    }

    static func resultSteps(_ groups: [AttributeGroup], as id: UInt32) -> [MockScript.Step] {
        [
            .expect(.setAttribute, as: id),
            .send(Frame(requestID: id, body: .setAttributeResult(SetAttributeResult(
                layerID: 3, attributeGroups: groups)))),
        ]
    }

    // MARK: - C-ATTR-04

    @MainActor
    func test_C_ATTR_04_editableAttributesGetEditorsAndTheRestStayAsTheyWere() async throws {
        let (model, session, server) = try await inspection([])
        let (controller, window) = panel(for: model)
        let rows = controller.attributeRows.map(\.row)
        XCTAssertEqual(rows.count, 22)
        XCTAssertEqual(rows.filter { $0.editor == nil }.map(\.title), ["Text Style", "Frame"])
        // The read-only row has the same controls, read-only (C-ATTR-02).
        let frame = try row("Frame", in: controller)
        let display = try XCTUnwrap(frame.display)
        XCTAssertNotNil(display.superview)
        XCTAssertTrue(display.isReadOnly)
        XCTAssertEqual(display.accessibilityIdentifier(), AttributeEditorView.readOnlyIdentifier)

        // A lost connection takes every editor away (C-WIN-03).
        model.connectionLost()
        XCTAssertTrue(controller.attributeRows.map(\.row).allSatisfy { $0.editor == nil })

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_04_noEditorsForAnOlderServerOrAnAppNotActive() async throws {
        let (model, session, server) = try await inspection([])
        let (controller, window) = panel(for: model)
        func editors() -> Int { controller.attributeRows.map(\.row).filter { $0.editor != nil }.count }
        XCTAssertEqual(editors(), 20)

        model.attributes.appStateDidChange(.background)
        XCTAssertEqual(editors(), 0, "the app is not active")
        model.attributes.appStateDidChange(.active)
        XCTAssertEqual(editors(), 20)
        model.attributes.setEditingSupported(false)
        XCTAssertEqual(editors(), 0, "a source that takes no changes")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-06

    @MainActor
    func test_C_ATTR_06_aRowShowsItsChangeThenWhatCameBackInPlace() async throws {
        let gate = MockGate()
        let results = try Fixtures.setAttributeResults()
        var steps = Self.resultSteps(results[0].attributeGroups, as: 30)
        steps.insert(.hold(gate), at: 1)
        let (model, session, server) = try await inspection(steps)
        let (controller, window) = panel(for: model)
        let text = try row("Text", in: controller)
        let before = controller.attributeRows.map(\.row).map(ObjectIdentifier.init)

        let area = try textArea(of: text)
        area.textView.string = "Welcome back"
        area.textDidChange(Notification(name: NSText.didChangeNotification))
        area.textDidEndEditing(Notification(name: NSText.didEndEditingNotification))
        XCTAssertTrue(text.isSending)
        XCTAssertEqual(area.textView.string, "Welcome back")
        await gate.open()
        let done = await Wait.until { @MainActor in !text.isSending }
        XCTAssertTrue(done)
        XCTAssertEqual(text.plainText, "Welcome back")
        XCTAssertNil(text.failureText)
        // The same rows, updated in place.
        XCTAssertEqual(controller.attributeRows.map(\.row).map(ObjectIdentifier.init), before)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    /// A value within the limits that the app does not take: the row shows the value the app
    /// holds, and a warning sign says the app did not accept it (C-ATTR-06, changed on
    /// 2026-10-12; before, there was no sign).
    @MainActor
    func test_C_ATTR_06_aRejectionWithinTheLimitsSaysSo() async throws {
        let steps: [MockScript.Step] = [
            .expect(.setAttribute, as: 30),
            .send(Frame(requestID: 30, body: .error(ServerError(
                code: .invalidAttributeValue, message: "no")))),
        ]
        let (model, session, server) = try await inspection(steps)
        let (controller, window) = panel(for: model)
        let opacity = try row("Opacity", in: controller)
        let number = try XCTUnwrap(AppListViewTests.descendants(of: try XCTUnwrap(opacity.editor)) {
            $0 is NumberFieldView
        }.first as? NumberFieldView)

        // 70% is within 0 to 1: it goes, and the app refuses it.
        XCTAssertEqual(number.commit("70"), .accepted)
        let settled = await Wait.until { @MainActor in
            model.attributes.edits[AttributeKey(layerID: 3, attributeID: "view.alpha")]
                == .failed(.rejected)
        }
        XCTAssertTrue(settled)
        XCTAssertEqual(opacity.failureText, "The app did not accept this value.")
        XCTAssertFalse(opacity.isSending)
        XCTAssertEqual(number.field.stringValue, "100", "the value the app holds")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    /// Any other failure is a warning sign at the end of the field with the reason on hover;
    /// the row keeps its height.
    @MainActor
    func test_C_ATTR_06_aFailureIsAWarningSignAndTheValueComesBack() async throws {
        let steps: [MockScript.Step] = [
            .expect(.setAttribute, as: 30),
            .send(Frame(requestID: 30, body: .error(ServerError(
                code: .attributeNotEditable, message: "no")))),
        ]
        let (model, session, server) = try await inspection(steps)
        let (controller, window) = panel(for: model)
        let opacity = try row("Opacity", in: controller)
        let height = opacity.frame.height

        let number = try XCTUnwrap(AppListViewTests.descendants(of: try XCTUnwrap(opacity.editor)) {
            $0 is NumberFieldView
        }.first as? NumberFieldView)
        number.commit("50")
        let failed = await Wait.until { @MainActor in opacity.failureText != nil }
        XCTAssertTrue(failed)
        window.layoutIfNeeded()
        XCTAssertEqual(opacity.failureText, "This attribute cannot be changed.")
        XCTAssertEqual(opacity.frame.height, height, "the row keeps its height")
        XCTAssertFalse(opacity.isSending)
        XCTAssertEqual(number.field.stringValue, "100", "the value from before")

        // Another selection clears it.
        model.select(4)
        model.select(3)
        let cleared = await Wait.until { @MainActor in
            (try? self.row("Opacity", in: controller).failureText) == nil
        }
        XCTAssertTrue(cleared)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_06_aFieldBeingTypedInKeepsItsFocusWhenAnAnswerComes() async throws {
        let results = try Fixtures.setAttributeResults()
        let (model, session, server) = try await inspection(
            Self.resultSteps(results[0].attributeGroups, as: 30))
        let (controller, window) = panel(for: model)
        let lines = try field(of: try row("Lines", in: controller))
        XCTAssertTrue(window.makeFirstResponder(lines))
        AttributeEditorTests.type("4", into: lines)

        // Another attribute changes and its answer comes in.
        model.attributes.set(
            AttributeKey(layerID: 3, attributeID: "label.text"), to: .string("Welcome back"),
            continuous: false)
        let answered = await Wait.until { @MainActor in
            (try? self.row("Text", in: controller).plainText) == "Welcome back"
        }
        XCTAssertTrue(answered)
        XCTAssertNotNil(lines.currentEditor(), "still being typed in")
        XCTAssertEqual((lines.currentEditor() as? NSTextView)?.string, "4")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }
}
