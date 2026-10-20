import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

/// The layer tree built from a `Hierarchy`: C-HIER-01 and C-HIER-03; searching it, its
/// subtrees and depths (C-HIER-04 to 06).
final class LayerTreeTests: XCTestCase {
    /// A node with nothing special about it. Opacity is 1: on the wire an absent opacity
    /// reads as 0, which is a transparent layer.
    static func node(
        _ id: UInt64, parent: UInt64 = 0, hidden: Bool = false, opacity: Float = 1,
        className: String? = "CALayer", displayClassName: String? = "CALayer",
        viewClassName: String? = nil, viewDisplayClassName: String? = nil
    ) -> LayerNode {
        LayerNode(
            id: id, parentID: parent, className: className, displayClassName: displayClassName,
            viewClassName: viewClassName, viewDisplayClassName: viewDisplayClassName,
            bounds: nil, position: nil, anchorPoint: nil, transform: nil, zPosition: 0,
            isHidden: hidden, opacity: opacity, masksToBounds: false)
    }

    private func tree(_ nodes: [LayerNode]) throws -> LayerTree {
        try LayerTree(Hierarchy(nodes: nodes, keyWindowID: 0))
    }

    /// Why these nodes are refused, or nil when they are a tree.
    private func refusal(_ nodes: [LayerNode]) -> LayerTreeError? {
        do {
            _ = try LayerTree(Hierarchy(nodes: nodes, keyWindowID: 0))
            return nil
        } catch {
            return error
        }
    }

    // MARK: - C-HIER-01: the tree

