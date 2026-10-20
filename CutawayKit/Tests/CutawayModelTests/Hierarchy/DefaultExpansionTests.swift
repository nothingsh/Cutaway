import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-HIER-09: which layers start expanded. The tree opens down to the view controllers on
/// show and no further; everything else starts collapsed.
final class DefaultExpansionTests: XCTestCase {
    private static func node(
        _ id: UInt64, parent: UInt64 = 0, hidden: Bool = false, controller: String? = nil
    ) -> LayerNode {
        var node = LayerTreeTests.node(id, parent: parent, hidden: hidden)
        node.viewControllerClassName = controller
        node.viewControllerDisplayClassName = controller
        return node
    }

    private static func fixture(_ change: (inout [LayerNode]) -> Void = { _ in }) throws -> Hierarchy {
        var hierarchy = try Fixtures.hierarchy()
        change(&hierarchy.nodes)
        return hierarchy
    }

    private static func index(_ id: UInt64, in nodes: [LayerNode]) -> Int {
        nodes.firstIndex { $0.id == id }!
    }

    // MARK: - The rule

    func test_C_HIER_09_theFixtureOpensDownToItsViewController() throws {
        // Layer 2 is HomeViewController's root view; 4 and 6 are views inside it.
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertEqual(tree.defaultExpansion(), [1, 2])
    }

    func test_C_HIER_09_withoutAViewControllerEveryLayerThatCanBeSeenOpens() throws {
        let hierarchy = try Self.fixture { nodes in
            let two = Self.index(2, in: nodes)
            nodes[two].viewControllerClassName = nil
            nodes[two].viewControllerDisplayClassName = nil
        }
        // Layer 4 opens although the one layer inside it is hidden: 4 itself can be seen. Its
        // virtual node 10 does not: the app asks for it to start collapsed (C-HIER-17).
        XCTAssertEqual(try LayerTree(hierarchy).defaultExpansion(), [1, 2, 4, 6, 13])
    }

    func test_C_HIER_09_aHiddenViewControllerIsNotOnShow() throws {
        let hierarchy = try Self.fixture { nodes in
            nodes[Self.index(2, in: nodes)].isHidden = true
        }
        // No view controller on show: what can be seen opens, and everything in 2 is dimmed.
        XCTAssertEqual(try LayerTree(hierarchy).defaultExpansion(), [1])
    }

    func test_C_HIER_09_aViewControllerTheServerSaysIsNotShownIsNotOnShow() throws {
        let hierarchy = try Self.fixture { nodes in
            nodes[Self.index(2, in: nodes)].viewControllerVisibility = .notShown
        }
        // The same as without a view controller (P-HIER-18).
        XCTAssertEqual(try LayerTree(hierarchy).defaultExpansion(), [1, 2, 4, 6, 13])
    }

    func test_C_HIER_09_withoutVisibilityTheRootViewsPlaceStands() throws {
        let hierarchy = Fixtures.withoutTheOptionalFields(try Fixtures.hierarchy())
        XCTAssertEqual(try LayerTree(hierarchy).defaultExpansion(), [1, 2])
        // Shown does not overrule the rest of the rule: a hidden root view is still not on show.
        let hidden = try Self.fixture { nodes in
            let two = Self.index(2, in: nodes)
            nodes[two].viewControllerVisibility = .shown
            nodes[two].isHidden = true
        }
        XCTAssertEqual(try LayerTree(hidden).defaultExpansion(), [1])
    }

    func test_C_HIER_09_anotherWindowStartsCollapsed() throws {
        let other = [
            Self.node(20), Self.node(21, parent: 20, controller: "Keyboard"),
            Self.node(22, parent: 21), Self.node(23, parent: 22),
        ]
        let keyed = try Self.fixture { $0 += other }
        XCTAssertEqual(keyed.keyWindowID, 1)
        XCTAssertEqual(try LayerTree(keyed).defaultExpansion(), [1, 2])

        // Without a key window every window opens down to its view controllers.
        var unkeyed = keyed
        unkeyed.keyWindowID = 0
        XCTAssertEqual(try LayerTree(unkeyed).defaultExpansion(), [1, 2, 20, 21])
        // A key window that is not in the tree counts as none.
        unkeyed.keyWindowID = 99
        XCTAssertEqual(try LayerTree(unkeyed).defaultExpansion(), [1, 2, 20, 21])
    }

