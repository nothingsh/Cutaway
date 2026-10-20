import AppKit
import CutawayRender
import CutawayTestSupport
import CutawayUI
import XCTest

@testable import Cutaway

/// Looks at what the running app shows, through AppKit alone.
@MainActor
enum AppWindows {
    /// Every view with this accessibility identifier in `view` and below it.
    static func views(in view: NSView, identifier: String) -> [NSView] {
        var matches = view.accessibilityIdentifier() == identifier ? [view] : []
        for subview in view.subviews {
            matches += views(in: subview, identifier: identifier)
        }
        return matches
    }

    /// Every view with this accessibility identifier in any of the app's windows, their
    /// toolbars included.
    static func views(identifier: String) -> [NSView] {
        // A closed inspector window lingers until its closing animation is over; its views
        // are not the app's any more. The launcher counts even when it is put away.
        let launcher = try? coordinator().launcher.window
        let windows = NSApplication.shared.windows.filter { $0.isVisible || $0 === launcher }
        return windows.flatMap { window in
            let roots = [window.contentView].compactMap { $0 }
                + (window.toolbar?.items.compactMap(\.view) ?? [])
            return roots.flatMap { views(in: $0, identifier: identifier) }
        }
    }

    /// The app's windows coordinator.
    static func coordinator() throws -> WindowCoordinator {
        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        return try XCTUnwrap(delegate.coordinator)
    }

    /// The inspector windows that are open.
    static func inspectorWindows() -> [NSWindow] {
        NSApplication.shared.windows.filter {
            $0.isVisible && $0.windowController is InspectorWindowController
        }
    }

    /// Closes every inspector window, which brings back the launcher: a test leaves the app
    /// as it found it.
    static func closeInspectors() {
        for window in inspectorWindows() { window.close() }
    }

    /// Whether neither the view nor any view above it is hidden.
    static func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    /// The row of the app named `name` in the app list.
    static func appRow(named name: String) -> NSView? {
        for label in views(identifier: "app.name") {
            guard (label as? NSTextField)?.stringValue == name else { continue }
            var ancestor = label.superview
            while let candidate = ancestor, !(candidate is NSTableCellView) {
                ancestor = candidate.superview
            }
            if let ancestor { return ancestor }
        }
        return nil
    }

