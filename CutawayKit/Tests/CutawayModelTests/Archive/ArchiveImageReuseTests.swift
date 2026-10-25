import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ARCH-08: an archive written over 1.3 holds full images, however the last refresh was
/// answered; its frames keep the digests as received, and an archive opened gives none.
final class ArchiveImageReuseTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveImageReuseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var destination: URL { directory.appendingPathComponent("Demo.cutaway") }

    @MainActor
    private static func roundDone(_ model: InspectionStore) async -> Bool {
        await Wait.until {
            await MainActor.run {
                model.loadState == .loaded && model.detailProgress.total > 0
                    && model.detailProgress.completed == model.detailProgress.total
            }
        }
    }

    private static func images(in archive: ArchiveDecoder) throws -> [(UInt64, DetailImage)] {
        try (0..<archive.chunkCount).flatMap { index in
            try archive.chunk(at: index).details.flatMap { detail in
                [detail.solo, detail.group].compactMap { $0 }.map { (detail.layerID, $0) }
            }
        }
    }

    @MainActor
    func test_C_ARCH_08_anArchiveSavedAfterNothingChangedHoldsTheFullImages() async throws {
        let server = try await ArchiveCaptureTests.server(try MockResponder.demo())
        let session = try await ArchiveCaptureTests.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let first = await Self.roundDone(model)
        XCTAssertTrue(first)
        let capabilities = await Wait.until { await MainActor.run { model.canRefreshSubtrees } }
        XCTAssertTrue(capabilities)
        let held = model.images
        var arriving = 0
        let subscription = model.arrivingPixels.sink { _ in arriving += 1 }
        let before = await server.receivedFrames.count
        model.refresh()
        let refreshed = await Wait.until { await server.receivedFrames.count > before }
        XCTAssertTrue(refreshed)
        let second = await Self.roundDone(model)
        XCTAssertTrue(second)
        XCTAssertEqual(arriving, 0, "every image was answered unchanged")
        XCTAssertEqual(model.images, held)
        subscription.cancel()

        model.saveArchive(to: destination, cutawayVersion: "1.3.0")
        let destination = destination
        let saved = await Wait.until { await MainActor.run { model.archiveSave == .saved(destination) } }
        XCTAssertTrue(saved, "ended as \(model.archiveSave)")

        let archive = try ArchiveDecoder(try Data(contentsOf: destination))
        XCTAssertEqual(archive.manifest.protocolVersion, Version(major: 1, minor: 3))
        let images = try Self.images(in: archive)
        XCTAssertFalse(images.isEmpty)
        for (id, image) in images {
            let full = try XCTUnwrap(image.fullImage, "layer \(id) is not unchanged")
            // The frames are kept as received, digest and all (Resources/ARCHIVE.md).
            XCTAssertNotNil(full.digest)
        }
        for id: UInt64 in [3, 4, 8] {
            for kind in [TextureKey.Kind.solo, .group] {
                guard let mine = held[id]?[kind]?.image else { continue }
                let theirs = try XCTUnwrap(
                    images.first { $0.0 == id && $0.1.fullImage?.digest == mine.digest }?.1.fullImage,
                    "layer \(id) \(kind)")
                XCTAssertEqual(try theirs.decoded().pixels, try mine.decoded().pixels)
            }
        }
        // The capture gives no digests: it wants the images themselves.
        let capture = await server.receivedFrames.compactMap { frame -> GetLayerDetails? in
            guard case .getLayerDetails(let request) = frame.body,
                  MockResponder.isArchiveBatch(request) else { return nil }
            return request
        }
        XCTAssertFalse(capture.isEmpty)
        XCTAssertTrue(capture.flatMap(\.requests).allSatisfy {
            $0.knownSoloDigest == nil && $0.knownGroupDigest == nil
        })

        await session.close()
        await server.stop()
    }

    private static func saved(over version: Version, to destination: URL) async throws -> ArchiveDecoder {
        let server = try await ArchiveCaptureTests.server(try MockResponder.demo())
        let session = try await ArchiveCaptureTests.session(to: server, protocolVersion: version)
        try await ArchiveCapture.run(
            from: session, to: destination,
            stamp: ArchiveCapture.Stamp(cutawayVersion: "1.3.0", savedAt: Date(), state: ArchiveState()),
            maxTextureDimension: 4096, progress: { _, _ in })
        await session.close()
        await server.stop()
        return try ArchiveDecoder(try Data(contentsOf: destination))
    }

    @MainActor
    func test_C_ARCH_08_anOpenedArchivesImagesHaveNoDigests() async throws {
        let archive = try await Self.saved(over: ProtocolVersion.current, to: destination)
        let model = InspectionStore(
            source: ArchiveSource(decoder: archive), maxTextureDimension: 4096, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let done = await Self.roundDone(model)
        XCTAssertTrue(done)
        XCTAssertFalse(model.images.isEmpty)
        for (id, images) in model.images {
            XCTAssertNil(images.solo?.image.digest, "layer \(id)")
            XCTAssertNil(images.group?.image.digest, "layer \(id)")
            for kind in [TextureKey.Kind.solo, .group] {
                XCTAssertNil(model.knownDigest(for: TextureNeed(layerID: id, kind: kind)))
            }
        }
    }

    @MainActor
    func test_C_ARCH_08_anArchiveSavedOverOneTwoStillOpens() async throws {
        let archive = try await Self.saved(over: Version(major: 1, minor: 2), to: destination)
        XCTAssertEqual(archive.manifest.protocolVersion, Version(major: 1, minor: 2))
        let model = InspectionStore(
            source: ArchiveSource(decoder: archive), maxTextureDimension: 4096, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let done = await Self.roundDone(model)
        XCTAssertTrue(done)
        XCTAssertEqual(model.tree.ids.count, 14)
        XCTAssertNotNil(model.images[3]?.group)
    }
}
