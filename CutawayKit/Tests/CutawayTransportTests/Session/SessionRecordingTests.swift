import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-ARCH-01: requests that hand over the bytes of their responses as received, so that an
/// archive can keep the protocol's messages unchanged (Resources/ARCHIVE.md).
final class SessionRecordingTests: XCTestCase {
    private func request(_ scenario: String) throws -> GetLayerDetails {
        guard case .getLayerDetails(let request) =
            try Harness.fixture(scenario, "01-c2s-get-layer-details.bin").body
        else { throw RequestError.protocolViolation("the fixture is not a GetLayerDetails") }
        return request
    }

    private func collect(
        _ stream: RecordedLayerDetailsStream, afterEachChunk: (Int) async -> Void = { _ in }
    ) async -> (chunks: [Recorded<[LayerDetail]>], error: (any Error)?) {
        var chunks: [Recorded<[LayerDetail]>] = []
        do {
            for try await chunk in stream.chunks {
                chunks.append(chunk)
                await afterEachChunk(chunks.count)
            }
            return (chunks, nil)
        } catch {
            return (chunks, error)
        }
    }

    func test_C_ARCH_01_recordedRequestsHandOverTheBytesAsReceived() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-icon", "hierarchy", "layer-details"))
        let session = try await Harness.readySession(for: server)

        let icon = try await session.recordedAppIcon()
        let hierarchy = try await session.recordedHierarchy()
        let result = await collect(await session.recordedLayerDetails(try request("layer-details")))
        XCTAssertNil(result.error)

        // Hello, AppStateChanged, AppIcon, Hierarchy, two chunks, StreamEnd.
        let sent = await server.sentPayloads
        XCTAssertEqual(sent.count, 7)
        let hello = await session.serverHelloPayload
        XCTAssertEqual(hello, sent[0])
        XCTAssertEqual(icon.payload, sent[2])
        XCTAssertEqual(hierarchy.payload, sent[3])
        XCTAssertEqual(result.chunks.map(\.payload), [sent[4], sent[5]])

        // The values are what the plain requests give.
        guard case .appIcon(let expectedIcon) = try Harness.fixture(
            "app-icon", "02-s2c-app-icon.bin").body
        else {
            XCTFail("the fixture is not an AppIcon")
            return
        }
        XCTAssertEqual(icon.value, expectedIcon.image)
        XCTAssertEqual(hierarchy.value, try Fixtures.hierarchy())
        XCTAssertEqual(
            result.chunks.flatMap(\.value), try Fixtures.layerDetails(scenario: "layer-details"))

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_01_aRecordedStreamCancelsLikeAnyOther() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "layer-details-cancelled"))
        let session = try await Harness.readySession(for: server)

        let stream = await session.recordedLayerDetails(try request("layer-details-cancelled"))
        let result = await collect(stream) { count in
            if count == 1 { await stream.cancel() }
        }
        XCTAssertEqual(result.chunks.map { $0.value.map(\.layerID) }, [[2]])
        XCTAssertEqual(result.error as? RequestError, .cancelled)

        let frames = await server.receivedFrames
        XCTAssertEqual(frames.last?.body, .cancel(Cancel(targetRequestID: 1)))
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
        await session.close()
        await server.stop()
    }

    /// An archive written from what the session recorded reads back frame for frame as the
    /// server sent it.
    func test_C_ARCH_01_anArchiveWrittenFromTheMockServerReadsBack() async throws {
        let server = try await MockServer.start(
            script: try .fixtures(
                "handshake", "app-icon", "hierarchy", "layer-details", "layout-constraints"))
        let session = try await Harness.readySession(for: server)

        var payloads: [Data] = []
        let hello = await session.serverHelloPayload
        payloads.append(try XCTUnwrap(hello))
        payloads.append(try await session.recordedAppIcon().payload)
        payloads.append(try await session.recordedHierarchy().payload)
        for scenario in ["layer-details", "layout-constraints"] {
            let result = await collect(await session.recordedLayerDetails(try request(scenario)))
            XCTAssertNil(result.error)
            payloads += result.chunks.map(\.payload)
        }

        let version = await session.negotiatedVersion
        let negotiated = try XCTUnwrap(version)
        let manifest = ArchiveManifest(
            protocolVersion: negotiated, cutawayVersion: "0.1.0",
            savedAt: Date(timeIntervalSince1970: 1_791_280_000))
        var encoder = ArchiveEncoder()
        var archive = encoder.header(manifest: manifest, state: Data())
        for payload in payloads { archive += try encoder.frame(payload) }
        archive += encoder.trailer()

        let decoder = try ArchiveDecoder(archive)
        // Hello, AppStateChanged, AppIcon, Hierarchy, chunk, chunk, StreamEnd, chunk, StreamEnd.
        let sent = await server.sentPayloads
        XCTAssertEqual(decoder.payloads, [sent[0], sent[2], sent[3], sent[4], sent[5], sent[7]])
        XCTAssertEqual(decoder.manifest, manifest)
        XCTAssertEqual(decoder.chunkCount, 3)
        XCTAssertEqual(decoder.hierarchy, try Fixtures.hierarchy())

        await session.close()
        await server.stop()
    }
}
