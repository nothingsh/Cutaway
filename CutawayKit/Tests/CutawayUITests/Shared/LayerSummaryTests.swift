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

/// The ancestors in the attribute panel's header (C-ATTR-16): who they are, their short
/// names, and how many of them fit on the line.
final class LayerAncestorsTests: XCTestCase {
    /// A chain of `depth` views under a window, each the next one's parent: 1 is the window's
    /// root layer, `depth + 1` the deepest view. View 3 is held by `contentView`.
    static func chain(depth: Int) throws -> LayerTree {
        var nodes = [LayerNode(
            id: 1, parentID: 0, className: "UIWindowLayer", displayClassName: "UIWindowLayer",
            viewClassName: "UIWindow", viewDisplayClassName: "UIWindow", bounds: nil,
            position: nil, anchorPoint: nil, transform: nil, zPosition: 0, isHidden: false,
            opacity: 1, masksToBounds: false)]
        for id in UInt64(2)...UInt64(depth + 1) {
            var node = LayerNode(
                id: id, parentID: id - 1, className: "CALayer", displayClassName: "CALayer",
                viewClassName: "View\(id)", viewDisplayClassName: "View\(id)", bounds: nil,
                position: nil, anchorPoint: nil, transform: nil, zPosition: 0, isHidden: false,
                opacity: 1, masksToBounds: false)
            if id == 3 {
                node.memberReferences = [MemberReference(
                    ownerClassName: "View2", ownerDisplayClassName: "View2", name: "contentView")]
            }
            nodes.append(node)
        }
        return try LayerTree(Hierarchy(nodes: nodes, keyWindowID: 1))
    }
}
