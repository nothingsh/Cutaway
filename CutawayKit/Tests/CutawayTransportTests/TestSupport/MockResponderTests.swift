import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// What a responder answers for a synthetic scene: chunks, subtrees, edits (C-MOCK-03).
final class MockResponderTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func everything(_ ids: [UInt64]) -> GetLayerDetails {
        GetLayerDetails(
            requests: ids.map {
                LayerDetailRequest(
                    layerID: $0, wantSolo: true, wantGroup: true, wantAttributes: true,
                    wantConstraints: true)
            },
            maxTextureDimension: 4096)
    }

    private func connect(
        _ responder: MockResponder, records: Bool = true
    ) async throws -> (MockServer, Session) {
        let server = try await MockServer.start(
            script: MockScript(
                steps: try MockScript.fixtures("handshake").steps + [.respond(responder)]),
            records: records)
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, requestTimeout: .seconds(10))
        _ = try await session.handshake()
        return (server, session)
    }

    func test_C_MOCK_03_aResponderSplitsChunksAtSixteenMebibytes() async throws {
        // 1024 × 1024 images: 4 MiB each, two to a layer, so two layers fill a chunk.
        let scene = SyntheticScene(
            layerCount: 5, shape: .deep, imagePixels: .fixed(width: 1024, height: 1024))
        let responder = scene.responder()
        let ids = scene.hierarchy().nodes.map(\.id)
        let chunks = responder.answerChunks(Self.everything(ids))
        XCTAssertEqual(chunks.map { $0.map(\.layerID) }, [[1, 2], [3, 4], [5]])

        // A layer larger than the limit by itself has a chunk of its own.
        let big = SyntheticScene(
            layerCount: 2, shape: .deep, imagePixels: .fixed(width: 2048, height: 2048))
        XCTAssertEqual(
            big.responder().answerChunks(Self.everything([1, 2])).map { $0.map(\.layerID) },
            [[1], [2]])

        // Over a connection: the chunks arrive in order, and the end counts them.
        let (server, session) = try await connect(responder)
        var arrived: [[UInt64]] = []
        for try await chunk in await session.layerDetails(Self.everything(ids)).chunks {
            arrived.append(chunk.map(\.layerID))
        }
        XCTAssertEqual(arrived, [[1, 2], [3, 4], [5]])
        let ends = await server.sentPayloads.compactMap { payload -> StreamEnd? in
            guard case .streamEnd(let end) = try? FrameCodec.decode(payload).body else { return nil }
            return end
        }
        XCTAssertEqual(ends.map(\.chunkCount), [3])
        await session.close()
        await server.stop()
    }

    func test_C_MOCK_03_aResponderAnswersSubtreesAndEdits() async throws {
        let scene = SyntheticScene(
            layerCount: 200, shape: .app(AppShape()), attributes: true, constraints: true)
        let (server, session) = try await connect(scene.responder())

        // The first cell: its content view, four subviews, two text layers and a separator.
        let hierarchy = scene.hierarchy()
        let cell = try XCTUnwrap(hierarchy.nodes.first { $0.viewClassName == "UITableViewCell" })
        let subtree = try await session.subtree(of: cell.id)
        XCTAssertEqual(subtree.nodes.count, 9)
        XCTAssertEqual(subtree.nodes.first, cell)

        let result = try await session.setAttribute(
            SetAttribute(layerID: cell.id, attributeID: "layer.opacity", value: .double(0.5)))
        let opacity = result.attributeGroups.flatMap(\.attributes).first { $0.id == "layer.opacity" }
        XCTAssertEqual(opacity?.value, .double(0.5))
        // The hierarchy follows, for the rest of the connection.
        let after = try await session.hierarchy()
        XCTAssertEqual(after.nodes.first { $0.id == cell.id }?.opacity, 0.5)
        let details = try await Self.details(of: cell.id, session)
        XCTAssertEqual(
            details?.attributeGroups.flatMap(\.attributes).first { $0.id == "layer.opacity" }?.value,
            .double(0.5))

        // Not editable, of another kind, nil where nil is not taken, unknown (P-SET-03 counts
        // it as not editable), on a layer that is not there.
        for (request, code) in [
            (SetAttribute(layerID: cell.id, attributeID: "layer.frame", value: .rect(.zero)),
             RequestError.attributeNotEditable(message: nil)),
            (SetAttribute(layerID: cell.id, attributeID: "layer.opacity", value: .bool(true)),
             .invalidAttributeValue(message: nil)),
            (SetAttribute(layerID: cell.id, attributeID: "layer.opacity", value: nil),
             .invalidAttributeValue(message: nil)),
            (SetAttribute(layerID: cell.id, attributeID: "no.such", value: .double(1)),
             .attributeNotEditable(message: nil)),
            (SetAttribute(layerID: 99_999, attributeID: "layer.opacity", value: .double(1)),
             .layerNotFound(message: nil)),
        ] {
            do {
                _ = try await session.setAttribute(request)
                XCTFail("\(request) was applied")
            } catch {
                XCTAssertEqual(error as? RequestError, code, "\(request)")
            }
        }
        await session.close()
        await server.stop()

        // A responder that refuses, as `demo()` does.
        var refusing = scene.responder()
        refusing.editing = .refuse
        let (other, otherSession) = try await connect(refusing)
        do {
            _ = try await otherSession.setAttribute(
                SetAttribute(layerID: cell.id, attributeID: "layer.opacity", value: .double(0.5)))
            XCTFail("the edit was applied")
        } catch {
            XCTAssertEqual(error as? RequestError, .attributeNotEditable(message: nil))
        }
        await otherSession.close()
        await other.stop()
    }

    func test_C_MOCK_03_aServerThatDoesNotRecordKeepsNoFrames() async throws {
        let scene = SyntheticScene(
            layerCount: 100, shape: .app(AppShape()), imagePixels: .fixed(width: 32, height: 32))
        let (server, session) = try await connect(scene.responder(), records: false)
        _ = try await session.hierarchy()
        _ = try await Self.details(of: 1, session)
        let received = await server.receivedFrames
        let sent = await server.sentPayloads
        let count = await server.receivedFrameCount
        let written = await server.writtenByteCount
        XCTAssertEqual(received, [])
        XCTAssertEqual(sent, [])
        XCTAssertEqual(count, 3, "Hello, GetHierarchy, GetLayerDetails")
        XCTAssertGreaterThan(written, 0)
        await session.close()
        await server.stop()
    }

    private static func details(of id: UInt64, _ session: Session) async throws -> LayerDetail? {
        var found: LayerDetail?
        for try await chunk in await session.layerDetails(everything([id])).chunks {
            found = chunk.first { $0.layerID == id } ?? found
        }
        return found
    }
}
