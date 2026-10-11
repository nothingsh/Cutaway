import AppKit
import Combine
import DeclarativeAppKit
import XCTest

@testable import CutawayUI

/// Toolchain probe: a Swift 6 target lays out views with DeclarativeAppKit and binds them with
/// DeclarativeCombine, both built in Swift 5 mode.
final class ToolchainTests: XCTestCase {
    @MainActor
    func test_M0_H2_declarativeLibrariesWorkFromASwift6Target() throws {
        let message = CurrentValueSubject<String, Never>("first")
        let controller = PlaceholderViewController(message: message.eraseToAnyPublisher())
        let root = controller.view

        // DeclarativeAppKit built and mounted the stack.
        XCTAssertTrue(root.subviews.contains { $0 is VStack })

        // DeclarativeCombine keeps the label in step with the publisher.
        let label = try XCTUnwrap(
            Self.descendant(of: root, identifier: PlaceholderViewController.messageIdentifier)
                as? NSTextField)
        XCTAssertEqual(label.stringValue, "first")
        message.send("second")
        XCTAssertEqual(label.stringValue, "second")
    }

    @MainActor
    private static func descendant(of view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let match = descendant(of: subview, identifier: identifier) { return match }
        }
        return nil
    }
}