    func test_C_HIER_01_theFixtureBecomesATreeOfFourteenNodes() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())

        XCTAssertEqual(tree.count, 14)
        XCTAssertEqual(tree.ids, [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        XCTAssertEqual(tree.roots, [1])
        XCTAssertEqual(tree.keyWindowID, 1)

        XCTAssertEqual(tree.children(of: 1), [2])
        XCTAssertEqual(tree.children(of: 2), [3, 4, 6, 8, 9, 13])
        // The virtual nodes come before the layer's sublayers (P-HIER-21).
        XCTAssertEqual(tree.children(of: 4), [10, 12, 5])
        XCTAssertEqual(tree.children(of: 10), [11])
        XCTAssertEqual(tree.children(of: 6), [7])
        XCTAssertEqual(tree.children(of: 13), [14])
        for leaf: UInt64 in [3, 5, 7, 8, 9, 11, 12, 14] {
            XCTAssertEqual(tree.children(of: leaf), [], "layer \(leaf)")
        }

        XCTAssertNil(tree.parent(of: 1))
        XCTAssertEqual(tree.parent(of: 2), 1)
        XCTAssertEqual(tree.parent(of: 5), 4)
        XCTAssertEqual(tree.parent(of: 7), 6)
        XCTAssertEqual(tree.parent(of: 9), 2)

        XCTAssertTrue(tree.contains(14))
        XCTAssertFalse(tree.contains(15))
        XCTAssertEqual(tree.node(4)?.viewClassName, "Demo.CardView")
    }

    func test_C_HIER_01_aTitleFallsBackWhenNamesAreMissing() throws {
        let node = Self.node
        let tree = try tree([
            node(1, 0, false, 1, "L", "LD", "Mod.V", "V"),
            node(2, 1, false, 1, "L", "LD", "Mod.V", nil),
            node(3, 1, false, 1, "L", "LD", nil, nil),
            node(4, 1, false, 1, "L", nil, nil, nil),
            node(5, 1, false, 1, nil, nil, nil, nil),
            // Empty strings count as missing.
            node(6, 1, false, 1, "L", "", "", ""),
        ])
        XCTAssertEqual(
            tree.ids.map(tree.title(of:)), ["V", "Mod.V", "LD", "L", nil, "L"])
    }

    func test_C_HIER_01_everyWindowIsARoot() throws {
        let node = Self.node
        let tree = try tree([
            node(1, 0, false, 1, "A", "A", nil, nil), node(2, 1, false, 1, "B", "B", nil, nil),
            node(3, 0, false, 1, "C", "C", nil, nil), node(4, 3, false, 1, "D", "D", nil, nil),
        ])
        XCTAssertEqual(tree.roots, [1, 3])
        XCTAssertEqual(tree.children(of: 1), [2])
        XCTAssertEqual(tree.children(of: 3), [4])
    }

    func test_C_HIER_01_anEmptyHierarchyIsTheEmptyTree() throws {
        let tree = try tree([])
        XCTAssertEqual(tree, .empty)
        XCTAssertEqual(tree.count, 0)
        XCTAssertEqual(tree.roots, [])
    }

    func test_C_HIER_01_aLayerThatIsNotInTheTreeHasNothing() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertNil(tree.node(99))
        XCTAssertNil(tree.parent(of: 99))
        XCTAssertEqual(tree.children(of: 99), [])
        XCTAssertNil(tree.title(of: 99))
        XCTAssertFalse(tree.isDimmed(99))
    }

    func test_C_HIER_01_aVeryDeepTreeIsBuilt() throws {
        // A chain of 20,000 layers, each inside the one before.
        let nodes = (1...20_000).map { Self.node(UInt64($0), parent: UInt64($0 - 1)) }
        let tree = try tree(nodes)
        XCTAssertEqual(tree.count, 20_000)
        XCTAssertEqual(tree.roots, [1])
        XCTAssertEqual(tree.parent(of: 20_000), 19_999)
        XCTAssertEqual(tree.children(of: 19_999), [20_000])
    }

    // MARK: - C-HIER-01: hierarchies that break P-HIER-01 or P-HIER-03

    func test_C_HIER_01_manySiblingsAreBuiltInLinearTime() throws {
        // Seconds to build a root with `count` children.
        func seconds(_ count: Int) throws -> Double {
            let nodes = [Self.node(1)] + (2...UInt64(count + 1)).map { Self.node($0, parent: 1) }
            let start = ContinuousClock.now
            let built = try tree(nodes)
            let elapsed = ContinuousClock.now - start
            XCTAssertEqual(built.children(of: 1).count, count)
            return Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
        }
        // The quickest of three runs each, so that one pause of the machine does not count.
        let small = try (0..<3).map { _ in try seconds(50_000) }.min()!
        let large = try (0..<3).map { _ in try seconds(200_000) }.min()!
        // Four times the siblings: about four times the time when linear, sixteen when each
        // append copies the parent's children.
        XCTAssertLessThan(large / small, 8, "50,000: \(small) s; 200,000: \(large) s")
    }

    func test_C_HIER_01_aLayerWithTheIDZeroIsRefused() {
        XCTAssertEqual(refusal([Self.node(1), Self.node(0, parent: 1)]), .zeroID(index: 1))
    }

    func test_C_HIER_01_aRepeatedIDIsRefused() {
        XCTAssertEqual(
            refusal([Self.node(1), Self.node(2, parent: 1), Self.node(2, parent: 1)]),
            .duplicateID(2))
    }

    func test_C_HIER_01_aLayerThatDoesNotFollowItsParentIsRefused() {
        // The parent comes later.
        XCTAssertEqual(
            refusal([Self.node(1), Self.node(3, parent: 2), Self.node(2, parent: 1)]),
            .parentNotBefore(id: 3, parentID: 2))
        // The parent does not exist.
        XCTAssertEqual(
            refusal([Self.node(1), Self.node(2, parent: 99)]),
            .parentNotBefore(id: 2, parentID: 99))
        // The layer is its own parent.
        XCTAssertEqual(
            refusal([Self.node(1), Self.node(2, parent: 2)]),
            .parentNotBefore(id: 2, parentID: 2))
    }

    // MARK: - C-HIER-03: layers that cannot be seen

    func test_C_HIER_03_onlyTheHiddenLayerOfTheFixtureIsDimmed() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertEqual(tree.ids.filter(tree.isDimmed), [5])
    }

    func test_C_HIER_03_layersInsideAHiddenLayerAreDimmed() throws {
        let tree = try tree([
            Self.node(1),
            Self.node(2, parent: 1, hidden: true),
            Self.node(3, parent: 2),
            Self.node(4, parent: 3),
            Self.node(5, parent: 1),
        ])
        XCTAssertEqual(tree.ids.filter(tree.isDimmed), [2, 3, 4])
    }

    func test_C_HIER_03_transparentLayersAndWhatIsInsideThemAreDimmed() throws {
        let tree = try tree([
            Self.node(1),
            Self.node(2, parent: 1, opacity: 0),
            Self.node(3, parent: 2),
            // Half transparent is still visible.
            Self.node(4, parent: 1, opacity: 0.5),
            Self.node(5, parent: 4),
        ])
        XCTAssertEqual(tree.ids.filter(tree.isDimmed), [2, 3])
    }

    // MARK: - C-HIER-04 to 06: searching, focusing, levels

    func test_C_HIER_04_aSearchMatchesAnyNameIgnoringCase() throws {
        let tree = try self.tree([
            Self.node(
                1, className: "_UILabelLayer", displayClassName: "UILabelLayer",
                viewClassName: "Demo.PriceLabel", viewDisplayClassName: "PriceLabel"),
        ])
        for text in ["price", "PRICE", "Demo.", "_uilabel", "LabelLayer", "l"] {
            XCTAssertTrue(tree.matches(1, text), text)
        }
        XCTAssertFalse(tree.matches(1, "button"))
        XCTAssertFalse(tree.matches(1, " price"), "the text is taken as it is")
        XCTAssertFalse(tree.matches(2, "price"), "a layer that is not in the tree")
    }

    /// The interface names a layer without names (C-LOC-01: the model has no text of its
    /// own), and the search finds it by that name.
    func test_C_HIER_04_aLayerWithoutNamesMatchesItsTitle() throws {
        let tree = try self.tree([
            Self.node(1, className: nil, displayClassName: nil),
            Self.node(2, className: "CALayer", displayClassName: nil),
        ])
        XCTAssertTrue(tree.matches(1, "layer", untitled: "Layer"), "the interface's name")
        XCTAssertTrue(tree.matches(1, "图层", untitled: "图层"))
        XCTAssertFalse(tree.matches(1, "layer"), "no name given")
        XCTAssertFalse(tree.matches(2, "图层", untitled: "图层"), "a layer with a name")
    }

    func test_C_HIER_04_theFixturesLabels() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertEqual(tree.ids.filter { tree.matches($0, "label") }, [3, 7, 14])
        // 5 too: since protocol 0.2, CardView.badgeLayer holds it (C-HIER-07); and 13, a
        // PaymentCardView.
        XCTAssertEqual(tree.ids.filter { tree.matches($0, "cardview") }, [4, 5, 13])
    }

    func test_C_HIER_06_theWholeTreeWithDepths() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertEqual(
            tree.layers(within: nil).map(\.id), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        XCTAssertEqual(
            tree.layers(within: nil).map(\.depth), [0, 1, 2, 2, 3, 4, 3, 3, 2, 3, 2, 2, 2, 3])
    }

    func test_C_HIER_05_aSubtreeWithDepthsFromItsRoot() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertEqual(
            tree.layers(within: 4),
            [LayerDepth(id: 4, depth: 0), LayerDepth(id: 10, depth: 1), LayerDepth(id: 11, depth: 2),
             LayerDepth(id: 12, depth: 1), LayerDepth(id: 5, depth: 1)])
        XCTAssertEqual(tree.layers(within: 2).map(\.id), [2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        XCTAssertEqual(tree.layers(within: 9), [LayerDepth(id: 9, depth: 0)])
        XCTAssertEqual(tree.layers(within: 42), [])
    }

    func test_C_HIER_05_twoWindowsAndAFocusOnOne() throws {
        let tree = try self.tree([
            Self.node(1), Self.node(2, parent: 1), Self.node(3), Self.node(4, parent: 3),
        ])
        XCTAssertEqual(tree.layers(within: nil).map(\.depth), [0, 1, 0, 1])
        XCTAssertEqual(tree.layers(within: 3).map(\.id), [3, 4])
    }

    func test_C_HIER_05_thePathFromTheWindowDown() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertEqual(tree.path(to: 5), [1, 2, 4, 5])
        XCTAssertEqual(tree.path(to: 1), [1])
        XCTAssertEqual(tree.path(to: 42), [])
    }

    func test_C_HIER_05_whatIsWithinASubtree() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertTrue(tree.isWithin(5, root: 4))
        XCTAssertTrue(tree.isWithin(4, root: 4))
        XCTAssertTrue(tree.isWithin(7, root: 1))
        XCTAssertFalse(tree.isWithin(3, root: 4))
        XCTAssertFalse(tree.isWithin(2, root: 4), "an ancestor is not within")
        XCTAssertFalse(tree.isWithin(42, root: 1))
    }

    // MARK: - C-HIER-07: view controllers and members

    func test_C_HIER_07_theFixturesMembersNearestFirst() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        XCTAssertEqual(tree.memberTitles(of: 3), ["HomeViewController.titleLabel"])
        XCTAssertEqual(
            tree.memberTitles(of: 5), ["CardView.badgeLayer", "HomeViewController.cardBadge"])
        XCTAssertEqual(tree.memberTitles(of: 8), ["DMBaseViewController._dividerLayer"])
        XCTAssertEqual(tree.ids.filter { !tree.memberTitles(of: $0).isEmpty }, [3, 4, 5, 6, 8, 13])
    }

    func test_C_HIER_07_namesFallBackAndEmptyOnesAreSkipped() throws {
        var node = Self.node(1)
        node.viewControllerClassName = "Demo.RootViewController"
        node.memberReferences = [
            MemberReference(ownerClassName: "Demo.Owner", ownerDisplayClassName: nil, name: "a"),
            MemberReference(ownerClassName: nil, ownerDisplayClassName: nil, name: "b"),
            MemberReference(
                ownerClassName: "Demo.Owner", ownerDisplayClassName: "Owner", name: nil),
            MemberReference(ownerClassName: "", ownerDisplayClassName: "", name: ""),
        ]
        let tree = try self.tree([node])
        XCTAssertEqual(tree.viewControllerTitle(of: 1), "Demo.RootViewController")
        XCTAssertEqual(tree.memberTitles(of: 1), ["Demo.Owner.a", "b"])
        XCTAssertNil(tree.viewControllerTitle(of: 42))
        XCTAssertEqual(tree.memberTitles(of: 42), [])
    }

    func test_C_HIER_07_aSearchMatchesControllersAndMembers() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        func matching(_ text: String) -> [UInt64] { tree.ids.filter { tree.matches($0, text) } }
        XCTAssertEqual(matching("titleLabel"), [3])
        XCTAssertEqual(matching("HomeViewController"), [2, 3, 4, 5, 6, 13])
        // A member is matched as the list and the header show it, "Owner.name": not by the
        // runtime name of its owner. The layer's own names, raw ones too, still count.
        XCTAssertEqual(matching("Demo.CardView"), [4], "4's own view class, not 5's member")
        XCTAssertEqual(matching("Demo.HomeViewController"), [2], "2's own view controller")
        XCTAssertEqual(matching("DMBase"), [8])
        // 11 by its class, CardBadge.
        XCTAssertEqual(matching("cardBadge"), [11, 5], "the second reference counts too")
        XCTAssertEqual(matching("HomeViewController.cardView"), [4])
    }

    // MARK: - C-ATTR-11: addresses are only shown

    func test_C_ATTR_11_addressesAreNotIdentity() throws {
        func withAddresses(_ node: LayerNode) -> LayerNode {
            var node = node
            node.layerAddress = 0x6000_03B4_C000
            node.viewAddress = 0x1_0380_6800
            return node
        }
        let tree = try self.tree([
            Self.node(1), withAddresses(Self.node(2, parent: 1)), withAddresses(Self.node(3, parent: 1)),
        ])
        XCTAssertEqual(tree.count, 3, "two layers with the same addresses are two layers")
        XCTAssertEqual(tree.node(2)?.id, 2)
        XCTAssertEqual(tree.node(3)?.id, 3)

        // A subtree whose root has another layer's addresses replaces the layer of its ID.
        var answer = withAddresses(Self.node(3, parent: 1, className: "CAShapeLayer"))
        answer.layerAddress = 0x6000_03B4_C040
        let replaced = try tree.replacingSubtree(with: Hierarchy(nodes: [answer], keyWindowID: 0))
        XCTAssertEqual(replaced.node(3)?.className, "CAShapeLayer")
        XCTAssertEqual(replaced.node(3)?.layerAddress, 0x6000_03B4_C040)
        XCTAssertEqual(replaced.node(2), tree.node(2))
    }
}
