import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

/// Marking the nodes the app answered `Excluded` for (C-DET-11): it says whether the tree
/// changed, and a node marked already costs nothing, however large the tree (C-SCALE-01).
final class CaptureExcludedMarkingTests: XCTestCase {
    /// 1 → 2 → 3, and 4 under 1.
    private func tree(excluding wireExcluded: Set<UInt64> = []) throws -> LayerTree {
        let nodes = [(1, 0), (2, 1), (3, 2), (4, 1)].map { id, parent in
            var node = LayerTreeTests.node(UInt64(id), parent: UInt64(parent))
            node.isCaptureExcluded = wireExcluded.contains(UInt64(id))
            return node
        }
        return try LayerTree(Hierarchy(nodes: nodes, keyWindowID: 0))
    }

    private func excluded(_ tree: LayerTree) -> [UInt64] {
        tree.ids.filter { tree.node($0)?.isCaptureExcluded == true }
    }

    func test_C_DET_11_markingSaysWhetherTheTreeChanged() throws {
        var tree = try tree()
        XCTAssertTrue(tree.markCaptureExcluded([2]))
        XCTAssertEqual(excluded(tree), [2, 3])

        let marked = tree
        XCTAssertFalse(tree.markCaptureExcluded([2]), "marked again")
        XCTAssertFalse(tree.markCaptureExcluded([3]), "below a marked node")
        XCTAssertFalse(tree.markCaptureExcluded([99]), "not in the tree")
        XCTAssertFalse(tree.markCaptureExcluded([]))
        XCTAssertEqual(tree, marked)

        XCTAssertTrue(tree.markCaptureExcluded([3, 4]))
        XCTAssertEqual(excluded(tree), [2, 3, 4])
    }

    func test_C_DET_11_whatIsBelowANodeTheAppMarkedIsMarkedToo() throws {
        var tree = try tree(excluding: [2])
        XCTAssertEqual(excluded(tree), [2])
        XCTAssertTrue(tree.markCaptureExcluded([2]))
        XCTAssertEqual(excluded(tree), [2, 3])
    }

    func test_C_SCALE_01_markingAMarkedLayerOfTenThousandDoesNotCopyTheTree() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let original = try LayerTree(ScaleScene.hierarchy())
        let leaf = try XCTUnwrap(original.ids.last)
        var tree = original
        XCTAssertTrue(tree.markCaptureExcluded([leaf]))
        // Every chunk with an `Excluded` answer marks again what earlier ones marked.
        let measured = try ScaleScene.median(of: 21) {
            let start = ContinuousClock.now
            for _ in 0..<100 {
                XCTAssertFalse(tree.markCaptureExcluded([leaf]))
            }
            return ContinuousClock.now - start
        }
        let report = ScaleScene.report("100 markings of a marked layer", measured, limit: .milliseconds(1))
        if ScaleScene.checksLimits { XCTAssertLessThanOrEqual(measured, .milliseconds(1), report) }
    }
}