    static func waitForAppRow(
        named name: String, toExist: Bool, within seconds: TimeInterval
    ) async -> NSView? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let row = appRow(named: name)
            if (row != nil) == toExist { return row }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return appRow(named: name)
    }

    /// Starts a MockServer on one of the ports the app scans.
    static func startMockServer(_ script: MockScript) async throws -> MockServer {
        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        let ports = delegate.simulatorPorts
        var started: MockServer?
        for port in ports {
            started = try? await MockServer.start(port: port, script: script)
            if started != nil { break }
        }
        return try XCTUnwrap(started, "every port the app scans is in use: \(ports)")
    }

    /// Waits for the app's row and its icon request, then chooses the app as the keyboard
    /// does: selects its row and presses Return. MockServer answers in the script's order, and
    /// the icon comes before the hierarchy there.
    static func chooseApp(named name: String, server: MockServer) async throws {
        let found = await waitForAppRow(named: name, toExist: true, within: 5)
        XCTAssertNotNil(found, "the app did not list \(name)")
        let deadline = Date().addingTimeInterval(3)
        while await server.receivedFrames.count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        // Looked up again: the list reloads when the icon arrives, and for a moment the row
        // has no view.
        let again = await waitForAppRow(named: name, toExist: true, within: 3)
        let row = try XCTUnwrap(again, "\(name)'s row is gone")
        var ancestor = row.superview
        while let candidate = ancestor, !(candidate is NSTableView) {
            ancestor = candidate.superview
        }
        let table = try XCTUnwrap(ancestor as? NSTableView)
        let index = table.row(for: row)
        XCTAssertGreaterThanOrEqual(index, 0)
        try open(row: index, of: table)
    }

    /// Selects a row of the app list and presses Return on it.
    static func open(row: Int, of table: NSTableView) throws {
        table.selectRowIndexes([row], byExtendingSelection: false)
        let returnKey = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
            keyCode: 36))
        table.keyDown(with: returnKey)
    }

    /// The rows the list first shows for the `hierarchy` fixture: it opens down to its view
    /// controller, layer 2, and layers 4, 6 and 13 start collapsed (C-HIER-09).
    static let fixtureRowsAtFirst = 8

    /// Expands every layer of the inspection, as the list's Expand All does: for tests that
    /// work with the whole `hierarchy` fixture in view.
    static func expandAll() throws {
        let model = try XCTUnwrap((NSApplication.shared.delegate as? AppDelegate)?.store)
        try XCTUnwrap(model.inspectedApp.flatMap { model.inspection(at: $0) }, "no inspection")
            .expandAll()
    }

    // MARK: - The preview's pixels

    /// Whether two pixels differ by at most 2 in every channel.
    static func isClose(_ a: Pixel, _ b: Pixel) -> Bool {
        abs(Int(a.blue) - Int(b.blue)) <= 2 && abs(Int(a.green) - Int(b.green)) <= 2
            && abs(Int(a.red) - Int(b.red)) <= 2 && abs(Int(a.alpha) - Int(b.alpha)) <= 2
    }

    /// How much of `color` is in `pixel` over `behind`, from 0 to 1, when the pixel is a mix
    /// of the two, as where a line covers part of it; nil when it is not such a mix.
    static func share(of color: Pixel, in pixel: Pixel, over behind: Pixel) -> Double? {
        let channels: [KeyPath<Pixel, UInt8>] = [\.blue, \.green, \.red]
        let spans = channels.map { Double(color[keyPath: $0]) - Double(behind[keyPath: $0]) }
        // Read off the channel the two differ most in; the others must agree with it.
        guard let widest = spans.indices.max(by: { abs(spans[$0]) < abs(spans[$1]) }),
              abs(spans[widest]) >= 32
        else { return nil }
        let share =
            (Double(pixel[keyPath: channels[widest]]) - Double(behind[keyPath: channels[widest]]))
                / spans[widest]
        let mixed = channels.indices.allSatisfy { index in
            let expected = Double(behind[keyPath: channels[index]]) + share * spans[index]
            return abs(expected - Double(pixel[keyPath: channels[index]])) <= 4
        }
        return mixed && share > -0.05 && share < 1.05 ? share : nil
    }

    /// The pixel of the preview's snapshot at the middle of a layer.
    static func centerPixel(of id: UInt64, in preview: PreviewView) throws -> Pixel {
        let image = try preview.snapshot()
        let point = try XCTUnwrap(preview.imagePoint(ofCenterOf: id), "layer \(id) is not drawn")
        return image.pixel(x: Int(point.x), y: Int(point.y))
    }

    /// Waits until the middle of a layer is `color`. Returns whether it got there. Until the
    /// preview has a size and draws the layer, there is nothing to sample.
    static func waitFor(
        _ color: Pixel, at id: UInt64, in preview: PreviewView, within seconds: TimeInterval = 5
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if preview.bounds.width > 0, preview.bounds.height > 0,
               preview.imagePoint(ofCenterOf: id) != nil,
               isClose(try centerPixel(of: id, in: preview), color)
            {
                return true
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(isDisplayAsleep, "the display is asleep: the preview does not draw")
        return false
    }

    /// Takes `sample` every few milliseconds while the preview is in a transition, then once
    /// more when it has ended (C-PREV-11, C-PREV-12): the last sample is of the still picture.
    static func samples<T>(
        whileInTransition preview: PreviewView, within seconds: TimeInterval = 3,
        _ sample: () throws -> T
    ) async throws -> [T] {
        var samples: [T] = []
        let deadline = Date().addingTimeInterval(seconds)
        while preview.isInTransition, Date() < deadline {
            samples.append(try sample())
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(
            preview.isInTransition, "the transition did not end\(displayAsleepNote)")
        try await waitForPendingFrame(of: preview)
        samples.append(try sample())
        return samples
    }

    /// Waits until the preview has drawn what it was last given. Showing a list asks for a
    /// frame at once, and the frame comes with the next display pass; a test that wakes up in
    /// between would count that frame as drawn after the change.
    static func waitForPendingFrame(
        of preview: PreviewView, within seconds: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while preview.isDrawingPending, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(
            preview.isDrawingPending,
            "the preview did not draw what it was given\(displayAsleepNote)")
    }

    /// Whether the main display is asleep: the preview's clock ticks with the display, so
    /// transitions do not end and nothing is drawn while it sleeps.
    static var isDisplayAsleep: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// Added to the message of a wait for drawing that failed: whether the display was asleep.
    static var displayAsleepNote: String {
        isDisplayAsleep ? " (the display is asleep; keep it awake, e.g. with caffeinate -du)" : ""
    }
}
