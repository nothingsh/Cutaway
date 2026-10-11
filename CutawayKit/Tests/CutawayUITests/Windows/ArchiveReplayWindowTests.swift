import AppKit
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// An inspection window over a replayed archive shows what it shows over the fixtures it was
/// saved from (C-MOCK-04).
final class ArchiveReplayWindowTests: XCTestCase {
    /// What an inspection window shows, as far as this test compares it.
    private struct Shown: Equatable {
        var rows: Int
        var ids: [UInt64]
        var three: EncodedImage?
        var four: EncodedImage?
        var attributes: [AttributeGroup]
    }

    @MainActor
    private func shown(over script: MockScript) async throws -> Shown {
        let server = try await MockServer.start(script: script)
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        let inspector = InspectorWindowController(
            location: .simulator(port: server.port), entry: nil, store: model)
        model.enter()
        let loaded = await Wait.until(within: .seconds(5)) {
            await MainActor.run { model.images[3] != nil && model.images[4] != nil }
        }
        XCTAssertTrue(loaded)
        model.select(3)
        let attributes = await Wait.until(within: .seconds(5)) {
            await MainActor.run {
                if case .loaded = model.attributes.state { true } else { false }
            }
        }
        XCTAssertTrue(attributes)
        let outline = inspector.splitController.hierarchyController.outlineView
        var groups: [AttributeGroup] = []
        if case .loaded(let loadedGroups, _) = model.attributes.state { groups = loadedGroups }
        let result = Shown(
            rows: outline.numberOfRows, ids: model.tree.ids, three: model.images[3]?.group?.image,
            four: model.images[4]?.solo?.image, attributes: groups)
        model.leave()
        inspector.close()
        await session.close()
        await server.stop()
        return result
    }

    @MainActor
    func test_C_MOCK_04_aReplayedArchiveShowsWhatTheFixturesShow() async throws {
        let direct = try await shown(over: MockScript(
            steps: try MockScript.fixtures("handshake").steps + [.respond(try MockResponder.demo())]))
        let replayed = try await shown(over: try MockScript.replaying(archive: Fixtures.archive()))

        XCTAssertEqual(replayed, direct)
        XCTAssertEqual(replayed.rows, 9)
        XCTAssertEqual(replayed.ids.count, 9)
        XCTAssertNotNil(replayed.three)
        XCTAssertNotNil(replayed.four)
        XCTAssertEqual(replayed.attributes.flatMap(\.attributes).count, 12)
    }
}
