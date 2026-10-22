import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// What the panel says about the selected layer outside its attributes: its classes, its
/// addresses and where it is held (C-ATTR-10, C-ATTR-11, C-HIER-07). The addresses are the
/// `hierarchy` fixture's, by the formulas of Protocol/fixtures/README.md.
final class LayerSummaryTests: XCTestCase {
    func test_C_ATTR_11_withoutAddressesThereAreNone() throws {
        let tree = try LayerTree(Fixtures.withoutProtocol11(try Fixtures.hierarchy()))
        let label = try XCTUnwrap(LayerSummary(tree, 3))
        XCTAssertNil(label.viewAddress)
        XCTAssertNil(label.layerAddress)
        XCTAssertNil(try XCTUnwrap(LayerSummary(tree, 2)).controllerAddress)
        // The header's second line does not depend on addresses.
        XCTAssertEqual(label.subtitle, "HomeViewController.titleLabel")
    }
}
