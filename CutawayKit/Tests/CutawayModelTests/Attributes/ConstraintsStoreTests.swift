import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// The selected layer's constraints, asked for with its attributes (C-LAYOUT-01), and going to
/// the layer at a constraint's other end (C-LAYOUT-03).
final class ConstraintsStoreTests: XCTestCase {
    private static let text = AttributeKey(layerID: 3, attributeID: "label.text")

    /// What the panel asks for a layer.
    private static func panelRequest(_ id: UInt64) -> GetLayerDetails {
        GetLayerDetails(
            requests: [LayerDetailRequest(
                layerID: id, wantSolo: false, wantGroup: false, wantAttributes: true,
                wantConstraints: true)],
            maxTextureDimension: 0)
    }

    /// Layer 3 as the panel gets it: `layer-details`' attributes, `layout-constraints`'
    /// constraints.
    private static func three() throws -> LayerDetail {
        try Fixtures.panelDetail(of: 3)
    }

    /// Layer 3 after a change: the change's attributes, and constraint 3 in effect.
    private static func threeAfterChange() throws -> LayerDetail {
        var detail = try three()
        detail.attributeGroups = try Fixtures.setAttributeResults()[0].attributeGroups
        detail.constraints[2].status = .satisfied
        return detail
    }

    private static func result(_ requestID: UInt32) throws -> [MockScript.Step] {
        [
            .expect(.setAttribute, as: requestID),
            .send(Frame(requestID: requestID, body: .setAttributeResult(SetAttributeResult(
                layerID: 3, attributeGroups: try threeAfterChange().attributeGroups)))),
        ]
    }

    private static func requests(_ server: MockServer) async -> [GetLayerDetails] {
        await InspectionStoreDetailsTests.detailRequests(server)
    }

    /// An open model on a session to a server that plays the handshake, then `steps`.
    @MainActor
    private func openModel(
        _ steps: [MockScript.Step], editing: Bool = false
    ) async throws -> (AttributesStore, Session, MockServer) {
        let server = try await MockServer.start(
            script: MockScript(steps: try MockScript.fixtures("handshake").steps + steps))
        let session = try await AttributesStoreTests.session(to: server)
        let model = AttributesStore(session: session)
        model.setOpen(true)
        model.setEditingSupported(editing)
        return (model, session, server)
    }

    /// The model's state is `detail`'s attributes and constraints.
    @MainActor
    private func shows(_ model: AttributesStore, _ detail: LayerDetail) async -> Bool {
        await Wait.until {
            await model.state == .loaded(detail.attributeGroups, constraints: detail.constraints)
        }
    }

    // MARK: - C-LAYOUT-01: asking

