import AppKit
import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The panels over the preview: the notice (C-DET-04), the loading panel, the notice of a lost
/// connection (C-WIN-03), the tags (C-PREV-16) and the controls (C-PREV-07 to C-PREV-09,
/// C-PREV-17). The screenshots' progress is the toolbar's (C-WIN-06).
final class PreviewPaneTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func session(
        to server: MockServer, requestTimeout: Duration = .seconds(10)
    ) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, requestTimeout: requestTimeout)
        _ = try await session.handshake()
        return session
    }

    /// A preview container in a window that is never shown.
    @MainActor
    private func container(
        _ model: InspectionStore, appName: String = "Demo", width: CGFloat = 700
    ) -> (PreviewPaneViewController, NSWindow) {
        let controller = PreviewPaneViewController(store: model, appName: appName)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: width, height: 600))
        window.layoutIfNeeded()
        return (controller, window)
    }

    @MainActor
    private func view(
        _ identifier: String, in controller: PreviewPaneViewController
    ) throws -> NSView {
        try XCTUnwrap(
            AppListViewTests.descendant(of: controller.view, identifier: identifier), identifier)
    }

    @MainActor
    private func label(
        _ identifier: String, in controller: PreviewPaneViewController
    ) throws -> NSTextField {
        try XCTUnwrap(try view(identifier, in: controller) as? NSTextField)
    }

    // MARK: - C-PREV-07 to 09: the controls

    @MainActor
    private func button(
        _ identifier: String, in controller: PreviewPaneViewController
    ) throws -> NSButton {
        try XCTUnwrap(try view(identifier, in: controller) as? NSButton)
    }

    @MainActor
    private func spacingSlider(_ controller: PreviewPaneViewController) throws -> NSSlider {
        try XCTUnwrap(
            try view(PreviewPaneViewController.spacingIdentifier, in: controller) as? NSSlider)
    }

    @MainActor
    func test_C_PREV_07_theControlsAreUnavailableOnceDisconnected() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        model.setPreviewMode(.threeD)
        let (controller, window) = container(model)
        model.connectionLost()
        for identifier in [
            PreviewPaneViewController.showHiddenIdentifier,
            PreviewPaneViewController.bordersIdentifier,
            PreviewPaneViewController.resetIdentifier,
        ] {
            XCTAssertFalse(try button(identifier, in: controller).isEnabled, identifier)
        }
        XCTAssertFalse(try spacingSlider(controller).isEnabled)
        let preview = try XCTUnwrap(controller.previewController.preview)
        preview.scroll(dx: 10, dy: 10, command: false, at: NSPoint(x: 50, y: 50))
        XCTAssertEqual(model.camera, .standard3D, "the camera no longer moves")
        withExtendedLifetime(window) {}
    }
}
