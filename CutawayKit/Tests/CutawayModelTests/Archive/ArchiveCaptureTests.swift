import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ARCH-02: capturing an archive over a connection, against a MockServer that answers by
/// content.
final class ArchiveCaptureTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")
    private static let savedAt = Date(timeIntervalSince1970: 1_791_280_000)

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveCaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private var destination: URL { directory.appendingPathComponent("Demo.cutaway") }

    static func server(_ responder: MockResponder) async throws -> MockServer {
        let steps = try MockScript.fixtures("handshake").steps
        return try await MockServer.start(script: MockScript(steps: steps + [.respond(responder)]))
    }

    static func session(
        to server: MockServer, protocolVersion: Version = ProtocolVersion.current
    ) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: client, protocolVersion: protocolVersion,
            requestTimeout: .seconds(5))
        _ = try await session.handshake()
        return session
    }

    /// Records the progress reports.
    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var reports: [(Int, Int)] = []

        func add(_ completed: Int, _ total: Int) {
            lock.withLock { reports.append((completed, total)) }
        }

        var all: [(Int, Int)] { lock.withLock { reports } }
    }

    private static func capture(
        _ session: Session, to destination: URL, state: ArchiveState = ArchiveState(),
        progress: Progress = Progress()
    ) async -> Result<Void, ArchiveCaptureError> {
        do {
            try await ArchiveCapture.run(
                from: session, to: destination,
                stamp: ArchiveCapture.Stamp(cutawayVersion: "0.1.0", savedAt: savedAt, state: state),
                maxTextureDimension: 4096, progress: { progress.add($0, $1) })
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func detailRequests(_ server: MockServer) async -> [GetLayerDetails] {
        await server.receivedFrames.compactMap { frame in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }
    }

    /// Nothing at the destination, and nothing left in the directory.
    private func assertNoFileLeft(file: StaticString = #filePath, line: UInt = #line) throws {
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(left, [], file: file, line: line)
    }

    // MARK: - C-ARCH-02

    func test_C_ARCH_02_aCaptureAsksForEveryLayerInBatches() async throws {
        let server = try await Self.server(try MockResponder.demo())
        let session = try await Self.session(to: server)
        let progress = Progress()
        var state = ArchiveState()
        state.selected = 3

        let result = await Self.capture(session, to: destination, state: state, progress: progress)
        XCTAssertNoThrow(try result.get())

        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.map { $0.requests.map(\.layerID) }, [
            [1, 2, 3, 4, 10, 11, 12, 5], [6, 7, 8, 9, 13, 14],
        ])
        for request in requests {
            XCTAssertEqual(request.maxTextureDimension, 4096)
            // Everything of every layer, but no images of virtual nodes or of those the app
            // excludes, and no constraints of virtual nodes (C-DET-11).
            XCTAssertTrue(request.requests.allSatisfy {
                let isVirtual = [10, 11, 12].contains($0.layerID)
                let wantsImages = !isVirtual && ![13, 14].contains($0.layerID)
                return $0.wantSolo == wantsImages && $0.wantGroup == wantsImages
                    && $0.wantAttributes && $0.wantConstraints == !isVirtual
            })
        }

        // The file holds the frames as the server sent them: Hello, icon, hierarchy, the
        // environment (C-ENV-04), chunks.
        let decoder = try ArchiveDecoder(try Data(contentsOf: destination))
        let sent = await server.sentPayloads
        let kept = sent.filter {
            guard let body = try? FrameCodec.decode($0).body else { return false }
            switch body {
            case .hello, .appIcon, .hierarchy, .environment, .layerDetailsChunk: return true
            default: return false
            }
        }
        XCTAssertEqual(decoder.payloads, kept)
        XCTAssertEqual(decoder.chunkCount, 2)
        XCTAssertEqual(decoder.manifest, ArchiveManifest(
            protocolVersion: ProtocolVersion.current, cutawayVersion: "0.1.0",
            savedAt: Self.savedAt))
        XCTAssertEqual(ArchiveState(decoding: decoder.state), state)
        XCTAssertEqual(try decoder.chunk(at: 0).details[2].attributeGroups.count, 3)

        XCTAssertEqual(progress.all.last?.0, 14)
        XCTAssertEqual(progress.all.last?.1, 14)
        XCTAssertEqual(progress.all.map(\.0), [0, 8, 14])

        // Only the archive is left in the directory.
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(left, ["Demo.cutaway"])
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_theNextBatchWaitsForTheLastOneToEnd() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        responder.holdBeforeDetailsRequest = (1, gate)
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server)

        let target = destination
        // Not `Self.capture`: `Self` inside the task's closure makes Xcode 26's compiler stop at
        // "pattern that the region-based isolation checker does not understand".
        // swiftlint:disable:next prefer_self_in_static_references
        let running = Task { await ArchiveCaptureTests.capture(session, to: target) }
        let asked = await eventually { await Self.detailRequests(server).count == 1 }
        XCTAssertTrue(asked)
        try await Task.sleep(for: .milliseconds(100))
        let whileHeld = await Self.detailRequests(server).count
        XCTAssertEqual(whileHeld, 1, "the second batch went out before the first ended")

        await gate.open()
        let finished = await running.value
        XCTAssertNoThrow(try finished.get())
        let afterwards = await Self.detailRequests(server).count
        XCTAssertEqual(afterwards, 2)
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_layersGoneOrNotCapturedAreKeptAsTheyCame() async throws {
        var responder = try MockResponder.demo()
        responder.details[5]?.status = .captureFailed
        responder.details[9] = nil
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server)

        let outcome = await Self.capture(session, to: destination)
        XCTAssertNoThrow(try outcome.get())
        let decoder = try ArchiveDecoder(try Data(contentsOf: destination))
        let details = try (0..<decoder.chunkCount).flatMap { try decoder.chunk(at: $0).details }
        XCTAssertEqual(details.map(\.layerID), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        XCTAssertEqual(details[7].status, .captureFailed)
        XCTAssertEqual(details[11].status, .layerNotFound)
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_losingTheConnectionLeavesNoFile() async throws {
        var responder = try MockResponder.demo()
        responder.failDetailsRequest = (2, .disconnect)
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server)

        let result = await Self.capture(session, to: destination)
        XCTAssertEqual(result.failure, .failed(.disconnected))
        try assertNoFileLeft()
        await server.stop()
    }

    func test_C_ARCH_02_anInactiveAppLeavesNoFile() async throws {
        var responder = try MockResponder.demo()
        responder.failDetailsRequest = (1, .appNotActive)
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server)

        let result = await Self.capture(session, to: destination)
        XCTAssertEqual(result.failure, .failed(.appNotActive))
        try assertNoFileLeft()
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_cancellingLeavesNoFile() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        responder.holdBeforeDetailsRequest = (2, gate)
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server)

        let target = destination
        // Not `Self.capture`: `Self` inside the task's closure makes Xcode 26's compiler stop at
        // "pattern that the region-based isolation checker does not understand".
        // swiftlint:disable:next prefer_self_in_static_references
        let running = Task { await ArchiveCaptureTests.capture(session, to: target) }
        let asked = await eventually { await Self.detailRequests(server).count == 2 }
        XCTAssertTrue(asked)
        running.cancel()
        let result = await running.value
        XCTAssertEqual(result.failure, .cancelled)
        try assertNoFileLeft()

        // The stream in flight was cancelled (P-REQ-04).
        await gate.open()
        let cancelled = await eventually {
            await server.receivedFrames.contains {
                if case .cancel = $0.body { return true }
                return false
            }
        }
        XCTAssertTrue(cancelled)
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_aFailedCaptureLeavesTheExistingFileAlone() async throws {
        let old = Data("an older archive".utf8)
        try old.write(to: destination)

        var failing = try MockResponder.demo()
        failing.failDetailsRequest = (1, .appNotActive)
        let server = try await Self.server(failing)
        let session = try await Self.session(to: server)
        let result = await Self.capture(session, to: destination)
        XCTAssertEqual(result.failure, .failed(.appNotActive))
        XCTAssertEqual(try Data(contentsOf: destination), old)
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(left, ["Demo.cutaway"])
        await session.close()
        await server.stop()

        // A capture that completes replaces it.
        let working = try await Self.server(try MockResponder.demo())
        let other = try await Self.session(to: working)
        let outcome = await Self.capture(other, to: destination)
        XCTAssertNoThrow(try outcome.get())
        XCTAssertNoThrow(try ArchiveDecoder(try Data(contentsOf: destination)))
        await other.close()
        await working.stop()
    }

    func test_C_ARCH_02_aFileThatCannotBeWrittenFails() async throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: directory.path)
        let server = try await Self.server(try MockResponder.demo())
        let session = try await Self.session(to: server)

        let result = await Self.capture(session, to: destination)
        guard case .failed(.writeFailed) = result.failure else {
            XCTFail("expected a write failure, got \(String(describing: result.failure))")
            return
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        await session.close()
        await server.stop()
    }

    private func eventually(
        within timeout: Duration = .seconds(3), _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