    func test_C_HIER_09_nestedViewControllersOpenDownToTheInnermostOnes() throws {
        // A tab bar controller holds a navigation controller, which shows two child view
        // controllers side by side; another tab's view is there but hidden.
        let hierarchy = Hierarchy(
            nodes: [
                Self.node(1),
                Self.node(2, parent: 1, controller: "TabBarController"),
                Self.node(3, parent: 2),
                Self.node(4, parent: 3, controller: "NavigationController"),
                Self.node(5, parent: 4),
                Self.node(6, parent: 5, controller: "ListController"),
                Self.node(7, parent: 6),
                Self.node(8, parent: 7),
                Self.node(9, parent: 5, controller: "DetailController"),
                Self.node(10, parent: 9),
                Self.node(11, parent: 10),
                Self.node(12, parent: 3, hidden: true, controller: "OtherTabController"),
                Self.node(13, parent: 12),
                Self.node(14, parent: 13),
                Self.node(15, parent: 2),
                Self.node(16, parent: 15),
            ],
            keyWindowID: 1)
        // The way down, the outer controllers and the innermost ones; not what is inside the
        // innermost ones, the hidden tab, or a view beside the way down.
        XCTAssertEqual(try LayerTree(hierarchy).defaultExpansion(), [1, 2, 3, 4, 5, 6, 9])
    }

    func test_C_HIER_09_tenThousandLayersAreSortedOutQuickly() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        // App-shaped, as C-SCALE-01: one pass over the tree, well under the 2 seconds the
        // list has to show the tree.
        let tree = try LayerTree(ScaleScene.synthetic.hierarchy())
        let start = ContinuousClock.now
        _ = tree.defaultExpansion()
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(200))
    }

    // MARK: - Where the rule is used

    @MainActor
    private func model() -> InspectionStore {
        InspectionStore(session: Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")))
    }

    @MainActor
    func test_C_HIER_09_anInspectionStartsWithTheDefault() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(model.tree.ids.filter(model.isExpanded), [1, 2, 3, 11, 12, 5, 7, 8, 9, 14])
        // Layers without sublayers count as expanded, as before: the preview draws them
        // with their own image.
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertFalse(model.isExpanded(6))
        // Layers 5 and 7 are inside collapsed layers: they are not drawn.
        XCTAssertEqual(
            Set(model.layout.drawnTextures.map(\.layerID)).intersection([5, 7]), [])
    }

    @MainActor
    func test_C_HIER_09_aReloadKeepsKnownLayersAndOpensNewOnesByTheRule() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.setExpanded(4, true)
        model.setExpanded(1, false)

        // A view controller pushed on top of the window, with a view and a sublayer inside.
        var hierarchy = try Fixtures.hierarchy()
        hierarchy.nodes += [
            Self.node(20, parent: 1, controller: "DetailViewController"),
            Self.node(21, parent: 20),
            Self.node(22, parent: 21),
        ]
        model.apply(hierarchy)

        XCTAssertTrue(model.isExpanded(4), "kept as the user left it")
        XCTAssertFalse(model.isExpanded(1), "kept as the user left it")
        XCTAssertFalse(model.isExpanded(6), "kept as it started")
        XCTAssertTrue(model.isExpanded(20), "a new view controller on show")
        XCTAssertFalse(model.isExpanded(21), "a new view inside it")
        XCTAssertTrue(model.isExpanded(22), "a new leaf")
    }

    @MainActor
    func test_C_HIER_09_anArchiveWithoutStateOpensByTheRule() async throws {
        let data = try Fixtures.archive(state: Data())
        let source = ArchiveSource(decoder: try ArchiveDecoder(data))
        let model = InspectionStore(source: source, maxTextureDimension: 4096)
        model.enter()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        XCTAssertTrue(model.isExpanded(2))
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertFalse(model.isExpanded(6))
    }

    @MainActor
    func test_C_HIER_09_aSubtreeTakenAgainOpensItsNewLayersByTheRule() async throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        let four = try XCTUnwrap(tree.node(4))
        let five = try XCTUnwrap(tree.node(5))
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        // Layer 4 with a new view inside, which has a sublayer of its own.
        steps += [
            .expect(.getSubtree, as: 1),
            .send(Frame(requestID: 1, body: .hierarchy(Hierarchy(
                nodes: [four, five, Self.node(20, parent: 4), Self.node(21, parent: 20)],
                keyWindowID: 1)))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: ClientInfo(name: "Cutaway", version: "0.4.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session)
        // No screenshots are asked for while the rows wait: the script has none.
        model.rowsWait = .seconds(30)
        model.enter()
        let loaded = await Wait.until {
            await MainActor.run { model.loadState == .loaded && model.canRefreshSubtrees }
        }
        XCTAssertTrue(loaded)
        model.setExpanded(4, true)

        model.refreshSubtree(of: 4)
        let replaced = await Wait.until { await model.tree.contains(20) }
        XCTAssertTrue(replaced)
        XCTAssertTrue(model.isExpanded(4), "kept")
        XCTAssertFalse(model.isExpanded(20), "a new view inside a view controller")
        XCTAssertTrue(model.isExpanded(21), "a new leaf")

        await session.close()
        await server.stop()
    }
}