    @MainActor
    func test_C_LAYOUT_01_theAttributesRequestAsksForConstraintsAndHoldsThemWithTheAttributes()
        async throws
    {
        let three = try Self.three()
        let (model, session, server) = try await openModel(
            MockScript.layerDetailsSteps([three], as: 10))

        model.select(3)
        let loaded = await shows(model, three)
        XCTAssertTrue(loaded, "\(model.state)")
        XCTAssertEqual(three.constraints.map(\.id), [1, 2, 3, 4])
        let requests = await Self.requests(server)
        XCTAssertEqual(requests, [Self.panelRequest(3)])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_01_aNewRoundAsksForTheConstraintsAgainAndShowsTheOldOnesUntilThen()
        async throws
    {
        let gate = MockGate()
        let three = try Self.three()
        var renewed = three
        renewed.constraints.removeLast()
        var steps = MockScript.layerDetailsSteps([three], as: 10)
        var again = MockScript.layerDetailsSteps([renewed], as: 11)
        again.insert(.hold(gate), at: 1)
        steps += again
        let (model, session, server) = try await openModel(steps)
        model.select(3)
        let loaded = await shows(model, three)
        XCTAssertTrue(loaded)

        // A refresh (C-DET-05) and a subtree's refresh (C-DET-07) both start a round.
        model.select(3, newRound: try LayerTree(try Fixtures.hierarchy()))
        let asked = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(asked)
        XCTAssertEqual(
            model.state, .loaded(three.attributeGroups, constraints: three.constraints),
            "the old ones stay shown")
        let requests = await Self.requests(server)
        XCTAssertEqual(requests.last, Self.panelRequest(3))

        await gate.open()
        let shown = await shows(model, renewed)
        XCTAssertTrue(shown)

        await session.close()
        await server.stop()
    }

    // MARK: - C-LAYOUT-01: after a change

    @MainActor
    func test_C_LAYOUT_01_aChangedLayersConstraintsAreAskedForAgainOnceTheChangeIsOver()
        async throws
    {
        let gate = MockGate()
        let three = try Self.three()
        let after = try Self.threeAfterChange()
        var steps = MockScript.layerDetailsSteps([three], as: 10)
        steps += try Self.result(20)
        var again = MockScript.layerDetailsSteps([after], as: 11)
        again.insert(.hold(gate), at: 1)
        steps += again
        let (model, session, server) = try await openModel(steps, editing: true)
        model.select(3)
        let loaded = await shows(model, three)
        XCTAssertTrue(loaded)

        model.set(Self.text, to: .string("Welcome back"), continuous: false)
        let asked = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(asked, "the change may have moved the layer's constraints in or out of effect")
        let requests = await Self.requests(server)
        XCTAssertEqual(requests.last, Self.panelRequest(3))
        // The answer's attributes at once, the old constraints until the new ones come.
        XCTAssertEqual(
            model.state, .loaded(after.attributeGroups, constraints: three.constraints))

        await gate.open()
        let renewed = await shows(model, after)
        XCTAssertTrue(renewed)
        XCTAssertEqual(model.edits, [:])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_01_aDragAsksForTheConstraintsOnceWhenItEnds() async throws {
        let three = try Self.three()
        let after = try Self.threeAfterChange()
        var steps = MockScript.layerDetailsSteps([three], as: 10)
        steps += try Self.result(20)
        steps += MockScript.layerDetailsSteps([after], as: 11)
        let (model, session, server) = try await openModel(steps, editing: true)
        model.select(3)
        let loaded = await shows(model, three)
        XCTAssertTrue(loaded)

        model.set(Self.text, to: .string("Welcome back"), continuous: true)
        let answered = await Wait.until {
            await model.state == .loaded(after.attributeGroups, constraints: three.constraints)
        }
        XCTAssertTrue(answered)
        try await Task.sleep(for: .milliseconds(100))
        var requests = await Self.requests(server)
        XCTAssertEqual(requests.count, 1, "not while the drag goes on")

        model.finish(Self.text)
        let renewed = await shows(model, after)
        XCTAssertTrue(renewed)
        try await Task.sleep(for: .milliseconds(100))
        requests = await Self.requests(server)
        XCTAssertEqual(requests.count, 2)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_01_aChangesAnswerCancelsTheLayersRequestUnderWay() async throws {
        let three = try Self.three()
        let after = try Self.threeAfterChange()
        var steps = MockScript.layerDetailsSteps([three], as: 10)
        steps += try Self.result(20)
        // Asked for again after the first change; not answered before the second change's
        // answer, which makes it out of date.
        steps.append(.expect(.getLayerDetails, as: 11))
        steps += try Self.result(21)
        steps += [
            .expect(.cancel, as: 99),
            .send(Frame(requestID: 11, body: .streamEnd(StreamEnd(
                status: .cancelled, chunkCount: 0, error: nil)))),
        ]
        steps += MockScript.layerDetailsSteps([after], as: 12)
        let (model, session, server) = try await openModel(steps, editing: true)
        model.select(3)
        let loaded = await shows(model, three)
        XCTAssertTrue(loaded)

        model.set(Self.text, to: .string("Welcome"), continuous: false)
        let asked = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(asked)
        model.set(Self.text, to: .string("Welcome back"), continuous: false)

        let renewed = await shows(model, after)
        XCTAssertTrue(renewed, "\(model.state)")
        let requests = await Self.requests(server)
        XCTAssertEqual(requests, [Self.panelRequest(3), Self.panelRequest(3), Self.panelRequest(3)])
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(
            Array(kinds.suffix(4)), [.getLayerDetails, .setAttribute, .cancel, .getLayerDetails])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_01_theChangedLayerIsAskedForAfterTheWindowsSubtree() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += MockScript.layerDetailsSteps([try Self.three()], as: 15)
        steps += try Self.result(30)
        steps += [
            .expect(.getSubtree, as: 31),
            .send(Frame(requestID: 31, body: .hierarchy(try Fixtures.hierarchy()))),
            // Layer 3's screenshot and its attributes, in either order.
            .expect(.getLayerDetails, as: 70),
            .expect(.getLayerDetails, as: 71),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await AttributesStoreTests.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let settled = await Wait.until {
            await MainActor.run {
                model.attributes.canEdit
                    && model.detailProgress == DetailProgress(completed: 7, total: 7)
            }
        }
        XCTAssertTrue(settled)
        model.select(3)
        let loaded = await Wait.until {
            if case .loaded(_, let constraints) = await model.attributes.state {
                return constraints.count == 4
            }
            return false
        }
        XCTAssertTrue(loaded)

        model.attributes.set(Self.text, to: .string("Welcome back"), continuous: false)
        let asked = await Wait.until {
            await Self.requests(server).filter { $0 == Self.panelRequest(3) }.count == 2
        }
        XCTAssertTrue(asked)
        // P-SET-05: what the app laid out after the change is read after the window is taken.
        let bodies = await server.receivedFrames.map(\.body)
        let subtree = try XCTUnwrap(bodies.firstIndex(of: .getSubtree(GetSubtree(rootID: 1))))
        let again = try XCTUnwrap(bodies.lastIndex(of: .getLayerDetails(Self.panelRequest(3))))
        XCTAssertLessThan(subtree, again)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_01_aChangeWaitingForItsAnswerHoldsTheRequestBack() async throws {
        let gate = MockGate()
        let three = try Self.three()
        let after = try Self.threeAfterChange()
        var steps = MockScript.layerDetailsSteps([three], as: 10)
        var result = try Self.result(20)
        result.insert(.hold(gate), at: 1)
        steps += result
        steps += MockScript.layerDetailsSteps([after], as: 11)
        let (model, session, server) = try await openModel(steps, editing: true)
        model.select(3)
        let loaded = await shows(model, three)
        XCTAssertTrue(loaded)

        model.set(Self.text, to: .string("Welcome back"), continuous: false)
        let sent = await Wait.until {
            await server.receivedFrames.contains { MessageKind($0.body) == .setAttribute }
        }
        XCTAssertTrue(sent)
        // A refresh while the change waits: what it would read is out of date once the
        // answer comes.
        model.select(3, newRound: try LayerTree(try Fixtures.hierarchy()))
        try await Task.sleep(for: .milliseconds(100))
        var requests = await Self.requests(server)
        XCTAssertEqual(requests.count, 1, "held back")

        await gate.open()
        let renewed = await shows(model, after)
        XCTAssertTrue(renewed)
        requests = await Self.requests(server)
        XCTAssertEqual(requests.count, 2)
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertFalse(kinds.contains(.cancel), "nothing went out to be cancelled")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_01_aDragWhoseLastValueIsRejectedStillAsksAgain() async throws {
        let three = try Self.three()
        let after = try Self.threeAfterChange()
        var steps = MockScript.layerDetailsSteps([three], as: 10)
        steps += try Self.result(20)
        steps += [
            .expect(.setAttribute, as: 21),
            .send(Frame(requestID: 21, body: .error(ServerError(
                code: .invalidAttributeValue, message: "no")))),
        ]
        steps += MockScript.layerDetailsSteps([after], as: 11)
        let (model, session, server) = try await openModel(steps, editing: true)
        model.select(3)
        let loaded = await shows(model, three)
        XCTAssertTrue(loaded)

        model.set(Self.text, to: .string("Welcome"), continuous: true)
        let first = await Wait.until {
            await model.state == .loaded(after.attributeGroups, constraints: three.constraints)
        }
        XCTAssertTrue(first)
        // The first value took: the layer may have been laid out again.
        model.set(Self.text, to: .string(""), continuous: false)
        let renewed = await shows(model, after)
        XCTAssertTrue(renewed, "\(model.state)")
        let requests = await Self.requests(server)
        XCTAssertEqual(requests.count, 2)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_01_anUndoAsksForTheConstraintsAgain() async throws {
        let three = try Self.three()
        let after = try Self.threeAfterChange()
        var undone = three
        undone.constraints[0].constant = 1
        var steps = MockScript.layerDetailsSteps([three], as: 10)
        steps += try Self.result(20)
        steps += MockScript.layerDetailsSteps([after], as: 11)
        steps += [
            .expect(.setAttribute, as: 21),
            .send(Frame(requestID: 21, body: .setAttributeResult(SetAttributeResult(
                layerID: 3, attributeGroups: three.attributeGroups)))),
        ]
        steps += MockScript.layerDetailsSteps([undone], as: 12)
        let (model, session, server) = try await openModel(steps, editing: true)
        model.select(3)
        let loaded = await shows(model, three)
        XCTAssertTrue(loaded)
        model.set(Self.text, to: .string("Welcome back"), continuous: false)
        let changed = await shows(model, after)
        XCTAssertTrue(changed)

        model.undoManager.undo()
        let renewed = await shows(model, undone)
        XCTAssertTrue(renewed, "\(model.state)")
        let sets = await server.receivedFrames.filter { MessageKind($0.body) == .setAttribute }
        XCTAssertEqual(sets.count, 2)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - C-LAYOUT-03: the other end

    /// A model showing the `hierarchy` fixture, with no connection behind it.
    @MainActor
    private func inspection() throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(
                channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.4.0")),
            newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        return model
    }

    @MainActor
    func test_C_LAYOUT_03_theLayerItselfIsSelectedEvenUnderACollapsedNode() throws {
        let model = try inspection()
        model.collapseAll()
        model.select(5)
        XCTAssertEqual(model.selectedLayerID, 1, "select picks the row that stands for it")

        model.showLayer(5)
        XCTAssertEqual(model.selectedLayerID, 5)
        XCTAssertTrue(model.isExpanded(4))
        XCTAssertTrue(model.isExpanded(1))
    }

    @MainActor
    func test_C_LAYOUT_03_aLayerOutsideTheFocusEndsTheFocusFirst() throws {
        let model = try inspection()
        model.focus(on: 6)
        model.select(7)
        XCTAssertEqual(model.selectedLayerID, 7)

        model.showLayer(4)
        XCTAssertNil(model.focusedLayerID)
        XCTAssertEqual(model.selectedLayerID, 4)

        // One inside the focus keeps it.
        model.focus(on: 4)
        model.showLayer(5)
        XCTAssertEqual(model.focusedLayerID, 4)
        XCTAssertEqual(model.selectedLayerID, 5)
    }

    @MainActor
    func test_C_LAYOUT_03_aLayerNotInTheTreeChangesNothing() throws {
        let model = try inspection()
        model.focus(on: 6)
        model.select(7)

        model.showLayer(42)
        XCTAssertEqual(model.focusedLayerID, 6)
        XCTAssertEqual(model.selectedLayerID, 7)
    }
}
