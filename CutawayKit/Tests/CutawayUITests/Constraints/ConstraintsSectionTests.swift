import AppKit
import Combine
import CutawayModel
import CutawayRender
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The constraints of the attribute panel's Layout section (C-LAYOUT-02) and their links (C-LAYOUT-03),
/// by the `layout-constraints` fixture on the layers of `hierarchy`. Checked by its views and
/// texts, not by eye.
final class ConstraintsSectionTests: XCTestCase {
    /// An entered inspection whose screenshots are all in, on a server that answers the
    /// requests for attributes with `answers`' layers, in order (`Fixtures.panelDetail`).
    @MainActor
    static func inspection(
        answering answers: [UInt64]
    ) async throws -> (InspectionStore, Session, MockServer) {
        try await inspection(serving: try answers.map { try Fixtures.panelDetail(of: $0) })
    }

    /// The same, answering the requests for attributes with `details`, in order.
    @MainActor
    static func inspection(
        serving details: [LayerDetail]
    ) async throws -> (InspectionStore, Session, MockServer) {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        for (index, detail) in details.enumerated() {
            steps += MockScript.layerDetailsSteps([detail], as: 60 + UInt32(index))
        }
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: ClientInfo(name: "Cutaway", version: "0.4.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let settled = await Wait.until {
            await MainActor.run {
                // Editing comes once the capabilities are known.
                model.attributes.canEdit
                    && model.detailProgress == DetailProgress(completed: 7, total: 7)
            }
        }
        XCTAssertTrue(settled)
        return (model, session, server)
    }

