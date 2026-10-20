import AppKit
import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// Values that refer to layers (C-ATTR-28, P-ATTR-18): a chip for each object, as a
/// constraint's other end has (C-LAYOUT-06). One whose layer is in the hierarchy can be pointed
/// at and clicked; the rest are grey. The fixtures refer to a view controller and to two
/// gesture recognizers; a stack view's arranged subviews are made.
@MainActor
final class ReferenceChipTests: XCTestCase {
    private static func tree() throws -> LayerTree {
        try LayerTree(Fixtures.hierarchy())
    }

    private static func layerSix() throws -> [Attribute] {
        try Fixtures.attributes(of: 6, scenario: "layer-details").flatMap(\.attributes)
    }

    private static func references(_ value: AttributeValue?) -> [ObjectReference] {
        if case .references(let references) = value { return references }
        return []
    }

    private static func view(
        _ references: [ObjectReference], tree: LayerTree,
        onShowLayer: @escaping (UInt64) -> Void = { _ in }, onHoverLayer: @escaping (UInt64?) -> Void = { _ in }
    ) -> ReferenceChipsView {
        let view = ReferenceChipsView(
            chips: { AttributesViewModel.chips(of: $0, in: tree) }, onShowLayer: onShowLayer,
            onHoverLayer: onHoverLayer)
        view.show(.references(references))
        return view
    }

    private static func view(_ id: UInt64, _ name: String) -> ObjectReference {
        ObjectReference(layerID: id, className: name, displayClassName: name)
    }

    // MARK: - The fixtures

    func test_C_ATTR_28_theFixturesDelegateIsAChipForItsController() throws {
        let tree = try Self.tree()
        let delegate = try XCTUnwrap(Self.layerSix().first { $0.id == "scrollView.delegate" })
        let chips = AttributesViewModel.chips(of: Self.references(delegate.value), in: tree)
        XCTAssertEqual(chips.map(\.name), ["HomeViewController"])
        XCTAssertEqual(chips.first?.layerID, 2, "the layer of the controller's root view")
        guard case .layer(let icon)? = chips.first?.icon else {
            XCTFail("the hierarchy's icon")
            return
        }
        XCTAssertEqual(icon, LayerIcon(tree.node(2)))
        XCTAssertEqual(icon.category, .controller)
        XCTAssertEqual(chips.first?.toolTip, "Demo.HomeViewController · Layer 2")
        XCTAssertEqual(Self.view(Self.references(delegate.value), tree: tree).linkedLayerIDs, [2])
    }

    func test_C_ATTR_28_gestureRecognizersAreGreyAndCannotBeChosen() throws {
        let tree = try Self.tree()
        let gestures = try XCTUnwrap(Self.layerSix().first { $0.id == "view.gestureRecognizers" })
        let view = Self.view(Self.references(gestures.value), tree: tree)
        XCTAssertEqual(view.shownChips.map(\.name), [
            "UIScrollViewDelayedTouchesBeganGestureRecognizer", "UIScrollViewPanGestureRecognizer",
        ])
        XCTAssertTrue(view.shownChips.allSatisfy { $0.icon == .none && !$0.canHover && !$0.canSelect })
        XCTAssertEqual(view.linkedLayerIDs, [])
        view.hoverChip(at: 0)
        XCTAssertNil(view.hoveredIndex, "nothing to point at")
    }

    // MARK: - Chips

    func test_C_ATTR_28_arrangedSubviewsAreChipsInOrder() throws {
        let tree = try Self.tree()
        let view = Self.view(
            [Self.view(6, "UIScrollView"), Self.view(3, "UILabel"), Self.view(4, "CardView")], tree: tree)
        XCTAssertEqual(view.shownChips.map(\.name), ["UIScrollView", "UILabel", "CardView"])
        XCTAssertEqual(view.linkedLayerIDs, [6, 3, 4])
        XCTAssertEqual(view.shownChips.map(\.icon), [6, 3, 4].map { LayerChip.Icon.layer(LayerIcon(tree.node($0))) })
    }

    func test_C_ATTR_28_aLayerThatIsNotInTheHierarchyCannotBeChosen() throws {
        let tree = try Self.tree()
        var shown: [UInt64] = []
        let view = Self.view(
            [Self.view(99, "GoneView"),
             ObjectReference(layerID: nil, className: "Demo.Model", displayClassName: "Model")],
            tree: tree, onShowLayer: { shown.append($0) })
        XCTAssertEqual(view.linkedLayerIDs, [])
        XCTAssertEqual(view.shownChips.map(\.toolTip), ["GoneView", "Demo.Model"])
        view.clickChip(at: 0)
        XCTAssertEqual(shown, [])
    }

