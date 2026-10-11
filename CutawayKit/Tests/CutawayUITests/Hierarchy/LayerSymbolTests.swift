import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The symbol of a layer in the list (C-HIER-01): windows, views by the end of their class
/// name, and layers that back no view.
final class LayerSymbolTests: XCTestCase {
    private func node(
        parent: UInt64 = 1, view: String? = nil, layer: String = "CALayer"
    ) -> LayerNode {
        LayerNode(
            id: 2, parentID: parent, className: layer, displayClassName: layer,
            viewClassName: view, viewDisplayClassName: view, bounds: nil, position: nil,
            anchorPoint: nil, transform: nil, zPosition: 0, isHidden: false, opacity: 1,
            masksToBounds: false)
    }

    func test_C_HIER_01_aWindowsRootLayerIsAWindow() {
        XCTAssertEqual(LayerSymbol.name(for: node(parent: 0, view: "UIWindow")), "macwindow")
        XCTAssertEqual(LayerSymbol.name(for: node(parent: 0)), "macwindow")
    }

    func test_C_HIER_01_aLayerThatBacksNoViewIsDashed() {
        XCTAssertEqual(LayerSymbol.name(for: node(layer: "CAShapeLayer")), "square.dashed")
        XCTAssertEqual(LayerSymbol.name(for: node(view: "")), "square.dashed")
        XCTAssertEqual(LayerSymbol.name(for: nil), "square.dashed")
    }

    func test_C_HIER_01_aViewIsKnownByTheEndOfItsClassName() {
        XCTAssertEqual(LayerSymbol.name(forViewClass: "UILabel"), "textformat")
        XCTAssertEqual(LayerSymbol.name(forViewClass: "CheckoutButton"), "button.horizontal")
        XCTAssertEqual(LayerSymbol.name(forViewClass: "UITableViewCell"), "rectangle.split.1x2")
        XCTAssertEqual(LayerSymbol.name(forViewClass: "UITableView"), "list.bullet.rectangle")
        XCTAssertEqual(LayerSymbol.name(forViewClass: "MyApp.ProfileImageView"), "photo")
        XCTAssertEqual(LayerSymbol.name(forViewClass: "_UIHostingView<ContentView>"), "swift")
        XCTAssertEqual(LayerSymbol.name(forViewClass: "UIView"), "square")
        XCTAssertEqual(LayerSymbol.name(forViewClass: "CardView"), "square")
    }

    func test_C_HIER_01_aSummaryNamesTheLayerItsClassAndSize() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        let label = try XCTUnwrap(LayerSummary(tree, 3))
        XCTAssertEqual(label.title, "UILabel")
        XCTAssertEqual(label.symbol, "textformat")
        XCTAssertTrue(label.subtitle.hasSuffix("· ID 3"), label.subtitle)
        XCTAssertEqual(label.size, "200 × 24")
        // A layer that backs no view has only its ID beneath its title.
        let shape = try XCTUnwrap(LayerSummary(tree, 5))
        XCTAssertEqual(shape.subtitle, "ID 5")
        XCTAssertNil(LayerSummary(tree, nil))
        XCTAssertNil(LayerSummary(tree, 999))
    }
}
