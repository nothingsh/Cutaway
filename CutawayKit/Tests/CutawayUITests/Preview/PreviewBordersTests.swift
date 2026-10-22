import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The borders' colours by kind (C-PREV-17) keep each layer's icon from the last tree: a tree
/// that comes again gives the colours a fresh look at it gives.
final class PreviewBordersTests: XCTestCase {
    /// The `hierarchy` fixture with layer 3, a label, made a button.
    private func treeWithAButton() throws -> LayerTree {
        var hierarchy = try Fixtures.hierarchy()
        let index = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 3 })
        hierarchy.nodes[index].viewClassName = "UIButton"
        hierarchy.nodes[index].viewDisplayClassName = "UIButton"
        hierarchy.nodes[index].viewBaseClassName = "UIButton"
        return try LayerTree(hierarchy)
    }

    @MainActor
    private func colors(_ trees: [LayerTree], onlyAppClasses: Bool = false) -> [UInt64: SIMD4<Float>] {
        var borders = PreviewBorders()
        borders.options = BorderOptions(style: .byKind, onlyAppClasses: onlyAppClasses)
        var colors: [UInt64: SIMD4<Float>] = [:]
        for tree in trees {
            borders.tree = tree
            colors = borders.borderColors(plain: .zero, dark: false)
        }
        return colors
    }

    @MainActor
    func test_C_PREV_17_aTreeThatComesAgainIsColouredAsAFreshOneIs() throws {
        let label = try LayerTree(try Fixtures.hierarchy())
        let button = try treeWithAButton()
        XCTAssertNotEqual(colors([label])[3], colors([button])[3], "a label and a button differ")
        // The kinds kept from the earlier tree are not taken for those of the layer that changed.
        XCTAssertEqual(colors([label, button]), colors([button]))
        XCTAssertEqual(colors([button, label]), colors([label]))
        XCTAssertEqual(
            colors([label, button], onlyAppClasses: true), colors([button], onlyAppClasses: true))

        // A layer gone from the tree has no colour.
        var fewer = try Fixtures.hierarchy()
        fewer.nodes.removeAll { $0.id == 7 }
        let left = colors([label, try LayerTree(fewer)])
        XCTAssertNotNil(colors([label])[7])
        XCTAssertNil(left[7])
        XCTAssertEqual(left, colors([try LayerTree(fewer)]))
    }
}
