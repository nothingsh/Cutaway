import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// What a refresh changed (C-LIVE-05): the layers that are new, those whose node changed, and
/// how many went. The first tree an inspection takes in marks nothing.
final class RefreshDiffTests: XCTestCase {
    /// The fixtures' app without a connection (`MockResponder.demo()`), whose hierarchy and
    /// screenshots the test changes between requests.
    private actor ChangingSource: InspectionSource {
        nonisolated var isLive: Bool { true }
        var negotiatedVersion: Version? { ProtocolVersion.current }
        private(set) var responder: MockResponder

        init() throws {
            responder = try MockResponder.demo()
        }

        func change(_ edit: @Sendable (inout MockResponder) -> Void) {
            edit(&responder)
        }

        func hierarchy() async throws -> Hierarchy {
            responder.hierarchy
        }

        func subtree(of rootID: UInt64) async throws -> Hierarchy {
            guard let subtree = responder.subtree(of: rootID) else { throw RequestError.layerNotFound(message: nil) }
            return subtree
        }

        func layerDetails(_ request: GetLayerDetails) async -> LayerDetailsStream {
            let (chunks, continuation) = AsyncThrowingStream.makeStream(of: [LayerDetail].self)
            continuation.yield(responder.answer(request))
            continuation.finish()
            return LayerDetailsStream(chunks: chunks, cancelAction: {})
        }

        func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult {
            throw RequestError.unsupported
        }
    }

    /// An inspection of `source`, entered, with its first tree in.
    @MainActor
    private func loaded(
        _ source: ChangingSource, start: InspectionStart = InspectionStart()
    ) async throws -> InspectionStore {
        let model = InspectionStore(source: source, newLayers: .expanded, start: start)
        model.enter()
        let loaded = await Wait.untilOnMain { model.loadState == .loaded && !model.loader.isLoading }
        XCTAssertTrue(loaded)
        return model
    }

    /// Refreshes the whole tree and waits until the loader is done with it.
    @MainActor
    private func refresh(_ model: InspectionStore) async {
        model.refresh()
        let done = await Wait.untilOnMain { !model.loader.isLoading && model.loader.hasNothingQueued }
        XCTAssertTrue(done)
    }

    /// The fixture's hierarchy with two layers added under the first root, one leaf removed,
    /// layer 3 moved and layer 4 hidden. Returns the leaf it removed.
    private static func changeEverything(_ responder: inout MockResponder) -> UInt64 {
        var nodes = responder.hierarchy.nodes
        let parents = Set(nodes.map(\.parentID))
        let leaf = nodes.last { !parents.contains($0.id) && $0.id != 3 && $0.id != 4 }!.id
        nodes.removeAll { $0.id == leaf }
        if let three = nodes.firstIndex(where: { $0.id == 3 }) {
            nodes[three].position?.x += 10
        }
        if let four = nodes.firstIndex(where: { $0.id == 4 }) {
            nodes[four].isHidden.toggle()
        }
        let root = nodes[0]
        for id: UInt64 in [100, 101] {
            var node = root
            node.id = id
            node.parentID = root.id
            node.memberReferences = []
            nodes.insert(node, at: 1)
        }
        responder.hierarchy = Hierarchy(nodes: nodes, keyWindowID: responder.hierarchy.keyWindowID)
        return leaf
    }

    @MainActor
    func test_C_LIVE_05_theFirstTreeMarksNothing() async throws {
        let model = try await loaded(ChangingSource())
        XCTAssertNil(model.refreshDiff)
    }

    @MainActor
    func test_C_LIVE_05_aRefreshMarksTheNewAndChangedLayersAndCountsThoseThatWent() async throws {
        let source = try ChangingSource()
        let model = try await loaded(source)
        await source.change { _ = Self.changeEverything(&$0) }
        await refresh(model)
        let diff = try XCTUnwrap(model.refreshDiff)
        XCTAssertEqual(diff.added, [100, 101])
        XCTAssertEqual(diff.changed, [3, 4])
        XCTAssertEqual(diff.removed, 1)
    }

