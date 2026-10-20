import Combine
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// The state of one app's inspection: C-HIER-01 and C-HIER-02, and how a failed request
/// for the hierarchy is reported.
final class InspectionStoreTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    /// A model whose session has no connection behind it. `apply(_:)` feeds it.
    /// Every layer starts expanded, as these tests lay the fixture out (C-HIER-09 has its own).
    @MainActor
    private func model() -> InspectionStore {
        InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
    }

    /// A session that has shaken hands with `server`.
    private func session(
        to server: MockServer, requestTimeout: Duration = .seconds(10)
    ) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, requestTimeout: requestTimeout)
        _ = try await session.handshake()
        return session
    }

    /// The fixture without layer 8 and with a new layer 20 under layer 2.
    private func changedHierarchy() throws -> Hierarchy {
        try Self.changed()
    }

    static func changed() throws -> Hierarchy {
        var hierarchy = try Fixtures.hierarchy()
        hierarchy.nodes.removeAll { $0.id == 8 }
        hierarchy.nodes.append(LayerTreeTests.node(20, parent: 2))
        return hierarchy
    }

    // MARK: - C-HIER-01: loading

    func test_C_HIER_01_theHierarchyArrivesOverTheConnection() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "hierarchy"))
        let session = try await session(to: server)
        let model = await InspectionStore(session: session, newLayers: .expanded)

        let before = await (model.loadState, model.tree)
        XCTAssertEqual(before.0, .loading)
        XCTAssertEqual(before.1, .empty)

        await model.reload()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)

        let tree = await model.tree
        XCTAssertEqual(tree, try LayerTree(try Fixtures.hierarchy()))
        XCTAssertEqual(tree.ids, [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_HIER_01_aHierarchyThatBreaksTheProtocolIsRefusedAndTheOldTreeStays() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.setExpanded(4, false)

        var broken = try Fixtures.hierarchy()
        broken.nodes.append(LayerTreeTests.node(3, parent: 2))
        model.apply(broken)

        XCTAssertEqual(
            model.loadState, .failed(.invalidHierarchy("the ID 3 appears more than once")))
        XCTAssertEqual(model.tree.count, 14)
        XCTAssertFalse(model.isExpanded(4))

        // The next good hierarchy is taken as usual.
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertFalse(model.isExpanded(4))
    }

    func test_C_CONN_08_anAppThatIsNotActiveIsReportedAsSuch() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-not-active"))
        let session = try await session(to: server)
        let model = await InspectionStore(session: session, newLayers: .expanded)

        await model.reload()
        let failed = await Wait.until { await model.loadState == .failed(.appNotActive) }
        XCTAssertTrue(failed)
        let tree = await model.tree
        XCTAssertEqual(tree, .empty)

        await session.close()
        await server.stop()
    }

    func test_C_HIER_01_aRequestThatGetsNoAnswerIsReportedAsFailed() async throws {
        // The server shakes hands and then says nothing more.
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let session = try await session(to: server, requestTimeout: .milliseconds(200))
        let model = await InspectionStore(session: session, newLayers: .expanded)

        await model.reload()
        let failed = await Wait.until { await model.loadState == .failed(.other) }
        XCTAssertTrue(failed)

        await session.close()
        await server.stop()
    }

    func test_C_HIER_01_reloadingAfterAFailureShowsLoadingAndThenTheTree() async throws {
        // Not active at first; the second request is answered, 200 ms late.
        var steps = try MockScript.fixtures("handshake", "app-not-active").steps
        steps += [
            .expect(.getHierarchy, as: 50),
            .pause(.milliseconds(200)),
            .send(Frame(requestID: 50, body: .hierarchy(try Fixtures.hierarchy()))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await session(to: server)
        let model = await InspectionStore(session: session, newLayers: .expanded)

        await model.reload()
        let failed = await Wait.until { await model.loadState == .failed(.appNotActive) }
        XCTAssertTrue(failed)

        let stateAfterAsking = await MainActor.run {
            model.reload()
            return model.loadState
        }
        XCTAssertEqual(stateAfterAsking, .loading)
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        let count = await model.tree.count
        XCTAssertEqual(count, 14)

        await session.close()
        await server.stop()
    }

    func test_C_CONN_07_aLostConnectionLeavesTheStateAlone() async throws {
        // The connection ends while the hierarchy is on its way. The app is about to leave
        // the list, and the inspection with it: no failure is shown.
        var steps = try MockScript.fixtures("handshake").steps
        steps += [.expect(.getHierarchy, as: 2), .close]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await session(to: server)
        let model = await InspectionStore(session: session, newLayers: .expanded)

        await model.reload()
        let settled = await Wait.until { await !model.isLoading }
        XCTAssertTrue(settled, "the request never ended")
        let state = await model.loadState
        XCTAssertEqual(state, .loading)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await server.stop()
    }

    // MARK: - C-HIER-02: expansion and selection

    @MainActor
    func test_C_HIER_02_theTreeOpensByTheRuleAndNothingIsSelected() throws {
        let model = InspectionStore(session: Session(channel: InertChannel(), client: Self.client))
        model.apply(try Fixtures.hierarchy())

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.tree.ids.filter { !model.isExpanded($0) }, [4, 10, 6, 13])
        XCTAssertNil(model.selectedLayerID)
    }

    /// The attributes are about the layer the inspection selects, however the selection
    /// moved: by a click, onto a collapsed node, or off a layer a new tree no longer has.
    @MainActor
    func test_C_ATTR_01_theAttributesFollowEveryMoveOfTheSelection() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.select(5)
        XCTAssertEqual(model.attributes.selectedID, 5)
        model.setExpanded(4, false)
        XCTAssertEqual(model.selectedLayerID, 4, "moved onto the collapsed node")
        XCTAssertEqual(model.attributes.selectedID, 4)
        model.select(8)
        model.apply(try changedHierarchy())  // without layer 8
        XCTAssertNil(model.selectedLayerID)
        XCTAssertNil(model.attributes.selectedID)
    }

    @MainActor
    func test_C_HIER_02_layersThatAreNotInTheTreeAreIgnored() throws {
        let model = model()
        // Before any tree.
        model.setExpanded(1, true)
        model.select(1)
        XCTAssertFalse(model.isExpanded(1))
        XCTAssertNil(model.selectedLayerID)

        model.apply(try Fixtures.hierarchy())
        model.select(7)
        model.setExpanded(99, true)
        model.select(99)
        XCTAssertFalse(model.isExpanded(99))
        XCTAssertEqual(model.selectedLayerID, 7, "selecting an unknown layer changed the selection")
    }

    @MainActor
    func test_C_HIER_02_collapsingANodeMovesASelectionInsideItOntoIt() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())

        // Directly inside.
        model.select(5)
        model.setExpanded(4, false)
        XCTAssertEqual(model.selectedLayerID, 4)

        // Deeper inside.
        model.select(7)
        model.setExpanded(2, false)
        XCTAssertEqual(model.selectedLayerID, 2)

        // A selection elsewhere stays.
        model.setExpanded(2, true)
        model.select(3)
        model.setExpanded(6, false)
        XCTAssertEqual(model.selectedLayerID, 3)

        // Collapsing the selected node itself keeps it selected.
        model.select(6)
        model.setExpanded(6, true)
        model.setExpanded(6, false)
        XCTAssertEqual(model.selectedLayerID, 6)
    }

    /// Collapsing a row in the list collapses every expanded row inside it too; the model
    /// used to lay the tree out again for each.
    @MainActor
    func test_C_HIER_02_collapsingSeveralNodesAtOnceLaysTheTreeOutOnce() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.select(5)
        let builds = model.geometryBuildCount
        let revision = model.expansionRevision

        model.setExpanded([4, 6, 2, 99], false)

        XCTAssertEqual([2, 4, 6].filter(model.isExpanded), [])
        XCTAssertTrue(model.isExpanded(1))
        XCTAssertEqual(model.geometryBuildCount, builds + 1)
        XCTAssertEqual(model.expansionRevision, revision + 1)
        XCTAssertEqual(model.selectedLayerID, 2, "the outermost collapsed node stands in")

        // Nothing changes: nothing is laid out.
        model.setExpanded([4, 99], false)
        XCTAssertEqual(model.geometryBuildCount, builds + 1)
        XCTAssertEqual(model.expansionRevision, revision + 1)
    }

    @MainActor
    func test_C_HIER_02_selectingALayerInsideACollapsedNodeSelectsThatNode() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.setExpanded(4, false)
        model.setExpanded(2, false)

        // The outermost collapsed node stands in for everything inside it.
        model.select(5)
        XCTAssertEqual(model.selectedLayerID, 2)
    }

    // MARK: - C-HIER-02: reloading

    @MainActor
    func test_C_HIER_02_reloadingKeepsTheStateOfLayersThatAreStillThere() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.setExpanded(4, false)
        model.setExpanded(8, false)
        model.select(7)

        model.apply(try changedHierarchy())

        XCTAssertEqual(model.tree.ids, [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 9, 13, 14, 20])
        XCTAssertFalse(model.isExpanded(4), "layer 4 was collapsed and is still there")
        XCTAssertTrue(model.isExpanded(6))
        XCTAssertEqual(model.selectedLayerID, 7)
        // A new layer takes the default.
        XCTAssertTrue(model.isExpanded(20))
        // A layer that is gone has no state…
        XCTAssertFalse(model.isExpanded(8))

        // …and none comes back with it: layer 8 was collapsed before it went away.
        model.apply(try Fixtures.hierarchy())
        XCTAssertTrue(model.isExpanded(8))
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertEqual(model.selectedLayerID, 7)
    }

    @MainActor
    func test_C_HIER_02_aSelectedLayerThatMovedIntoACollapsedNodeHandsTheSelectionOver() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.setExpanded(4, false)
        model.select(3)

        // Layer 3 is now inside layer 4.
        var moved = try Fixtures.hierarchy()
        var three = try XCTUnwrap(moved.nodes.first { $0.id == 3 })
        three.parentID = 4
        moved.nodes.removeAll { $0.id == 3 }
        let afterFour = try XCTUnwrap(moved.nodes.firstIndex { $0.id == 4 }) + 1
        moved.nodes.insert(three, at: afterFour)
        model.apply(moved)

        XCTAssertEqual(model.tree.children(of: 4), [3, 10, 12, 5])
        XCTAssertEqual(model.selectedLayerID, 4)
    }

    @MainActor
    func test_C_HIER_02_theNewStateIsInPlaceWhenTheTreeIsPublished() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.setExpanded(4, false)
        model.select(8)

        // What a subscriber sees at the moment the new tree is published.
        var seen: [(ids: [UInt64], four: Bool, twenty: Bool, selected: UInt64?)] = []
        let subscription = model.$tree.dropFirst().sink { tree in
            seen.append((tree.ids, model.isExpanded(4), model.isExpanded(20), model.selectedLayerID))
        }
        model.apply(try changedHierarchy())
        subscription.cancel()

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.ids, [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 9, 13, 14, 20])
        XCTAssertEqual(seen.first?.four, false)
        XCTAssertEqual(seen.first?.twenty, true)
        XCTAssertNil(seen.first?.selected, "layer 8 is gone, and the selection with it")
    }

    func test_C_DET_02_aReloadAskedForDuringOneIsMadeAfterIt() async throws {
        // The second request is answered 200 ms late with a changed tree; a third one is
        // expected after it, answered with a tree that has a layer 21.
        var third = try Fixtures.hierarchy()
        third.nodes.append(LayerTreeTests.node(21, parent: 2))
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getHierarchy, as: 50),
            .pause(.milliseconds(200)),
            .send(Frame(requestID: 50, body: .hierarchy(try changedHierarchy()))),
            .expect(.getHierarchy, as: 51),
            .send(Frame(requestID: 51, body: .hierarchy(third))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await session(to: server)
        let model = await InspectionStore(session: session, newLayers: .expanded)
        await model.reload()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)

        // Three in a row while one is under way: one more after it. Meanwhile the tree that
        // is there stays shown.
        let stateAfterAsking = await MainActor.run {
            model.reload()
            model.reload()
            model.reload()
            return (model.loadState, model.tree.count)
        }
        XCTAssertEqual(stateAfterAsking.0, .loaded)
        XCTAssertEqual(stateAfterAsking.1, 14)

        let reloaded = await Wait.until { await model.tree.contains(21) }
        XCTAssertTrue(reloaded)
        try await Task.sleep(for: .milliseconds(200))
        // Hello and three GetHierarchy: the first, the one asked for, the one queued.
        let frames = await server.receivedFrames
        XCTAssertEqual(frames.count, 4)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Images, hover, preview mode

    /// A model holding the `hierarchy` fixture.
    @MainActor
    private func loadedModel() throws -> InspectionStore {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        return model
    }

    @MainActor
    func test_C_SCENE_03_detailsGiveTheLayersTheirImages() async throws {
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))

        let label = try XCTUnwrap(model.images[3])
        XCTAssertNil(label.solo)
        XCTAssertEqual(label.group?.image.pixelWidth, 200)
        let card = try XCTUnwrap(model.images[4])
        XCTAssertEqual(card.solo?.image.pixelWidth, 300)
        XCTAssertEqual(card.group?.image.pixelWidth, 300)
        let revisions = [label.group?.revision, card.solo?.revision, card.group?.revision]
        XCTAssertEqual(Set(revisions).count, 3, "every image has a revision of its own")
        XCTAssertEqual(Set(model.images.keys), [3, 4])
    }

    @MainActor
    func test_C_SCENE_03_detailsForLayersNotInTheTreeAreSkipped() async throws {
        let model = try loadedModel()
        // layer-details has layer 99, which is not in the tree and is LayerNotFound anyway;
        // here a layer 77 that the tree does not know arrives with an image.
        var details = try Fixtures.layerDetails(scenario: "layer-details")
        details[0].layerID = 77
        await model.applyDetails(details)
        XCTAssertNil(model.images[77])
        XCTAssertEqual(Set(model.images.keys), [4])
    }

    @MainActor
    func test_C_SCENE_03_aLayerWhoseDetailFailedHasNoImage() async throws {
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details-edge"))
        XCTAssertNotNil(model.images[8])
        XCTAssertNil(model.images[9], "CaptureFailed")
        XCTAssertNil(model.images[7], "asked for nothing")

        // A later failure takes away the image a layer had.
        var failed = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details-edge").first { $0.layerID == 8 })
        failed.status = .captureFailed
        failed.group = nil
        await model.applyDetails([failed])
        XCTAssertNil(model.images[8])
    }

    @MainActor
    func test_C_SCENE_03_newImagesForALayerGetANewRevision() async throws {
        let model = try loadedModel()
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        await model.applyDetails(details)
        let first = try XCTUnwrap(model.images[3]?.group?.revision)
        await model.applyDetails(details)
        XCTAssertNotEqual(try XCTUnwrap(model.images[3]?.group?.revision), first)
    }

    @MainActor
    func test_C_REND_04_noDetailsPublishNothing() async throws {
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        var published = 0
        let subscription = model.imagesChanged.sink { _ in published += 1 }
        await model.applyDetails([])
        await model.applyDetails([LayerDetail(
            layerID: 99, status: .layerNotFound, solo: nil, group: nil, attributeGroups: [])])
        XCTAssertEqual(published, 0)
        subscription.cancel()
    }

    @MainActor
    func test_C_SCALE_02_aChangeOfImagesNamesOnlyTheLayersItChanged() async throws {
        let model = try loadedModel()
        var changes: [[UInt64]] = []
        let subscription = model.imagesChanged.sink { changes.append($0) }
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        XCTAssertEqual(changes.map(Set.init), [Set(model.images.keys)])

        // Reloading without layer 8 drops its images, and names only it.
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details-edge"))
        XCTAssertNotNil(model.images[8])
        changes.removeAll()
        model.apply(try changedHierarchy())  // without layer 8
        XCTAssertEqual(changes, [[8]])
        subscription.cancel()
    }

    @MainActor
    func test_C_SCENE_03_reloadingDropsTheImagesOfLayersThatAreGone() async throws {
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details-edge"))
        XCTAssertNotNil(model.images[8])
        model.apply(try changedHierarchy())  // without layer 8
        XCTAssertNil(model.images[8])
        XCTAssertNotNil(model.images[3])
    }

    @MainActor
    func test_C_SCENE_03_expandingAndCollapsingIsPublished() throws {
        let model = try loadedModel()
        var revisions: [UInt64] = []
        let subscription = model.$expansionRevision.dropFirst().sink { revisions.append($0) }
        model.setExpanded(4, false)
        model.setExpanded(4, false)  // no change
        model.setExpanded(4, true)
        model.setExpanded(42, false)  // not in the tree
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(model.expandedLayerIDs, Set(1...14))
        model.setExpanded(6, false)
        XCTAssertEqual(model.expandedLayerIDs, Set(1...14).subtracting([6]))
        subscription.cancel()
    }

    @MainActor
    func test_C_PREV_03_hoverIsRecordedForLayersOfTheTree() throws {
        let model = try loadedModel()
        XCTAssertNil(model.hoveredLayerID)
        model.hover(3)
        XCTAssertEqual(model.hoveredLayerID, 3)
        model.hover(42)
        XCTAssertEqual(model.hoveredLayerID, 3, "a layer not in the tree is ignored")
        model.hover(nil)
        XCTAssertNil(model.hoveredLayerID)

        model.hover(8)
        model.apply(try changedHierarchy())  // without layer 8
        XCTAssertNil(model.hoveredLayerID)
    }

    @MainActor
    func test_C_PREV_02_thePreviewStartsIn2DAndSwitches() throws {
        let model = try loadedModel()
        XCTAssertEqual(model.previewMode, .twoD)
        var published = 0
        let subscription = model.$previewMode.dropFirst().sink { _ in published += 1 }
        model.setPreviewMode(.threeD)
        model.setPreviewMode(.threeD)
        XCTAssertEqual(model.previewMode, .threeD)
        XCTAssertEqual(published, 1)
        subscription.cancel()
    }

    @MainActor
    func test_C_SCENE_03_theSceneGetsATextureKeyForEachImage() async throws {
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        let layers = model.tree.sceneLayers(images: model.images)
        let card = try XCTUnwrap(layers.first { $0.id == 4 })
        let images = try XCTUnwrap(model.images[4])
        XCTAssertEqual(
            card.solo,
            TextureKey(layerID: 4, kind: .solo, revision: try XCTUnwrap(images.solo?.revision)))
        XCTAssertEqual(
            card.group,
            TextureKey(layerID: 4, kind: .group, revision: try XCTUnwrap(images.group?.revision)))
        let label = try XCTUnwrap(layers.first { $0.id == 3 })
        XCTAssertNil(label.solo)
        XCTAssertNotNil(label.group)
        XCTAssertNil(layers.first { $0.id == 2 }?.group)
    }

    @MainActor
    func test_C_SCENE_03_anImageOfOneKindLeavesTheOtherKind() async throws {
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        let before = try XCTUnwrap(model.images[4])

        var groupOnly = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 4 })
        groupOnly.solo = nil
        await model.applyDetails([groupOnly])

        let after = try XCTUnwrap(model.images[4])
        XCTAssertEqual(after.solo?.revision, before.solo?.revision, "the solo stays")
        XCTAssertNotEqual(after.group?.revision, before.group?.revision, "the group is new")
    }

    @MainActor
    func test_C_SCENE_03_aDetailWithoutImagesLeavesTheImagesThere() async throws {
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        let before = model.images[3]
        await model.applyDetails([LayerDetail(
            layerID: 3, status: .ok, solo: nil, group: nil, attributeGroups: [])])
        XCTAssertEqual(model.images[3], before)
    }

    func test_C_REND_04_imagesAreComparedByRevisionNotByData() {
        // Two images of the same revision are equal whatever their data: comparing images
        // never reads it, so comparing large screenshots costs nothing.
        let red = EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: 1, pixelHeight: 1, bytesPerRow: 4,
            scale: 1, data: Data([0, 0, 255, 255]))
        var green = red
        green.data = Data([0, 255, 0, 255])
        XCTAssertEqual(
            RevisionedImage(revision: 7, image: red), RevisionedImage(revision: 7, image: green))
        XCTAssertNotEqual(
            RevisionedImage(revision: 7, image: red), RevisionedImage(revision: 8, image: red))
    }

    // MARK: - The layout

    @MainActor
    func test_C_REND_04_imagesSwapTexturesWithoutLayingTheTreeOutAgain() async throws {
        let model = try loadedModel()
        let built = model.geometryBuildCount
        XCTAssertTrue(model.layout.isDisplayed(3))
        XCTAssertNil(model.layout.texture(of: 3))

        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        XCTAssertEqual(model.geometryBuildCount, built, "only the textures changed")
        let revision = try XCTUnwrap(model.images[3]?.group?.revision)
        XCTAssertEqual(
            model.layout.texture(of: 3), TextureKey(layerID: 3, kind: .group, revision: revision))

        model.setExpanded(4, false)
        XCTAssertEqual(model.geometryBuildCount, built + 1)
        XCTAssertFalse(model.layout.isDisplayed(5))
    }

    @MainActor
    func test_C_REND_04_theLayoutIsPublishedAfterWhatItIsBuiltFrom() async throws {
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        var seen: [(imagesHaveFour: Bool, fourExpanded: Bool, fourShown: Bool)] = []
        let subscription = model.$layout.dropFirst().sink { layout in
            seen.append((model.images[4] != nil, model.isExpanded(4), layout.isDisplayed(5)))
        }
        model.setExpanded(4, false)
        subscription.cancel()
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.imagesHaveFour, true)
        XCTAssertEqual(seen.first?.fourExpanded, false)
        XCTAssertEqual(seen.first?.fourShown, false)
    }

    @MainActor
    func test_C_HIER_02_anUnchangedTreeIsNotPublishedAgain() throws {
        let model = model()
        var published = 0
        let subscription = model.$tree.sink { _ in published += 1 }

        model.apply(try Fixtures.hierarchy())
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(published, 2, "the empty tree, then the fixture once")
        XCTAssertEqual(model.geometryBuildCount, 1)

        model.apply(try changedHierarchy())
        XCTAssertEqual(published, 3)
        XCTAssertEqual(model.geometryBuildCount, 2)
        subscription.cancel()
    }

    @MainActor
    func test_C_HIER_02_anUnchangedTreeStillStartsANewRound() async throws {
        let model = model()
        model.enter()
        // The request for the hierarchy fails at once on this session; then the attributes
        // know no hierarchy is on its way.
        let settled = await Wait.until { await !model.isLoading }
        XCTAssertTrue(settled)
        model.apply(try Fixtures.hierarchy())
        model.select(3)
        let asked = model.attributes.requestsStarted

        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(model.attributes.requestsStarted, asked + 1, "the selection is asked for again")
    }

    @MainActor
    func test_C_SCENE_03_aLayerThatLostItsSublayersShowsItsNewGroup() async throws {
        // Layer 4 had a solo and a group; reloaded without its sublayer 5 and its virtual
        // nodes 10 to 12, it is a leaf that asks for its group only. The new group is drawn,
        // not the old solo.
        let model = try loadedModel()
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        var withoutFive = try Fixtures.hierarchy()
        withoutFive.nodes.removeAll { [5, 10, 11, 12].contains($0.id) }
        model.apply(withoutFive)

        var groupOnly = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 4 })
        groupOnly.solo = nil
        await model.applyDetails([groupOnly])
        let group = try XCTUnwrap(model.images[4]?.group?.revision)
        XCTAssertEqual(
            model.layout.texture(of: 4), TextureKey(layerID: 4, kind: .group, revision: group))
    }
}