    func test_C_ATTR_28_pointingAtAChipHoversItsLayer() throws {
        var hovered: [UInt64?] = []
        let view = Self.view(
            [Self.view(3, "UILabel"), Self.view(4, "CardView")], tree: try Self.tree(),
            onHoverLayer: { hovered.append($0) })
        view.hoverChip(at: 1)
        view.hoverChip(at: nil)
        XCTAssertEqual(hovered, [4, nil])
    }

    func test_C_ATTR_28_moreThanSixShowSixAndAMoreButton() throws {
        let tree = try Self.tree()
        let eight = [6, 3, 4, 7, 9, 8, 5, 2].map { Self.view(UInt64($0), "View\($0)") }
        let view = Self.view(eight, tree: tree)
        XCTAssertEqual(view.shownChips.count, 6)
        XCTAssertEqual(view.moreText, "2 More")
        view.showAll()
        XCTAssertEqual(view.shownChips.count, 8)
        XCTAssertNil(view.moreText)
        // New values for the same layer keep it open; another layer's row starts with six.
        view.show(.references(eight))
        XCTAssertEqual(view.shownChips.count, 8)
        XCTAssertEqual(Self.view(eight, tree: tree).shownChips.count, 6)
        XCTAssertEqual(Self.view(Array(eight.prefix(6)), tree: tree).moreText, nil)
    }

    func test_C_ATTR_28_noReferencesReadsAsNone() throws {
        let view = Self.view([], tree: try Self.tree())
        XCTAssertEqual(view.shownChips, [])
        XCTAssertEqual(view.string, "None")
    }

    func test_C_WIRE_12_copyingReferencesGivesTheirNames() throws {
        let gestures = try XCTUnwrap(Self.layerSix().first { $0.id == "view.gestureRecognizers" })
        XCTAssertEqual(
            AttributeText.text(of: gestures.value),
            "UIScrollViewDelayedTouchesBeganGestureRecognizer, UIScrollViewPanGestureRecognizer")
        XCTAssertEqual(AttributeText.text(of: .references([])), "None")
    }

    // MARK: - In the panel

    func test_C_ATTR_28_clickingAChipSelectsItsLayer() async throws {
        var responder = try MockResponder.demo()
        var detail = try XCTUnwrap(responder.details[3])
        detail.attributeGroups = try Protocol12Extras.layerThree(adding: [
            Protocol12Extras.arrangedSubviews([Self.view(7, "UILabel"), Self.view(99, "GoneView")]),
        ])
        responder.details[3] = detail
        let server = try await MockServer.start(
            script: MockScript(steps: try MockScript.fixtures("handshake").steps + [.respond(responder)]))
        let channel = try await ConnectionChannel.connect(host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let listed = await Wait.until { await model.tree.count == 9 }
        XCTAssertTrue(listed)
        let layer = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: layer, tree: model.$tree.eraseToAnyPublisher(),
            connection: model.$connection.eraseToAnyPublisher(),
            onShowLayer: { [weak model] in model?.showLayer($0) }, onHoverLayer: { [weak model] in model?.hover($0) },
            loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.layoutIfNeeded()
        model.select(3)
        let loaded = await Wait.until { @MainActor in
            AppListViewTests.descendants(of: controller.view, identifier: ReferenceChipsView.identifier).count == 1
        }
        XCTAssertTrue(loaded, "the row of references")
        let chips = try XCTUnwrap(AppListViewTests.descendants(
            of: controller.view, identifier: ReferenceChipsView.identifier).first as? ReferenceChipsView)
        XCTAssertEqual(chips.linkedLayerIDs, [7])
        model.setExpanded(6, false)
        XCTAssertFalse(model.expandedLayerIDs.contains(6))

        chips.hoverChip(at: 0)
        XCTAssertEqual(model.hoveredLayerID, 7)
        chips.hoverChip(at: nil)
        XCTAssertNil(model.hoveredLayerID)

        chips.clickChip(at: 0)
        XCTAssertEqual(model.selectedLayerID, 7)
        XCTAssertTrue(model.expandedLayerIDs.contains(6), "its parent opened")

        window.close()
        await session.close()
        await server.stop()
    }
}