    @MainActor
    func test_C_LIVE_05_aLayerWhoseScreenshotAloneChangedIsNotMarked() async throws {
        let source = try ChangingSource()
        let model = try await loaded(source)
        let revision = model.nextImageRevision
        await source.change { responder in
            // Layer 3's group takes layer 4's picture; the hierarchy stays as it was.
            let four = responder.details[4]?.solo
            responder.details[3]?.group = four
            responder.answersUnchanged = false
        }
        await refresh(model)
        let redrawn = await Wait.untilOnMain { model.nextImageRevision != revision }
        XCTAssertTrue(redrawn, "the new picture came")
        XCTAssertNil(model.refreshDiff)
    }

    @MainActor
    func test_C_LIVE_05_aSubtreeRefreshMarksOnlyWhatItTookAgain() async throws {
        let source = try ChangingSource()
        let model = try await loaded(source)
        XCTAssertTrue(model.canRefreshSubtrees)
        let tree = model.tree
        // Layer 3 and a layer outside its subtree both move; only layer 3's subtree is taken.
        let outside = try XCTUnwrap(tree.layers(within: nil).map(\.id).first {
            !tree.path(to: $0).contains(3) && !tree.path(to: 3).contains($0)
        })
        await source.change { responder in
            var nodes = responder.hierarchy.nodes
            for index in nodes.indices where [3, outside].contains(nodes[index].id) {
                nodes[index].position?.y += 5
            }
            responder.hierarchy = Hierarchy(nodes: nodes, keyWindowID: responder.hierarchy.keyWindowID)
        }
        model.refreshSubtree(of: 3)
        let done = await Wait.untilOnMain { model.refreshDiff != nil && !model.loader.isLoading }
        XCTAssertTrue(done)
        XCTAssertEqual(model.refreshDiff?.changed, [3])
        XCTAssertEqual(model.refreshDiff?.added, [])
        XCTAssertEqual(model.refreshDiff?.removed, 0)
    }

    @MainActor
    func test_C_LIVE_05_eachRefreshReplacesTheLastOnesMarks() async throws {
        let source = try ChangingSource()
        let model = try await loaded(source)
        await source.change { _ = Self.changeEverything(&$0) }
        await refresh(model)
        let first = try XCTUnwrap(model.refreshDiff)
        await source.change { responder in
            var nodes = responder.hierarchy.nodes
            if let index = nodes.firstIndex(where: { $0.id == 100 }) { nodes[index].opacity = 0.5 }
            responder.hierarchy = Hierarchy(nodes: nodes, keyWindowID: responder.hierarchy.keyWindowID)
        }
        await refresh(model)
        let second = try XCTUnwrap(model.refreshDiff)
        XCTAssertEqual(second.changed, [100])
        XCTAssertEqual(second.added, [])
        XCTAssertEqual(second.removed, 0)
        XCTAssertGreaterThan(second.generation, first.generation)

        // A refresh that changes nothing leaves nothing marked.
        await refresh(model)
        XCTAssertNil(model.refreshDiff)
    }

    @MainActor
    func test_C_LIVE_05_withTheSettingOffNothingIsMarked() async throws {
        let source = try ChangingSource()
        var start = InspectionStart()
        start.highlightsChanges = false
        let model = try await loaded(source, start: start)
        await source.change { _ = Self.changeEverything(&$0) }
        await refresh(model)
        XCTAssertNil(model.refreshDiff)

        // Turned on, the next refresh marks; turned off, the marks go at once.
        model.setHighlightsChanges(true)
        await source.change { responder in
            var nodes = responder.hierarchy.nodes
            nodes[1].opacity = 0.25
            responder.hierarchy = Hierarchy(nodes: nodes, keyWindowID: responder.hierarchy.keyWindowID)
        }
        await refresh(model)
        XCTAssertNotNil(model.refreshDiff)
        model.setHighlightsChanges(false)
        XCTAssertNil(model.refreshDiff)
    }
}
