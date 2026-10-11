import AppKit
import CutawayModel
import CutawayRender
import CutawayTestSupport
import CutawayUI
import XCTest

@testable import Cutaway

/// End to end: the running app shows the fixture in 2D and in 3D. The hierarchy and the
/// screenshots both come over the connection from MockServer.
final class PreviewExitTests: XCTestCase {
    @MainActor
    private func waitForFrame(after count: Int, of preview: PreviewView) async throws {
        let deadline = Date().addingTimeInterval(5)
        while preview.frameCount <= count, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(
            preview.frameCount, count,
            "the preview did not redraw\(AppWindows.displayAsleepNote)")
    }

    private func assertClose(
        _ actual: Pixel, _ expected: Pixel, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for (a, e) in [
            (actual.blue, expected.blue), (actual.green, expected.green),
            (actual.red, expected.red), (actual.alpha, expected.alpha),
        ] {
            XCTAssertEqual(
                Int(a), Int(e), accuracy: 2, "\(actual) vs \(expected): \(message)",
                file: file, line: line)
        }
    }

    @MainActor
    func test_C_PREV_02_theRunningAppShowsTheFixtureIn2DAnd3D() async throws {
        let server = try await AppWindows.startMockServer(
            try .fixtures("handshake", "app-icon", "hierarchy", "layer-details"))
        addTeardownBlock {
            // Leave the app as it was for the other tests, even when this one failed.
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)

        // The layers arrive and the preview is there.
        let deadline = Date().addingTimeInterval(5)
        while (AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)?
            .numberOfRows != AppWindows.fixtureRowsAtFirst, Date() < deadline
        {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            (AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)?
                .numberOfRows, AppWindows.fixtureRowsAtFirst, "the layers did not arrive")
        let preview = try XCTUnwrap(
            AppWindows.views(identifier: PreviewView.identifier).first as? PreviewView)
        XCTAssertTrue(AppWindows.isShown(preview))

        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        let model = try XCTUnwrap(delegate.store)
        let inspection = try XCTUnwrap(model.inspectedApp.flatMap { model.inspection(at: $0) })
        // The screenshots arrive over the connection. Until the preview has a
        // size and draws the layer, there is nothing to sample.
        let arrived = try await AppWindows.waitFor(
            Pixel(blue: 0, green: 255, red: 0, alpha: 255), at: 4, in: preview)
        XCTAssertTrue(arrived, "layer 4's screenshot did not appear")

        let red = Pixel(blue: 0, green: 0, red: 255, alpha: 255)
        let green = Pixel(blue: 0, green: 255, red: 0, alpha: 255)
        assertClose(try AppWindows.centerPixel(of: 3, in: preview), red, "2D, layer 3")
        assertClose(try AppWindows.centerPixel(of: 4, in: preview), green, "2D, layer 4")

        // 3D, as a click on the switch does.
        let control = try XCTUnwrap(
            AppWindows.views(identifier: "inspection.mode").first as? NSSegmentedControl)
        let frames = preview.frameCount
        control.selectedSegment = 1
        control.sendAction(control.action, to: control.target)
        XCTAssertEqual(inspection.previewMode, .threeD)
        try await waitForFrame(after: frames, of: preview)
        // The view turns over a short while (C-PREV-11); the still 3D picture is sampled.
        _ = try await AppWindows.samples(whileInTransition: preview) {}
        assertClose(try AppWindows.centerPixel(of: 3, in: preview), red, "3D, layer 3")
        assertClose(try AppWindows.centerPixel(of: 4, in: preview), green, "3D, layer 4")

        let connections = await server.connectionCount
        XCTAssertEqual(connections, 1)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        // Leave the app as it was for the other tests.
        AppWindows.closeInspectors()
        await server.stop()
        let gone = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        XCTAssertNil(gone)
    }
}
