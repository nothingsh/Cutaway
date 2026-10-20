import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-HIER-17: a node the app asks to start collapsed does, with everything below it, where
/// the default expansion (C-HIER-09) is used; the person can still open it every way.
final class CollapsedByDefaultTests: XCTestCase {
    /// The fixture with these nodes marked. Node 10, a virtual node inside the collapsed
    /// node 4, is marked in the fixture itself.
    private static func marking(_ ids: Set<UInt64>, in hierarchy: Hierarchy) -> Hierarchy {
        var hierarchy = hierarchy
        for index in hierarchy.nodes.indices where ids.contains(hierarchy.nodes[index].id) {
            hierarchy.nodes[index].isCollapsedByDefault = true
        }
        return hierarchy
    }

    @MainActor
    private func model() -> InspectionStore {
        InspectionStore(session: Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")))
    }

    // MARK: - The rule

    func test_C_HIER_17_aMarkedNodeStartsCollapsedWithEverythingBelow() throws {
        // The window, above the view controller on show (2), is marked: neither opens.
        let marked = Self.marking([1], in: try Fixtures.hierarchy())
        XCTAssertEqual(try LayerTree(marked).defaultExpansion(), [])
        // Marked on the view controller's root view itself: the window still opens.
        let root = Self.marking([2], in: try Fixtures.hierarchy())
        XCTAssertEqual(try LayerTree(root).defaultExpansion(), [1])
    }

    func test_C_HIER_17_unmarkedTheRuleIsAsBefore() throws {
        let unmarked = Fixtures.withoutProtocol12(try Fixtures.hierarchy())
        XCTAssertEqual(try LayerTree(unmarked).defaultExpansion(), [1, 2])
        // Without a view controller on show everything that can be seen opens, the marked
        // virtual node 10 apart.
        var noController = try Fixtures.hierarchy()
        let two = noController.nodes.firstIndex { $0.id == 2 }!
        noController.nodes[two].viewControllerClassName = nil
        noController.nodes[two].viewControllerDisplayClassName = nil
        XCTAssertEqual(try LayerTree(noController).defaultExpansion(), [1, 2, 4, 6, 13])
        XCTAssertEqual(
            try LayerTree(Fixtures.withoutProtocol12(noController)).defaultExpansion(),
            [1, 2, 4, 6, 10, 13])
    }

    // MARK: - Where the rule is used

    @MainActor
    func test_C_HIER_17_aNewInspectionStartsWithTheMarkedNodeCollapsed() throws {
        let model = model()
        model.apply(Self.marking([1], in: try Fixtures.hierarchy()))
        XCTAssertFalse(model.isExpanded(1))
        XCTAssertFalse(model.isExpanded(2), "the view controller's root view below it")
        // A leaf counts as expanded, marked or not: there is nothing to fold.
        XCTAssertTrue(model.isExpanded(3))
    }

    @MainActor
    func test_C_HIER_17_expandAllAndExpandToALevelOpenAMarkedNode() throws {
        let model = model()
        model.apply(Self.marking([1], in: try Fixtures.hierarchy()))
        model.expandAll()
        XCTAssertTrue(model.isExpanded(1))
        XCTAssertTrue(model.isExpanded(2))
        XCTAssertTrue(model.isExpanded(10))

        let levels = self.model()
        levels.apply(Self.marking([1], in: try Fixtures.hierarchy()))
        levels.expand(toDepth: 2)
        XCTAssertTrue(levels.isExpanded(1))
        XCTAssertTrue(levels.isExpanded(2))

        let byHand = self.model()
        byHand.apply(Self.marking([1], in: try Fixtures.hierarchy()))
        byHand.setExpanded(1, true)
        XCTAssertTrue(byHand.isExpanded(1))
    }

    @MainActor
    func test_C_HIER_17_aNewMarkedNodeOnReloadStartsCollapsedAndKnownOnesStay() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.setExpanded(4, true)
        model.setExpanded(10, true)

        // A view controller on show is pushed on top, marked by the app, with a view inside.
        var hierarchy = try Fixtures.hierarchy()
        var pushed = LayerTreeTests.node(30, parent: 1)
        pushed.viewControllerClassName = "ChartViewController"
        pushed.isCollapsedByDefault = true
        hierarchy.nodes += [pushed, LayerTreeTests.node(31, parent: 30), LayerTreeTests.node(32, parent: 31)]
        model.apply(hierarchy)

        XCTAssertFalse(model.isExpanded(30), "new and marked")
        XCTAssertFalse(model.isExpanded(31), "new, below a marked node")
        XCTAssertTrue(model.isExpanded(10), "known: kept as the person left it")
        XCTAssertTrue(model.isExpanded(4), "known: kept as the person left it")
    }

    @MainActor
    func test_C_HIER_17_anArchivesStateWins() async throws {
        var state = ArchiveState()
        state.expanded = [1, 2, 4, 10]
        let data = try Fixtures.archive(state: state.encoded())
        let source = ArchiveSource(decoder: try ArchiveDecoder(data))
        let model = InspectionStore(source: source, maxTextureDimension: 4096)
        model.restore(state)
        model.enter()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        XCTAssertTrue(model.isExpanded(10), "the archive says it was open")
    }
}