    /// The panel in a window that is never shown, 300 × 600 points. `shown` collects the layers
    /// its links ask for.
    @MainActor
    private func panel(
        for model: InspectionStore, shown: @escaping (UInt64) -> Void = { _ in }
    ) -> (AttributesViewController, NSWindow) {
        let layer = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: layer,
            tree: model.$tree.eraseToAnyPublisher(),
            connection: model.$connection.eraseToAnyPublisher(), onShowLayer: shown, loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 300, height: 600))
        window.layoutIfNeeded()
        return (controller, window)
    }

    /// Selects a layer and waits for its attributes.
    @MainActor
    private func select(_ id: UInt64, in model: InspectionStore) async {
        model.select(id)
        let loaded = await Wait.until {
            await MainActor.run {
                guard model.attributes.selectedID == id, case .loaded = model.attributes.state
                else { return false }
                return true
            }
        }
        XCTAssertTrue(loaded, "layer \(id): \(model.attributes.state)")
    }

    @MainActor
    private func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    @MainActor
    private static func descendants(of view: NSView, identifier: String) -> [NSView] {
        (view.accessibilityIdentifier() == identifier ? [view] : [])
            + view.subviews.flatMap { descendants(of: $0, identifier: identifier) }
    }

    /// The constraints end the Layout section, after its attributes (C-ATTR-10).
    @MainActor
    private func assertConstraintsEndLayout(
        _ controller: AttributesViewController, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let constraints = try XCTUnwrap(controller.constraintsView, file: file, line: line)
        let layout = try XCTUnwrap(controller.section(.layout), file: file, line: line)
        XCTAssertTrue(layout.constraintsPart === constraints, file: file, line: line)
        XCTAssertTrue(constraints.isDescendant(of: layout), file: file, line: line)
        layout.layoutSubtreeIfNeeded()
        let top = constraints.convert(constraints.bounds, to: layout)
        for row in layout.rows {
            let frame = row.convert(row.bounds, to: layout)
            let above = layout.isFlipped ? frame.maxY <= top.minY + 0.5 : frame.minY >= top.maxY - 0.5
            XCTAssertTrue(above, "\(row.title) is above the constraints", file: file, line: line)
        }
    }

    @MainActor
    private func message(_ controller: AttributesViewController) -> NSTextField? {
        AppListViewTests.descendant(
            of: controller.view, identifier: AttributesViewController.messageIdentifier)
            as? NSTextField
    }

    // MARK: - C-LAYOUT-02

    @MainActor
    func test_C_LAYOUT_02_theSectionIsBuiltAgainOnlyWhenWhatItSaysChanges() async throws {
        let (model, session, server) = try await Self.inspection(answering: [3])
        let (controller, window) = panel(for: model)
        await select(3, in: model)
        let section = try XCTUnwrap(controller.constraintsView)
        let rows = controller.attributeRows.map(\.row)

        // The same tree again: nothing is built again.
        model.apply(try Fixtures.hierarchy())
        XCTAssertTrue(controller.constraintsView === section)

        // Layer 2 under another name, its controller's: the section says it; the attribute rows
        // stay as they are, so that a field being typed in keeps its focus (C-ATTR-06).
        var renamed = try Fixtures.hierarchy()
        let two = try XCTUnwrap(renamed.nodes.firstIndex { $0.id == 2 })
        renamed.nodes[two].viewControllerDisplayClassName = "RootViewController"
        model.apply(renamed)
        let rebuilt = try XCTUnwrap(controller.constraintsView)
        XCTAssertFalse(rebuilt === section)
        XCTAssertEqual(
            rebuilt.rows[0].equationView.plainText, "self.centerX = RootViewController.centerX")
        XCTAssertEqual(controller.attributeRows.count, rows.count)
        XCTAssertTrue(zip(controller.attributeRows.map(\.row), rows).allSatisfy { $0 === $1 })

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_02_aNewAnswerWithTheSameConstraintsKeepsTheSection() async throws {
        // The second answer renames the attributes and keeps the constraints.
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 3)], as: 60)
        var renamed = try Fixtures.panelDetail(of: 3)
        renamed.attributeGroups = Fixtures.renamingAttributes(renamed.attributeGroups)
        steps += MockScript.layerDetailsSteps([renamed], as: 61)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.4.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let settled = await Wait.until {
            await MainActor.run {
                model.attributes.canEdit
                    && model.detailProgress == DetailProgress(completed: 7, total: 7)
            }
        }
        XCTAssertTrue(settled)
        let (controller, window) = panel(for: model)
        await select(3, in: model)
        let section = try XCTUnwrap(controller.constraintsView)
        let titles = controller.sectionViews.flatMap(\.rows).map(\.title)

        // A new round, as a refresh starts (C-DET-05).
        model.attributes.select(3, newRound: model.tree)
        let answered = await Wait.untilOnMain { controller.sectionViews.flatMap(\.rows).map(\.title) != titles }
        XCTAssertTrue(answered, "the renamed attributes")
        XCTAssertTrue(controller.constraintsView === section, "the same constraints")
        try assertConstraintsEndLayout(controller)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-10: the list ends with the section

    /// A peer of 1.0 sends no sections: every attribute is in Appearance, and the constraints
    /// still have a Layout section of their own.
    @MainActor
    func test_C_ATTR_10_withoutSectionsTheConstraintsStillEndTheList() async throws {
        var detail = try Fixtures.panelDetail(of: 3)
        detail.attributeGroups = Fixtures.withoutProtocol11(detail.attributeGroups)
        let (model, session, server) = try await Self.inspection(serving: [detail])
        let (controller, window) = panel(for: model)
        await select(3, in: model)
        window.layoutIfNeeded()

        XCTAssertEqual(controller.objectSection?.rows.isEmpty, true)
        XCTAssertEqual(controller.section(.layout)?.rows.isEmpty, true)
        XCTAssertEqual(
            controller.section(.appearance)?.rows.count,
            detail.attributeGroups.flatMap(\.attributes).count)
        let section = try XCTUnwrap(controller.constraintsView)
        XCTAssertTrue(isShown(section))
        try assertConstraintsEndLayout(controller)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-LAYOUT-05

    /// P-LAYOUT-08: the constraint is listed like any other, its other end can be chosen, and
    /// the panel reports no error.
    @MainActor
    func test_C_LAYOUT_05_aConstraintWithAnUnknownAttributeIsListedAndItsOtherEndCanBeChosen()
        async throws
    {
        var detail = try Fixtures.panelDetail(of: 3)
        detail.constraints[3].firstAttribute = .notAnAttribute
        detail.constraints[3].secondAttribute = .notAnAttribute
        let (model, session, server) = try await Self.inspection(serving: [detail])
        var shown: [UInt64] = []
        let (controller, window) = panel(for: model) { shown.append($0) }
        await select(3, in: model)
        window.layoutIfNeeded()

        let section = try XCTUnwrap(controller.constraintsView)
        XCTAssertTrue(isShown(section))
        XCTAssertEqual(section.rows.count, 4)
        XCTAssertTrue(section.rows.allSatisfy { isShown($0) })
        XCTAssertEqual(
            section.rows[3].equationView.plainText, "cardView.unknown = self.unknown + 78")
        XCTAssertNil(message(controller).flatMap { isShown($0) ? $0.stringValue : nil })
        XCTAssertEqual(section.rows[3].equationView.linkedLayerIDs, [4])
        section.rows[3].equationView.clickLink(to: 4)
        XCTAssertEqual(shown, [4])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-LAYOUT-06

    /// The chips of a row, in order.
    @MainActor
    private func ends(_ row: ConstraintRowView) -> [ConstraintRow.End] {
        row.equationView.chips.map(\.cell.end)
    }

    @MainActor
    func test_C_LAYOUT_06_pointingAtAChipHoversItsLayerAndStressesItsEnd() async throws {
        let (model, session, server) = try await Self.inspection(answering: [3, 4])
        // Every end marked, so that the others fade (C-PREV-18).
        model.setShowsAllConstraintEnds(true)
        let layer = model.selectedLayerSummary
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: layer,
            tree: model.$tree.eraseToAnyPublisher(),
            onShowLayer: { [weak model] in model?.showLayer($0) },
            onHoverConstraintEnd: { [weak model] end in
                model?.hoverConstraintEnd(end?.mark, layerID: end?.layerID)
            },
            loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        await select(3, in: model)
        let section = try XCTUnwrap(controller.constraintsView)

        // Layer 4's chip, in the last row.
        let equation = section.rows[3].equationView
        let chip = try XCTUnwrap(equation.chips.first)
        equation.hoverEnd(at: chip.index)
        XCTAssertTrue(chip.cell.isHovered)
        XCTAssertEqual(model.hoveredLayerID, 4)
        XCTAssertEqual(model.emphasizedConstraintEnds, [.layer(4)])
        // Off it: as before.
        equation.hoverEnd(at: nil)
        XCTAssertFalse(chip.cell.isHovered)
        XCTAssertNil(model.hoveredLayerID)
        XCTAssertEqual(model.emphasizedConstraintEnds, [])

        // The safe area: its owner hovered, its area stressed.
        let guideRow = section.rows[1].equationView
        guideRow.hoverEnd(at: try XCTUnwrap(guideRow.chips.first).index)
        XCTAssertEqual(model.hoveredLayerID, 2)
        XCTAssertEqual(model.emphasizedConstraintEnds, [model.constraintEnds[1].mark])

        // Another layer's constraints: nothing is stressed.
        await select(4, in: model)
        XCTAssertEqual(model.emphasizedConstraintEnds, [])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_07_pointingAtARowFillsItAndMarksOnlyItsEnds() async throws {
        let (model, session, server) = try await Self.inspection(answering: [3, 9])
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: model.selectedLayerSummary,
            tree: model.$tree.eraseToAnyPublisher(),
            onPointConstraints: { [weak model] pointer in
                switch pointer {
                case .entered(let indices, let stresses):
                    model?.pointConstraints(indices, stresses: stresses)
                case .left(let indices):
                    model?.leaveConstraints(indices)
                }
            },
            loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        await select(3, in: model)
        let section = try XCTUnwrap(controller.constraintsView)
        XCTAssertEqual(model.constraintEnds, [], "selecting marks nothing")

        // The second row: the safe area, stressed.
        let row = section.rows[1]
        XCTAssertEqual(row.text.index, 1)
        row.point(true)
        XCTAssertTrue(row.isHovered)
        XCTAssertEqual(model.constraintEnds.count, 1)
        XCTAssertEqual(model.emphasizedConstraintEnds, model.constraintEnds.map(\.mark))
        guard case .area(_, in: 2)? = model.constraintEnds.first?.mark else {
            XCTFail("\(model.constraintEnds)")
            return
        }
        row.point(false)
        XCTAssertFalse(row.isHovered)
        XCTAssertEqual(model.constraintEnds, [])

        // Layer 9's folded UIKit constraints: their one end, plainly.
        await select(9, in: model)
        let folded = try XCTUnwrap(controller.constraintsView?.generatedBox)
        folded.point(true)
        XCTAssertEqual(model.constraintEnds.map(\.mark), [.layer(2)])
        XCTAssertEqual(model.emphasizedConstraintEnds, [])
        folded.point(false)
        XCTAssertEqual(model.constraintEnds, [])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    /// The middle of a row, in the window.
    @MainActor
    private static func middle(of row: NSView) -> NSPoint {
        row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
    }

    /// Reported by the user (2026-10-20): scrolling the attribute panel over the constraints
    /// left rows filled and their ends marked, several at once. The section now says which
    /// row the pointer is on, from where it is, and points at nothing while the list scrolls.
    @MainActor
    func test_C_LAYOUT_07_onlyTheRowUnderThePointerIsPointedAtAndScrollingPointsAtNothing() async throws {
        let (model, session, server) = try await Self.inspection(answering: [3])
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: model.selectedLayerSummary,
            tree: model.$tree.eraseToAnyPublisher(),
            onPointConstraints: { [weak model] pointer in
                switch pointer {
                case .entered(let indices, let stresses):
                    model?.pointConstraints(indices, stresses: stresses)
                case .left(let indices):
                    model?.leaveConstraints(indices)
                }
            },
            loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        await select(3, in: model)
        window.layoutIfNeeded()
        let section = try XCTUnwrap(controller.constraintsView)
        XCTAssertGreaterThanOrEqual(section.rows.count, 2)
        // The first two rows in view, with room to scroll a little.
        let firstTwo = section.rows[0].frame.union(section.rows[1].frame)
        section.rows[0].superview?.scrollToVisible(firstTwo.insetBy(dx: 0, dy: -40))
        window.layoutIfNeeded()
        controller.constraintsView?.pointerMayHaveMoved()

        // From one row to the next without the pointer leaving the first, as when rows move
        // under it: only the second is pointed at, and only its ends are marked.
        section.pointerMoved(to: Self.middle(of: section.rows[0]))
        XCTAssertEqual(section.rows.map(\.isHovered).prefix(2), [true, false])
        section.pointerMoved(to: Self.middle(of: section.rows[1]))
        XCTAssertEqual(section.rows.map(\.isHovered).prefix(2), [false, true])
        let marked = model.constraintEnds
        section.rows[1].point(false)
        section.rows[1].point(true)
        XCTAssertEqual(model.constraintEnds, marked, "the second row's ends alone")

        // The list scrolls: nothing is pointed at, and rows passing under the pointer stay
        // plain until it is still.
        let origin = controller.list.contentView.bounds.origin
        controller.list.contentView.scroll(to: NSPoint(x: 0, y: origin.y + 4))
        controller.list.reflectScrolledClipView(controller.list.contentView)
        XCTAssertFalse(section.rows.contains(where: \.isHovered))
        XCTAssertEqual(model.constraintEnds, [])
        section.pointerMoved(to: Self.middle(of: section.rows[0]))
        XCTAssertFalse(section.rows[0].isHovered, "not while it scrolls")
        // Once still, the row under the pointer is pointed at again.
        section.pointerMayHaveMoved()
        section.pointerMoved(to: Self.middle(of: section.rows[0]))
        XCTAssertTrue(section.rows[0].isHovered)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_06_aChipThatGoesNowhereIsNotHovered() throws {
        let end = ConstraintRow.End(
            name: "ID 42", kind: .view(LayerIcon(.container, .view, isAppClass: false)), layerID: nil,
            mark: nil)
        var hovered: [ConstraintRow.End?] = []
        let view = ConstraintEquationView(
            [.selfItem, .text(".width = "), .end(end), .text(".width")], dimmed: false,
            onShowLayer: { _ in XCTFail("it goes nowhere") })
        view.onHoverEnd = { hovered.append($0) }
        view.hoverEnd(at: try XCTUnwrap(view.chips.first).index)
        XCTAssertNil(view.hoveredIndex)
        XCTAssertTrue(hovered.isEmpty)
        XCTAssertEqual(view.linkedLayerIDs, [])
    }
}
