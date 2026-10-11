import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

/// C-HIER-08: a subtree of the tree replaced by the answer to `GetSubtree`.
final class SubtreeReplacementTests: XCTestCase {
    private static func node(_ id: UInt64, parent: UInt64, className: String = "CALayer")
        -> LayerNode
    {
        LayerTreeTests.node(id, parent: parent, className: className, displayClassName: className)
    }

    /// The `hierarchy` fixture's tree: 1 > 2 > (3, 4 > 5, 6 > 7, 8, 9).
    private func fixtureTree() throws -> LayerTree {
        try LayerTree(try Fixtures.hierarchy())
    }

    private func replacing(_ tree: LayerTree, with nodes: [LayerNode], keyWindowID: UInt64 = 1)
        -> Result<LayerTree, SubtreeError>
    {
        do {
            return .success(try tree.replacingSubtree(with: Hierarchy(
                nodes: nodes, keyWindowID: keyWindowID)))
        } catch {
            return .failure(error)
        }
    }

    func test_C_HIER_08_theFixturesSubtreeLeavesTheTreeAsItWas() throws {
        let tree = try fixtureTree()
        let replaced = try tree.replacingSubtree(with: try Fixtures.subtreeOfNode4())
        XCTAssertEqual(replaced, tree)
    }

    func test_C_HIER_08_onlyTheSubtreeChanges() throws {
        let tree = try fixtureTree()
        let hierarchy = try Fixtures.hierarchy()
        // Node 4 now holds 5, renamed, and a new node 10; 5 keeps its place.
        var four = try XCTUnwrap(tree.node(4))
        four.opacity = 0.5
        let answer = [four, Self.node(5, parent: 4, className: "CAShapeLayer"),
                      Self.node(10, parent: 4)]
        let replaced = try tree.replacingSubtree(with: Hierarchy(nodes: answer, keyWindowID: 1))

        XCTAssertEqual(replaced.ids, [1, 2, 3, 4, 5, 10, 6, 7, 8, 9])
        XCTAssertEqual(replaced.children(of: 4), [5, 10])
        XCTAssertEqual(replaced.children(of: 2), [3, 4, 6, 8, 9])
        XCTAssertEqual(replaced.node(4), four)
        XCTAssertEqual(replaced.node(5)?.className, "CAShapeLayer")
        XCTAssertEqual(replaced.parent(of: 10), 4)
        // Everything outside the subtree is as it was, fields included.
        for node in hierarchy.nodes where ![4, 5].contains(node.id) {
            XCTAssertEqual(replaced.node(node.id), node, "layer \(node.id)")
        }
        XCTAssertEqual(replaced.keyWindowID, 1)
    }

    func test_C_HIER_08_layersThatAreGoneLeaveTheTree() throws {
        let tree = try fixtureTree()
        // Node 6 lost its child 7.
        let six = try XCTUnwrap(tree.node(6))
        let replaced = try tree.replacingSubtree(with: Hierarchy(nodes: [six], keyWindowID: 1))
        XCTAssertEqual(replaced.ids, [1, 2, 3, 4, 5, 6, 8, 9])
        XCTAssertFalse(replaced.contains(7))
        XCTAssertEqual(replaced.children(of: 6), [])
    }

    func test_C_HIER_08_aWindowsRootCanBeReplaced() throws {
        let tree = try fixtureTree()
        let one = try XCTUnwrap(tree.node(1))
        let replaced = try tree.replacingSubtree(with: Hierarchy(
            nodes: [one, Self.node(20, parent: 1)], keyWindowID: 1))
        XCTAssertEqual(replaced.ids, [1, 20])
        XCTAssertEqual(replaced.roots, [1])
    }

    func test_C_HIER_08_otherWindowsStayInPlace() throws {
        let tree = try LayerTree(Hierarchy(
            nodes: [Self.node(1, parent: 0), Self.node(2, parent: 1),
                    Self.node(3, parent: 0), Self.node(4, parent: 3)],
            keyWindowID: 3))
        let replaced = try tree.replacingSubtree(with: Hierarchy(
            nodes: [Self.node(1, parent: 0), Self.node(5, parent: 1)], keyWindowID: 1))
        XCTAssertEqual(replaced.ids, [1, 5, 3, 4])
        XCTAssertEqual(replaced.roots, [1, 3])
        // The answer says which window is key now (P-HIER-10).
        XCTAssertEqual(replaced.keyWindowID, 1)
    }

    func test_C_HIER_08_aTreeThatIsOnlyParentsFirstLosesTheWholeOldSubtree() throws {
        // Breadth first: 4 is inside 2 but comes after 3, so the subtree is not one run.
        let tree = try LayerTree(Hierarchy(
            nodes: [Self.node(1, parent: 0), Self.node(2, parent: 1), Self.node(3, parent: 1),
                    Self.node(4, parent: 2)],
            keyWindowID: 1))
        let replaced = try tree.replacingSubtree(with: Hierarchy(
            nodes: [Self.node(2, parent: 1)], keyWindowID: 1))
        XCTAssertEqual(replaced.ids, [1, 2, 3])
    }

    func test_C_HIER_08_answersThatAreNotThisTreesSubtreeAreRefused() throws {
        let tree = try fixtureTree()
        let four = try XCTUnwrap(tree.node(4))

        XCTAssertEqual(replacing(tree, with: []), .failure(.empty))
        XCTAssertEqual(
            replacing(tree, with: [Self.node(99, parent: 2)]), .failure(.rootNotInTree(99)))
        // Node 4 now sits in node 6: it moved.
        var moved = four
        moved.parentID = 6
        XCTAssertEqual(replacing(tree, with: [moved]), .failure(.rootMoved(4)))
        // A node whose parent is not an earlier node of the answer.
        XCTAssertEqual(
            replacing(tree, with: [four, Self.node(11, parent: 2)]),
            .failure(.notInSubtree(id: 11, parentID: 2)))
        XCTAssertEqual(
            replacing(tree, with: [four, Self.node(12, parent: 13), Self.node(13, parent: 4)]),
            .failure(.notInSubtree(id: 12, parentID: 13)))
        // Node 7 moved from node 6 into node 4: it would be in the tree twice.
        XCTAssertEqual(
            replacing(tree, with: [four, Self.node(7, parent: 4)]),
            .failure(.invalid(.duplicateID(7))))
    }
}
