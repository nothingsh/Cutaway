import AppKit
import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The attribute panel's header follows the selected layer (C-ATTR-16, C-ATTR-18) at the cost
/// of one summary for each change (C-SCALE-01: a new selection shows within 100 ms): the
/// summary walks to the root and looks the classes up in the project's index, so every part of
/// the header that follows it shares the one made.
@MainActor
final class AttributesHeaderTests: XCTestCase {
    private final class Counter {
        var count = 0
    }

    func test_C_SCALE_01_eachChangeOfTheSelectedLayerIsSummarizedOnce() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        let selected = CurrentValueSubject<UInt64?, Never>(3)
        let summaries = Counter()
        let layer = selected
            .map { id -> LayerSummary? in
                summaries.count += 1
                return LayerSummary(tree, id)
            }
            .eraseToAnyPublisher()
        let store = AttributesStore(
            session: Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")))
        let controller = AttributesViewController(
            store: store, appName: "Demo", inputs: AttributesPanelInputs(layer: layer), loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.layoutIfNeeded()
        XCTAssertEqual(summaries.count, 1, "the layer there is when the panel is built")

        selected.send(9)
        XCTAssertEqual(summaries.count, 2, "one more for the next layer")
        // Every part of the header follows it.
        let title = try XCTUnwrap(AppListViewTests.descendants(
            of: controller.view, identifier: AttributesViewController.headerTitleIdentifier).first as? NSTextField)
        XCTAssertEqual(title.stringValue, try XCTUnwrap(LayerSummary(tree, 9)).title)
        let subtitle = try XCTUnwrap(AppListViewTests.descendants(
            of: controller.view, identifier: AttributesViewController.headerSubtitleIdentifier)
            .first as? NSTextField)
        XCTAssertEqual(subtitle.stringValue, LayerSummary(tree, 9)?.headerLine ?? "")

        selected.send(nil)
        XCTAssertEqual(summaries.count, 3)
        let header = try XCTUnwrap(AppListViewTests.descendants(
            of: controller.view, identifier: AttributesViewController.headerIdentifier).first)
        XCTAssertTrue(header.isHidden, "no layer, no header")
        window.close()
    }
}
