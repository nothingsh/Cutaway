import AppKit
import XCTest

@testable import CutawayUI

/// A text's field in a list that scrolls (C-ATTR-05, C-ATTR-12). Reported by the user
/// (2026-10-20): with the pointer on a text's field, two fingers did not scroll the attribute
/// panel. The field scrolls only a text longer than it shows, and only while it can go further
/// that way; otherwise the scroll goes on to the list. Checked by where the event goes: a view
/// that is never shown does not scroll for a wheel.
@MainActor
final class TextAreaScrollingTests: XCTestCase {
    /// A text field 22 points tall near the top of a list 300 points tall whose content is
    /// 2,000 points tall, in a window that is never shown.
    private func list(text: String) -> (list: RecordingView, area: AttributeTextArea, window: NSWindow) {
        let area = AttributeTextArea(name: "Label")
        area.shownText = text
        let document = RecordingView(frame: NSRect(x: 0, y: 0, width: 300, height: 2000))
        area.frame = NSRect(x: 10, y: 100, width: 200, height: 80)
        area.translatesAutoresizingMaskIntoConstraints = true
        document.addSubview(area)
        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        outer.documentView = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = outer
        window.layoutIfNeeded()
        area.layoutSubtreeIfNeeded()
        return (document, area, window)
    }

    /// A scroll of whole lines, as a mouse's wheel sends: negative is towards the end.
    private func wheel(lines: Int32) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0))
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    func test_C_ATTR_05_aTextThatFitsLetsTheListScroll() throws {
        let (list, area, window) = list(text: "Welcome")
        area.scrollView.scrollWheel(with: try wheel(lines: -5))
        area.scrollView.scrollWheel(with: try wheel(lines: 5))
        XCTAssertEqual(list.scrolls, 2, "both went on to the list")
        withExtendedLifetime(window) {}
    }

    func test_C_ATTR_05_aLongTextScrollsInItsFieldThenLetsTheListScroll() throws {
        let long = (1...40).map { "Line \($0)" }.joined(separator: "\n")
        let (list, area, window) = list(text: long)
        area.textView.frame.size.height = 1000
        // Towards its start, where it is: the list takes it.
        area.scrollView.scrollWheel(with: try wheel(lines: 5))
        XCTAssertEqual(list.scrolls, 1)
        // Towards its end: the field keeps it.
        area.scrollView.scrollWheel(with: try wheel(lines: -5))
        XCTAssertEqual(list.scrolls, 1, "the field took it")
        // At its end, further towards it: the list takes it.
        area.scrollView.contentView.scroll(to: NSPoint(
            x: 0, y: area.textView.frame.height - area.scrollView.contentView.bounds.height))
        area.scrollView.scrollWheel(with: try wheel(lines: -5))
        XCTAssertEqual(list.scrolls, 2)
        withExtendedLifetime(window) {}
    }
}

/// The list's content: counts the scrolls that reach it, which a list would scroll by.
final class RecordingView: NSView {
    private(set) var scrolls = 0
    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        scrolls += 1
    }
}
