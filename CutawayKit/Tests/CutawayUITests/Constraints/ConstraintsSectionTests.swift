import AppKit
import Combine
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The Constraints section of the attribute panel (C-LAYOUT-02) and its links (C-LAYOUT-03),
/// by the `layout-constraints` fixture on the layers of `hierarchy`. Checked by its views and
/// texts, not by eye.
final class ConstraintsSectionTests: XCTestCase {
    /// An entered inspection whose screenshots are all in, on a server that speaks `minor` and
    /// answers the requests for attributes with `answers`' layers, in order
    /// (`Fixtures.panelDetail`).
    @MainActor
    static func inspection(
        answering answers: [UInt64], serverMinor minor: UInt16? = nil
    ) async throws -> (InspectionStore, Session, MockServer) {
        try await inspection(
            serving: try answers.map { try Fixtures.panelDetail(of: $0) }, serverMinor: minor)
    }

    /// The same, answering the requests for attributes with `details`, in order.
    @MainActor
    static func inspection(
        serving details: [LayerDetail], serverMinor minor: UInt16? = nil
    ) async throws -> (InspectionStore, Session, MockServer) {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        // A server at 0.`minor` is met by a client at 0.5: 1.0 would not connect to it.
        var version = ProtocolVersion.current
        if let minor {
            guard case .send(var hello) = steps[1], case .hello(var body) = hello.body else {
                throw RequestError.protocolViolation("the handshake script changed shape")
            }
            body.protocolVersion = Version(major: 0, minor: minor)
            hello.body = .hello(body)
            steps[1] = .send(hello)
            version = Fixtures.zeroMajorProtocol
        }
        for (index, detail) in details.enumerated() {
            steps += MockScript.layerDetailsSteps([detail], as: 60 + UInt32(index))
        }
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: ClientInfo(name: "Cutaway", version: "0.4.0"),
            protocolVersion: version)
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let settled = await Wait.until {
            await MainActor.run {
                // Editing comes with the version, and the constraints with it.
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
    private func labels(_ identifier: String, in view: NSView) -> [String] {
        Self.descendants(of: view, identifier: identifier)
            .compactMap { ($0 as? NSTextField)?.stringValue }
    }

    @MainActor
    private static func descendants(of view: NSView, identifier: String) -> [NSView] {
        (view.accessibilityIdentifier() == identifier ? [view] : [])
            + view.subviews.flatMap { descendants(of: $0, identifier: identifier) }
    }

    @MainActor
    private func statusLabel(_ row: ConstraintRowView) -> String? {
        Self.descendants(of: row, identifier: ConstraintRowView.statusIdentifier).first?
            .accessibilityLabel()
    }

    /// The groups, then a shown separator, then the Constraints section, in the list's stack.
    @MainActor
    private func assertSectionComesLast(
        _ controller: AttributesViewController, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let section = try XCTUnwrap(controller.constraintsView, file: file, line: line)
        let stack = try XCTUnwrap(section.superview as? NSStackView, file: file, line: line)
        let arranged = stack.arrangedSubviews
        XCTAssertTrue(arranged.last === section, "the section is last", file: file, line: line)
        let groups = controller.groupViews.compactMap { group in
            arranged.firstIndex { $0 === group }
        }
        XCTAssertEqual(groups.count, controller.groupViews.count, file: file, line: line)
        XCTAssertEqual(groups, groups.sorted(), file: file, line: line)
        let separator = arranged[arranged.count - 2]
        XCTAssertFalse(controller.groupViews.contains { $0 === separator }, file: file, line: line)
        XCTAssertFalse(separator.isHidden, "a line between the groups and it", file: file, line: line)
    }

    @MainActor
    private func message(_ controller: AttributesViewController) -> NSTextField? {
        AppListViewTests.descendant(
            of: controller.view, identifier: AttributesViewController.messageIdentifier)
            as? NSTextField
    }

    // MARK: - C-LAYOUT-02

    @MainActor
    func test_C_LAYOUT_02_layerThreeListsItsFourConstraintsAfterTheGroups() async throws {
        let (model, session, server) = try await Self.inspection(answering: [3])
        let (controller, window) = panel(for: model)
        await select(3, in: model)
        window.layoutIfNeeded()

        let section = try XCTUnwrap(controller.constraintsView)
        XCTAssertTrue(isShown(section))
        XCTAssertEqual(controller.groupViews.count, 3, "the attributes are listed too")
        try assertSectionComesLast(controller)
        // The groups built again (here: the connection goes, and the editors with it) go
        // before the section, which stays.
        model.connectionLost()
        XCTAssertTrue(controller.constraintsView === section)
        try assertSectionComesLast(controller)

        let header = try XCTUnwrap(AppListViewTests.descendant(
            of: section, identifier: ConstraintsSectionView.headerIdentifier) as? NSButton)
        XCTAssertEqual(header.accessibilityLabel(), "Constraints")
        XCTAssertEqual(header.title, " Constraints  4")
        XCTAssertEqual(section.rows.map(\.equationView.string), [
            "self.centerX = UIView.centerX",
            "self.top = Safe Area.top + 49",
            "self.width = 240",
            "CardView.top = self.bottom + 78",
        ])
        XCTAssertTrue(section.rows.allSatisfy { isShown($0) })
        // The second goes to the safe area of layer 2, and says so.
        XCTAssertEqual(
            labels(ConstraintRowView.ownerIdentifier, in: section.rows[1]),
            ["Safe Area of UIView"])
        // The third: priority 250, not in effect.
        XCTAssertEqual(
            labels(ConstraintRowView.detailIdentifier, in: section.rows[2]),
            ["Priority 250 · titleLabel.preferredWidth"])
        XCTAssertEqual(statusLabel(section.rows[2]), "Not in effect")
        let tag = Self.descendants(
            of: section.rows[2], identifier: ConstraintRowView.notInEffectIdentifier)
        XCTAssertEqual(tag.count, 1)
        XCTAssertEqual(
            section.rows.map { statusLabel($0) },
            ["In effect", "In effect", "Not in effect", "In effect"])
        for index in [0, 1, 3] {
            XCTAssertEqual(Self.descendants(
                of: section.rows[index], identifier: ConstraintRowView.notInEffectIdentifier
            ).count, 0)
        }
        XCTAssertNil(AppListViewTests.descendant(
            of: section, identifier: ConstraintsSectionView.generatedIdentifier))

        // The section folds away from its header, as a group does.
        header.performClick(nil)
        XCTAssertFalse(isShown(section.rows[0]))
        XCTAssertEqual(header.accessibilityValue() as? String, "Collapsed")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_02_constraintsUIKitMadeAreFoldedIntoOneLastRow() async throws {
        let (model, session, server) = try await Self.inspection(answering: [9])
        let (controller, window) = panel(for: model)
        await select(9, in: model)
        window.layoutIfNeeded()

        let section = try XCTUnwrap(controller.constraintsView)
        XCTAssertNil(message(controller).flatMap { isShown($0) ? $0.stringValue : nil },
                     "no attributes, but the section is listed")
        XCTAssertTrue(isShown(section))
        let fold = try XCTUnwrap(AppListViewTests.descendant(
            of: section, identifier: ConstraintsSectionView.generatedIdentifier) as? NSButton)
        XCTAssertTrue(isShown(fold))
        XCTAssertEqual(fold.accessibilityLabel(), "4 from UIKit")
        XCTAssertEqual(fold.title, " 4 from UIKit  Autoresizing Mask")
        XCTAssertEqual(section.rows.count, 4)
        XCTAssertTrue(section.rows.allSatisfy { !isShown($0) }, "folded by default")

        fold.performClick(nil)
        XCTAssertTrue(section.rows.allSatisfy { isShown($0) })
        XCTAssertEqual(section.rows.map(\.equationView.string), [
            "UIView.width = self.maxX + 93",
            "self.width = 0",
            "self.minY = 700",
            "self.height = 0",
        ])
        // The superview, written first, can be chosen (C-LAYOUT-05).
        XCTAssertEqual(section.rows.map(\.equationView.linkedLayerIDs), [[2], [], [], []])
        XCTAssertEqual(
            section.rows.flatMap { labels(ConstraintRowView.classIdentifier, in: $0) },
            Array(repeating: "NSAutoresizingMaskLayoutConstraint", count: 4))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_02_aLayerThatBacksNoViewHasNoSectionAndAViewWithoutConstraintsSaysSo()
        async throws
    {
        let (model, session, server) = try await Self.inspection(answering: [8, 2])
        let (controller, window) = panel(for: model)

        // Layer 8 backs no view: no section, and nothing says why.
        await select(8, in: model)
        XCTAssertNil(controller.constraintsView)
        XCTAssertNil(controller.constraintRows)
        XCTAssertEqual(message(controller)?.stringValue, "No Attributes")

        // Layer 2 is a view the fixture gives no constraints.
        await select(2, in: model)
        let section = try XCTUnwrap(controller.constraintsView)
        XCTAssertTrue(isShown(section))
        XCTAssertEqual(section.rows.count, 0)
        XCTAssertEqual(labels(ConstraintsSectionView.emptyIdentifier, in: section), ["No Constraints"])
        let header = try XCTUnwrap(AppListViewTests.descendant(
            of: section, identifier: ConstraintsSectionView.headerIdentifier) as? NSButton)
        XCTAssertEqual(header.title, " Constraints")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_02_aServerBelow04HasNoSection() async throws {
        let (model, session, server) = try await Self.inspection(answering: [3], serverMinor: 3)
        let (controller, window) = panel(for: model)
        await select(3, in: model)

        XCTAssertEqual(controller.groupViews.count, 3)
        XCTAssertNil(controller.constraintsView)
        // The session left the constraints out (C-LAYOUT-01); the fixture's answer had them.
        let asked = await server.receivedFrames.compactMap { frame -> LayerDetailRequest? in
            guard case .getLayerDetails(let request) = frame.body,
                  request.requests.first?.wantAttributes == true
            else { return nil }
            return request.requests.first
        }
        XCTAssertEqual(asked.map(\.wantConstraints), [false])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_02_theThreeStatusesHaveMarksOfTheirOwn() throws {
        var constraint = try Fixtures.constraints(of: 3)[0]
        let tree = try LayerTree(try Fixtures.hierarchy())
        var marks: [String] = []
        for status in [ConstraintStatus.satisfied, .unsatisfied, .unknown] {
            constraint.status = status
            let row = ConstraintRowView(
                ConstraintRow(constraint, selected: 3, tree: tree), showsClass: false,
                onShowLayer: { _ in })
            let image = try XCTUnwrap(Self.descendants(
                of: row, identifier: ConstraintRowView.statusIdentifier).first as? NSImageView)
            XCTAssertNotNil(image.image, "\(status)")
            marks.append(image.accessibilityLabel() ?? "")
            let style = ConstraintRowView.status(status)
            XCTAssertEqual(image.contentTintColor, style.color)
            // Only the one not in effect is dimmed and tagged.
            let tagged = !Self.descendants(
                of: row, identifier: ConstraintRowView.notInEffectIdentifier).isEmpty
            XCTAssertEqual(tagged, status == .unsatisfied)
            let color = row.equationView.textStorage?.attribute(
                .foregroundColor, at: row.equationView.string.count - 1, effectiveRange: nil)
                as? NSColor
            XCTAssertEqual(color, status == .unsatisfied ? .secondaryLabelColor : .labelColor)
        }
        XCTAssertEqual(marks, ["In effect", "Not in effect", "Unknown"])
        let styles = [ConstraintStatus.satisfied, .unsatisfied, .unknown]
            .map(ConstraintRowView.status)
        XCTAssertEqual(Set(styles.map(\.symbol)).count, 3, "a symbol of its own for each")
        XCTAssertEqual(Set(styles.map(\.symbol)), Set(ConstraintRowView.symbols))
    }

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

        // Layer 2 under another name: the section says it; the attribute rows stay as they are,
        // so that a field being typed in keeps its focus (C-ATTR-06).
        var renamed = try Fixtures.hierarchy()
        let two = try XCTUnwrap(renamed.nodes.firstIndex { $0.id == 2 })
        renamed.nodes[two].viewDisplayClassName = "RootView"
        model.apply(renamed)
        let rebuilt = try XCTUnwrap(controller.constraintsView)
        XCTAssertFalse(rebuilt === section)
        XCTAssertEqual(rebuilt.rows[0].equationView.string, "self.centerX = RootView.centerX")
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
        let titles = controller.groupViews.map(\.title)

        // A new round, as a refresh starts (C-DET-05).
        model.attributes.select(3, newRound: model.tree)
        let answered = await Wait.untilOnMain { controller.groupViews.map(\.title) != titles }
        XCTAssertTrue(answered, "the renamed attributes")
        XCTAssertTrue(controller.constraintsView === section, "the same constraints")
        try assertSectionComesLast(controller)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_02_aLongEquationWrapsToTheWidthItHas() throws {
        var constraint = try Fixtures.constraints(of: 3)[0]
        constraint.secondItem = .other(
            className: nil,
            displayClassName: "AVeryLongClassNameThatCannotFitOnOneLineOfThePanel"
                + "AndStillGoesOnForAWhileLonger")
        let row = ConstraintRowView(
            ConstraintRow(constraint, selected: 3, tree: try LayerTree(try Fixtures.hierarchy())),
            showsClass: false, onShowLayer: { _ in })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 400), styleMask: [.titled],
            backing: .buffered, defer: false)
        let container = NSView()
        window.contentView = container
        container.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        window.layoutIfNeeded()
        window.layoutIfNeeded()

        let equation = row.equationView
        XCTAssertLessThanOrEqual(equation.frame.maxX, row.bounds.width)
        let manager = try XCTUnwrap(equation.layoutManager)
        let container2 = try XCTUnwrap(equation.textContainer)
        manager.ensureLayout(for: container2)
        let used = manager.usedRect(for: container2)
        XCTAssertGreaterThan(used.height, 20, "more than one line")
        XCTAssertLessThanOrEqual(used.width, equation.frame.width + 0.5)
        XCTAssertGreaterThanOrEqual(equation.frame.height, used.height.rounded(.down), "all of it shows")
    }

    @MainActor
    func test_C_LAYOUT_02_everySymbolOfTheSectionExists() {
        for name in ConstraintRowView.symbols + ["chevron.right", "chevron.down"] {
            XCTAssertNotNil(Theme.symbol(name), name)
        }
        XCTAssertTrue(AttributesViewController.symbols.contains("questionmark.circle"))
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
            section.rows[3].equationView.string, "CardView.unknown = self.unknown + 78")
        XCTAssertNil(message(controller).flatMap { isShown($0) ? $0.stringValue : nil })
        XCTAssertEqual(section.rows[3].equationView.linkedLayerIDs, [4])
        section.rows[3].equationView.clickLink(to: 4)
        XCTAssertEqual(shown, [4])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - C-LAYOUT-03

    @MainActor
    func test_C_LAYOUT_03_aNameInTheAccentColourAsksForItsLayer() async throws {
        let (model, session, server) = try await Self.inspection(answering: [3])
        var shown: [UInt64] = []
        let (controller, window) = panel(for: model) { shown.append($0) }
        await select(3, in: model)
        let section = try XCTUnwrap(controller.constraintsView)

        // Layer 2, its safe area (whose owner is layer 2), nothing, layer 4.
        XCTAssertEqual(section.rows.map(\.equationView.linkedLayerIDs), [[2], [2], [], [4]])
        section.rows[3].equationView.clickLink(to: 4)
        section.rows[1].equationView.clickLink(to: 2)
        XCTAssertEqual(shown, [4, 2])
        XCTAssertEqual(model.selectedLayerID, 3, "the panel only asks; the inspection selects")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }
}
