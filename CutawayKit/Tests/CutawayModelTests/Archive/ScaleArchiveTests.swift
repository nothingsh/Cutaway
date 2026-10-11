import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-SCALE-01: an archive of 10,000 app-shaped layers (`ScaleScene`) is saved by the way ⌘S
/// saves one (C-ARCH-02). There is no limit on how long it takes; the time is printed.
final class ScaleArchiveTests: XCTestCase {
    @MainActor
    func test_C_SCALE_01_anArchiveOfTenThousandLayersIsSaved() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScaleArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Large.cutaway")

        let server = try await MockServer.start(script: try ScaleScene.script(), records: false)
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"),
            requestTimeout: .seconds(30))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, maxTextureDimension: 4096)
        model.enter()
        let count = try ScaleScene.hierarchy().nodes.count
        let loaded = await Wait.until(within: .seconds(30)) {
            await MainActor.run { model.tree.count == count }
        }
        XCTAssertTrue(loaded)

        let start = ContinuousClock.now
        model.saveArchive(to: url, cutawayVersion: "0.1.0")
        let saved = await Wait.until(within: .seconds(300)) {
            await MainActor.run {
                if case .saving = model.archiveSave { false } else { true }
            }
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertTrue(saved)
        XCTAssertEqual(model.archiveSave, .saved(url))
        print("C-SCALE-01 archive of \(count) layers saved in \(ScaleScene.milliseconds(elapsed))")

        let decoder = try ArchiveDecoder(try Data(contentsOf: url, options: .alwaysMapped))
        XCTAssertEqual(decoder.hierarchy.nodes.count, count)
        var held = Set<UInt64>()
        for index in 0..<decoder.chunkCount {
            for layer in try decoder.layers(inChunk: index) { held.insert(layer.layerID) }
        }
        XCTAssertEqual(held, Set(decoder.hierarchy.nodes.map(\.id)), "every layer's details")

        model.leave()
        await session.close()
        await server.stop()
    }
}
