import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// The attributes of the selected layer, asked for over the connection one layer at a time
/// (C-ATTR-01 to C-ATTR-03).
final class AttributesStoreTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    static func session(
        to server: MockServer, protocolVersion: Version = ProtocolVersion.current,
        requestTimeout: Duration = .seconds(10)
    ) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, protocolVersion: protocolVersion,
            requestTimeout: requestTimeout)
        _ = try await session.handshake()
        return session
    }

    /// A request for a layer's attributes and constraints and no image, as it reaches a 0.4
    /// server (C-LAYOUT-01).
    static func attributesOnly(_ id: UInt64) -> LayerDetailRequest {
        LayerDetailRequest(
            layerID: id, wantSolo: false, wantGroup: false, wantAttributes: true,
            wantConstraints: true)
    }

    /// Layer 3 of `layer-details`: three groups, twelve attributes.
    static func layerThree() throws -> [AttributeGroup] {
        try Fixtures.attributes(of: 3, scenario: "layer-details")
    }

    /// An open model on a session to a server that plays `script`.
    @MainActor
    private func openModel(
        _ script: MockScript, requestTimeout: Duration = .seconds(10)
    ) async throws -> (AttributesStore, Session, MockServer) {
        let server = try await MockServer.start(script: script)
        let session = try await Self.session(to: server, requestTimeout: requestTimeout)
        let model = AttributesStore(session: session)
        model.setOpen(true)
        return (model, session, server)
    }

    // MARK: - Asking

    @MainActor
    func test_C_ATTR_01_aSelectedLayerShowsItsGroupsInTheOrderTheyArrived() async throws {
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details"))
        XCTAssertEqual(model.state, .none)

        model.select(3)
        XCTAssertEqual(model.state, .loading)
        let expected = try Self.layerThree()
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)
        XCTAssertEqual(expected.map(\.id), ["layer", "label", "view"])
        XCTAssertEqual(expected.flatMap(\.attributes).count, 19)

        // One layer, its attributes and no image.
        let requests = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(
            requests, [GetLayerDetails(requests: [Self.attributesOnly(3)], maxTextureDimension: 0)])
        // Only the layer asked for is kept: 4 and 99 came along in the replay.
        XCTAssertEqual(model.heldLayerIDs, [3])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        model.select(nil)
        XCTAssertEqual(model.state, .none)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_nothingIsAskedForWhileTheInspectionIsClosed() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "layer-details"))
        let session = try await Self.session(to: server)
        let model = AttributesStore(session: session)

        model.select(3)
        try await Task.sleep(for: .milliseconds(200))
        let before = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(before, [])
        XCTAssertEqual(model.state, .loading)

        model.setOpen(true)
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_nothingIsAskedForWhileAHierarchyIsOnItsWay() async throws {
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details"))
        model.setTreeLoading(true)

        model.select(3)
        try await Task.sleep(for: .milliseconds(200))
        let before = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(before, [])

        model.setTreeLoading(false)
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aLayerAlreadyAnsweredIsShownWithoutAskingAgain() async throws {
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details"))
        let expected = try Self.layerThree()
        model.select(3)
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)

        model.select(nil)
        model.select(3)
        XCTAssertEqual(model.state, .loaded(expected), "shown at once")
        XCTAssertEqual(model.requestsStarted, 1)
        try await Task.sleep(for: .milliseconds(200))
        let requests = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(requests.count, 1)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Cancelling

    @MainActor
    func test_C_ATTR_01_selectingAnotherLayerCancelsTheRequestUnderWay() async throws {
        // layer-details-cancelled waits for a Cancel after its first chunk; layer-details-edge
        // then answers the next request, with layer 9's attributes.
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details-cancelled", "layer-details-edge"))

        model.select(2)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 1
        }
        XCTAssertTrue(asked)
        model.select(9)

        let expected = try Fixtures.attributes(of: 9, scenario: "layer-details-edge")
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)
        let frames = await server.receivedFrames
        XCTAssertEqual(
            frames.map { MessageKind($0.body) }, [.hello, .getLayerDetails, .cancel, .getLayerDetails])
        XCTAssertEqual(frames[2].body, .cancel(Cancel(targetRequestID: frames[1].requestID)))
        XCTAssertEqual(
            frames[3].body,
            .getLayerDetails(GetLayerDetails(
                requests: [Self.attributesOnly(9)], maxTextureDimension: 0)))
        XCTAssertEqual(model.heldLayerIDs, [9], "the cancelled answer is not kept")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aRequestCancelledBeforeItIsSentSendsNothing() async throws {
        let (model, session, server) = try await openModel(try .fixtures("handshake"))

        // Within one turn of the main actor: the request's task has not run yet.
        model.select(3)
        model.select(nil)
        try await Task.sleep(for: .milliseconds(200))
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello])
        XCTAssertEqual(model.state, .none)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_closingCancelsTheRequestUnderWay() async throws {
        var steps = try MockScript.fixtures("handshake").steps
        steps += [.expect(.getLayerDetails, as: 70), .expect(.cancel, as: 71)]
        let (model, session, server) = try await openModel(MockScript(steps: steps))

        model.select(3)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 1
        }
        XCTAssertTrue(asked)
        model.setOpen(false)
        let cancelled = await Wait.until {
            await server.receivedFrames.contains { MessageKind($0.body) == .cancel }
        }
        XCTAssertTrue(cancelled)
        XCTAssertEqual(model.state, .loading)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Answers that are not attributes

    @MainActor
    func test_C_ATTR_01_aLayerTheAppCannotCaptureStillShowsItsAttributes() async throws {
        // P-DET-03: layer 9 failed to capture and brought its attributes.
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details-edge"))
        model.select(9)
        let expected = try Fixtures.attributes(of: 9, scenario: "layer-details-edge")
        XCTAssertFalse(expected.isEmpty)
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aLayerTheAppDoesNotHaveIsReportedGone() async throws {
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details"))
        model.select(99)
        let gone = await Wait.until { await model.state == .layerGone }
        XCTAssertTrue(gone)

        // Kept for the round.
        model.select(nil)
        model.select(99)
        XCTAssertEqual(model.state, .layerGone)
        XCTAssertEqual(model.requestsStarted, 1)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_anAnswerThatLeavesTheLayerOutFailsAndIsAskedForAgain() async throws {
        // layer-details has no layer 5.
        var steps = try MockScript.fixtures("handshake", "layer-details").steps
        steps.append(.expect(.getLayerDetails, as: 80))
        let (model, session, server) = try await openModel(MockScript(steps: steps))

        model.select(5)
        let failed = await Wait.until { await model.state == .failed }
        XCTAssertTrue(failed)

        model.select(nil)
        model.select(5)
        XCTAssertEqual(model.state, .loading, "a failure is not kept")
        let again = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 2
        }
        XCTAssertTrue(again)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aRequestThatTimesOutFailsAndIsAskedForAgain() async throws {
        var steps = try MockScript.fixtures("handshake").steps
        steps.append(.expect(.getLayerDetails, as: 90))  // never answered
        steps += try MockScript.fixtures("layer-details").steps
        let (model, session, server) = try await openModel(
            MockScript(steps: steps), requestTimeout: .milliseconds(300))

        model.select(3)
        let failed = await Wait.until { await model.state == .failed }
        XCTAssertTrue(failed)

        model.select(nil)
        model.select(3)
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Retrying

    @MainActor
    func test_C_ATTR_01_retryingAnAppThatWasNotActiveAsksAgain() async throws {
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details-failed", "layer-details"))

        model.select(3)
        let paused = await Wait.until { await model.state == .appNotActive }
        XCTAssertTrue(paused)

        model.retry()
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_retryingWhatDidNotFailAsksNothing() async throws {
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details", "layer-details"))

        model.retry()
        XCTAssertEqual(model.state, .none, "nothing selected")
        model.select(3)
        model.retry()  // under way
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)
        model.retry()  // answered
        model.select(99)
        let gone = await Wait.until { await model.state == .layerGone }
        XCTAssertTrue(gone)
        model.select(3)
        model.retry()  // answered in this round

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.requestsStarted, 2, "one for layer 3, one for layer 99")
        let requests = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(model.state, .loaded(try Self.layerThree()))

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aFailedRequestIsNotAskedAgainUntilRetried() async throws {
        var steps = try MockScript.fixtures("handshake").steps
        steps.append(.expect(.getLayerDetails, as: 90))  // never answered
        steps += try MockScript.fixtures("layer-details").steps
        let (model, session, server) = try await openModel(
            MockScript(steps: steps), requestTimeout: .milliseconds(300))

        model.select(3)
        let failed = await Wait.until { await model.state == .failed }
        XCTAssertTrue(failed)

        // None of these is the user asking again.
        model.appStateDidChange(.active)
        model.setTreeLoading(true)
        model.setTreeLoading(false)
        model.setOpen(false)
        model.setOpen(true)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.requestsStarted, 1)
        XCTAssertEqual(model.state, .failed)

        model.retry()
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)
        XCTAssertEqual(model.requestsStarted, 2)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_anAppActiveAgainBeforeItsFailureArrivesIsAskedAgain() async throws {
        let gate = MockGate()
        var failed = try MockScript.fixtures("layer-details-failed").steps
        failed.insert(.hold(gate), at: 2)  // after the AppStateChanged, before the StreamEnd
        let steps = try MockScript.fixtures("handshake").steps + failed
            + (try MockScript.fixtures("layer-details").steps)
        let (model, session, server) = try await openModel(MockScript(steps: steps))

        model.select(3)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 1
        }
        XCTAssertTrue(asked)
        model.appStateDidChange(.active)
        await gate.open()

        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded, "stayed \(model.state)")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_anAppThatIsNotActiveIsAskedAgainWhenItIs() async throws {
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details-failed", "layer-details"))

        model.select(3)
        let paused = await Wait.until { await model.state == .appNotActive }
        XCTAssertTrue(paused)

        model.appStateDidChange(.inactive)
        try await Task.sleep(for: .milliseconds(200))
        let before = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(before.count, 1)

        model.appStateDidChange(.active)
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Rounds

    @MainActor
    func test_C_ATTR_01_aNewRoundAsksAgainAndShowsTheOldAttributesUntilThen() async throws {
        let gate = MockGate()
        var renamed = try MockScript.fixtures("layer-details").renamingAttributes().steps
        renamed.insert(.hold(gate), at: 1)  // after the request
        let steps = try MockScript.fixtures("handshake", "layer-details", "layer-details").steps
            + renamed
        let (model, session, server) = try await openModel(MockScript(steps: steps))
        let old = try Self.layerThree()

        model.select(99)
        let gone = await Wait.until { await model.state == .layerGone }
        XCTAssertTrue(gone)
        model.select(3)
        let loaded = await Wait.until { await model.state == .loaded(old) }
        XCTAssertTrue(loaded)
        XCTAssertEqual(model.heldLayerIDs, [3, 99])

        model.select(3, newRound: try LayerTree(try Fixtures.hierarchy()))
        XCTAssertEqual(model.state, .loaded(old), "the old ones stay shown")
        XCTAssertEqual(model.heldLayerIDs, [3], "only the selected layer's answer stays")
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 3
        }
        XCTAssertTrue(asked)
        XCTAssertEqual(model.state, .loaded(old))

        await gate.open()
        let renewed = await Wait.until {
            await model.state == .loaded(Fixtures.renamingAttributes(old))
        }
        XCTAssertTrue(renewed)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Paths found untested in review

    @MainActor
    func test_C_CONN_07_aClosedConnectionLeavesTheAttributesQuiet() async throws {
        var steps = try MockScript.fixtures("handshake").steps
        steps += [.expect(.getLayerDetails, as: 90), .close]
        let (model, session, server) = try await openModel(MockScript(steps: steps))

        model.select(3)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 1
        }
        XCTAssertTrue(asked)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.state, .loading, "no failure is shown (C-CONN-07)")

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_reopeningAfterACancelAsksAgain() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake").steps
        steps += [.expect(.getLayerDetails, as: 70), .hold(gate), .expect(.cancel, as: 71)]
        steps += try MockScript.fixtures("layer-details").steps
        let (model, session, server) = try await openModel(MockScript(steps: steps))

        model.select(3)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 1
        }
        XCTAssertTrue(asked)
        model.setOpen(false)
        model.setOpen(true)
        await gate.open()

        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)
        XCTAssertEqual(model.requestsStarted, 2)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aFailureInANewRoundReplacesTheOldAttributes() async throws {
        var steps = try MockScript.fixtures("handshake", "layer-details").steps
        steps.append(.expect(.getLayerDetails, as: 90))  // never answered
        let (model, session, server) = try await openModel(
            MockScript(steps: steps), requestTimeout: .milliseconds(300))

        model.select(3)
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)

        model.select(3, newRound: try LayerTree(Fixtures.hierarchy()))
        XCTAssertEqual(model.state, .loaded(try Self.layerThree()), "shown until the new answer")
        let failed = await Wait.until { await model.state == .failed }
        XCTAssertTrue(failed, "the failure hides the old attributes")

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aSelectionGoneFromTheNewTreeAsksNothing() async throws {
        // A session without a connection: requests fail at once, and are still counted.
        let inspection = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        inspection.enter()
        let settled = await Wait.until { await !inspection.isLoading }
        XCTAssertTrue(settled)
        inspection.apply(try Fixtures.hierarchy())
        inspection.select(8)
        XCTAssertEqual(inspection.attributes.requestsStarted, 1)

        inspection.apply(try InspectionStoreTests.changed())  // without layer 8
        XCTAssertNil(inspection.selectedLayerID)
        XCTAssertEqual(inspection.attributes.state, .none)
        XCTAssertEqual(inspection.attributes.requestsStarted, 1)
    }

    // MARK: - C-ATTR-02, C-ATTR-03

    @MainActor
    func test_C_ATTR_02_aNilValueKeepsItsPlace() async throws {
        let (model, session, server) = try await openModel(
            try .fixtures("handshake", "layer-details"))
        model.select(3)
        let loaded = await Wait.until { await model.state == .loaded(try! Self.layerThree()) }
        XCTAssertTrue(loaded)

        guard case .loaded(let groups, _) = model.state else {
            XCTFail("not loaded")
            return
        }
        let attributes = groups.flatMap(\.attributes)
        let background = try XCTUnwrap(attributes.first { $0.id == "view.backgroundColor" })
        XCTAssertNil(background.value)
        // In the view group, after the layer's eight and the label's four (P-ATTR-11).
        XCTAssertEqual(attributes.map(\.title).firstIndex(of: "Background"), 15)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_03_attributesUnknownToTheClientArriveUnchanged() async throws {
        var steps = try MockScript.fixtures("handshake").steps
        steps += try MockScript.fixtures("layer-details").renamingAttributes().steps
        let (model, session, server) = try await openModel(MockScript(steps: steps))

        model.select(3)
        let expected = Fixtures.renamingAttributes(try Self.layerThree())
        let loaded = await Wait.until { await model.state == .loaded(expected) }
        XCTAssertTrue(loaded)
        let originals = Set(try Self.layerThree().flatMap { [$0.title] + $0.attributes.map(\.title) })
        let titles = expected.flatMap { [$0.title] + $0.attributes.map(\.title) }
        XCTAssertEqual(titles.count, 22)
        XCTAssertTrue(originals.isDisjoint(with: titles))

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Through the inspection

    // The state has constraints: `layer-details` has none
    // (C-LAYOUT-01).

    @MainActor
    func test_C_ATTR_01_selectingInTheInspectionAsksForTheAttributes() async throws {
        // Both GetLayerDetails get the same answer, so their order does not matter.
        let server = try await MockServer.start(script: try .fixtures(
            "handshake", "hierarchy", "layer-details", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        // Not about the wait for rows: the first batch goes at once.
        model.rowsWait = .zero

        model.enter()
        let tree = await Wait.until { await model.tree.count == 9 }
        XCTAssertTrue(tree)
        model.select(3)
        let loaded = await Wait.until {
            await model.attributes.state == .loaded(try! Self.layerThree(), constraints: [])
        }
        XCTAssertTrue(loaded)

        let requests = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.filter { $0.requests == [Self.attributesOnly(3)] }.count, 1)
        XCTAssertEqual(
            requests.filter { $0.requests.contains(where: \.wantAttributes) }.count, 1,
            "screenshots are asked for without attributes")

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aSelectionKeptFromBeforeIsAskedForOnceTheTreeArrives() async throws {
        let server = try await MockServer.start(script: try .fixtures(
            "handshake", "hierarchy", "layer-details", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        // Not about the wait for rows: the first batch goes at once.
        model.rowsWait = .zero
        model.apply(try Fixtures.hierarchy())
        model.select(3)
        XCTAssertEqual(model.attributes.requestsStarted, 0, "the inspection is closed")

        model.enter()
        let loaded = await Wait.until {
            await model.attributes.state == .loaded(try! Self.layerThree(), constraints: [])
        }
        XCTAssertTrue(loaded)
        // Not asked while the hierarchy was on its way: that request would have been
        // cancelled by the new round and asked again.
        XCTAssertEqual(model.attributes.requestsStarted, 1)
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello, .getHierarchy, .getLayerDetails, .getLayerDetails])

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_leavingTheInspectionCancelsTheAttributes() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += [.expect(.getLayerDetails, as: 70), .expect(.cancel, as: 71)]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)
        model.select(3)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 2
        }
        XCTAssertTrue(asked)

        model.leave()
        let cancelled = await Wait.until {
            await server.receivedFrames.contains { MessageKind($0.body) == .cancel }
        }
        XCTAssertTrue(cancelled)
        let frames = await server.receivedFrames
        let attributesRequest = try XCTUnwrap(
            frames.last { MessageKind($0.body) == .getLayerDetails })
        XCTAssertEqual(
            frames.last?.body, .cancel(Cancel(targetRequestID: attributesRequest.requestID)))
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_theAttributesFollowTheRowThatStandsIn() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(model.attributes.state, .none)

        model.select(7)
        XCTAssertEqual(model.attributes.selectedID, 7)
        model.setExpanded(6, false)
        XCTAssertEqual(model.selectedLayerID, 6)
        XCTAssertEqual(model.attributes.selectedID, 6)

        model.select(nil)
        XCTAssertEqual(model.attributes.selectedID, nil)
        XCTAssertEqual(model.attributes.state, .none)
    }

    @MainActor
    func test_C_ATTR_01_theAttributesComeWhenTheAppIsActiveAgain() async throws {
        // The screenshots are done; only the attributes meet an app that is not active.
        let server = try await MockServer.start(script: try .fixtures(
            "handshake", "hierarchy", "layer-details", "layer-details-failed", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)
        model.select(3)
        let paused = await Wait.until { await model.attributes.state == .appNotActive }
        XCTAssertTrue(paused)
        XCTAssertNil(model.notice, "the top bar has nothing to say")

        model.appStateDidChange(.active)
        let loaded = await Wait.until {
            await model.attributes.state == .loaded(try! Self.layerThree(), constraints: [])
        }
        XCTAssertTrue(loaded)
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds.filter { $0 == .getHierarchy }.count, 1, "the tree is not reloaded")

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_aReloadAsksForTheSelectedLayerAgain() async throws {
        var steps = try MockScript.fixtures(
            "handshake", "hierarchy", "layer-details", "layer-details").steps
        steps += [
            .expect(.getHierarchy, as: 60),
            .send(Frame(requestID: 60, body: .hierarchy(try Fixtures.hierarchy()))),
        ]
        // Renamed answers, so that the last wait tells the reload's answer from the first one.
        steps += try MockScript.fixtures("layer-details", "layer-details").renamingAttributes().steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        let expected = try Self.layerThree()

        model.enter()
        let tree = await Wait.until { await model.tree.count == 9 }
        XCTAssertTrue(tree)
        model.select(3)
        let loaded = await Wait.until {
            await model.attributes.state == .loaded(expected, constraints: [])
        }
        XCTAssertTrue(loaded)
        // The screenshots are settled too: a batch still under way would be cancelled by the
        // new round, and the script has no Cancel.
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)

        model.reload()
        XCTAssertEqual(
            model.attributes.state, .loaded(expected, constraints: []), "shown while the tree loads")
        let again = await Wait.until { await model.attributes.requestsStarted == 2 }
        XCTAssertTrue(again)
        let reloaded = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 4
        }
        XCTAssertTrue(reloaded)
        let renamed = Fixtures.renamingAttributes(expected)
        XCTAssertNotEqual(renamed, expected)
        let answered = await Wait.until {
            await model.attributes.state == .loaded(renamed, constraints: [])
        }
        XCTAssertTrue(answered)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_01_theInspectionRetriesTheSelectedLayersAttributes() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps.append(.expect(.getLayerDetails, as: 90))  // the attributes, never answered
        steps += try MockScript.fixtures("layer-details").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server, requestTimeout: .milliseconds(300))
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)
        model.select(3)
        let failed = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(failed)

        model.retryAttributes()
        let loaded = await Wait.until {
            await model.attributes.state == .loaded(try! Self.layerThree(), constraints: [])
        }
        XCTAssertTrue(loaded)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }
}
