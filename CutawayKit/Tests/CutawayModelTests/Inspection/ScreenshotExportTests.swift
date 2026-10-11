import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ARCH-06: getting a layer's screenshot to export, online and from an archive.
@MainActor
final class ScreenshotExportTests: XCTestCase {
    private func eventually(
        within timeout: Duration = .seconds(3), _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// An open inspection of the fixtures' app over a connection, its first screenshots in.
    private func liveInspection(
        _ responder: MockResponder
    ) async throws -> (MockServer, Session, InspectionStore) {
        let server = try await ArchiveCaptureTests.server(responder)
        let session = try await ArchiveCaptureTests.session(to: server)
        let model = InspectionStore(
            session: session, maxTextureDimension: 4096, newLayers: .expanded)
        model.enter()
        let ready = await eventually { model.images[4]?.solo != nil }
        XCTAssertTrue(ready, "layer 4's solo did not arrive")
        // Let the preview's round finish, so that what follows is the export's alone.
        _ = await eventually {
            model.detailProgress.total > 0 && model.detailProgress.completed == model.detailProgress.total
        }
        return (server, session, model)
    }

    private static func detailRequests(_ server: MockServer) async -> [GetLayerDetails] {
        await server.receivedFrames.compactMap { frame in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }
    }

    private func exported(
        _ model: InspectionStore, _ id: UInt64, _ kind: TextureKey.Kind
    ) async -> Result<Bitmap, ScreenshotExportFailure> {
        do {
            return .success(try await model.exportImage(of: id, kind: kind))
        } catch {
            return .failure(error)
        }
    }

    private func color(of bitmap: Bitmap) -> [UInt8] {
        Array(bitmap.pixels.prefix(4))
    }

    // MARK: - Online

    func test_C_ARCH_06_anImageThePreviewHoldsIsExportedWithoutAsking() async throws {
        let (server, session, model) = try await liveInspection(try MockResponder.demo())
        let before = await Self.detailRequests(server).count

        let bitmap = try await exported(model, 4, .solo).get()
        XCTAssertEqual(bitmap.pixelWidth, 300)
        XCTAssertEqual(bitmap.pixelHeight, 180)
        XCTAssertEqual(color(of: bitmap), [0x00, 0xFF, 0x00, 0xFF])
        let after = await Self.detailRequests(server).count
        XCTAssertEqual(after, before)
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_06_aMissingImageIsAskedForAlone() async throws {
        let (server, session, model) = try await liveInspection(try MockResponder.demo())
        // Layer 4 is expanded: the preview draws its solo and has not asked for its group.
        XCTAssertNil(model.images[4]?.group)
        let before = await Self.detailRequests(server).count

        let bitmap = try await exported(model, 4, .group).get()
        XCTAssertEqual(bitmap.pixelWidth, 300)
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.count, before + 1)
        XCTAssertEqual(requests.last, GetLayerDetails(
            requests: [LayerDetailRequest(layerID: 4, wantSolo: false, wantGroup: true, wantAttributes: false)],
            maxTextureDimension: 4096))
        // The image is not taken into the preview.
        XCTAssertNil(model.images[4]?.group)
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_06_aMissingSoloFallsBackToTheGroup() async throws {
        // Layer 3 has no sublayers; the fixtures give it only a group (P-DET-04).
        let (server, session, model) = try await liveInspection(try MockResponder.demo())
        XCTAssertNil(model.images[3]?.solo)

        let bitmap = try await exported(model, 3, .solo).get()
        XCTAssertEqual(bitmap.pixelWidth, 200)
        XCTAssertEqual(color(of: bitmap), [0x00, 0x00, 0xFF, 0xFF])
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.last?.requests, [
            LayerDetailRequest(layerID: 3, wantSolo: true, wantGroup: true, wantAttributes: false),
        ])
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_06_failuresSayWhy() async throws {
        var responder = try MockResponder.demo()
        responder.details[5]?.status = .captureFailed
        responder.details[6] = nil
        responder.failDetails = ({ request in
            request.requests.map(\.layerID) == [7]
        }, .appNotActive)
        let (server, session, model) = try await liveInspection(responder)

        var result = await exported(model, 5, .group)
        XCTAssertEqual(result.failure, .notCaptured)
        result = await exported(model, 6, .group)
        XCTAssertEqual(result.failure, .layerGone)
        result = await exported(model, 7, .group)
        XCTAssertEqual(result.failure, .appNotActive)
        // A layer the app gives no image for, without saying it failed.
        result = await exported(model, 1, .group)
        XCTAssertEqual(result.failure, .notCaptured)

        XCTAssertTrue(model.canExportImage(of: 6, kind: .group))
        XCTAssertFalse(model.canExportImage(of: 77, kind: .group), "not in the tree")
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_06_theFileIsWrittenOrNothingIs() async throws {
        let (server, session, model) = try await liveInspection(try MockResponder.demo())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotExportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("CardView 4.png")
        let encode: @Sendable (Bitmap) -> Data? = { bitmap in Data("\(bitmap.pixelWidth)".utf8) }

        model.exportScreenshot(of: 4, kind: .solo, to: url, encode: encode)
        XCTAssertEqual(model.screenshotExport, .exporting)
        XCTAssertFalse(model.canExportImage(of: 3, kind: .group), "one export at a time")
        let written = await eventually { model.screenshotExport == .idle }
        XCTAssertTrue(written)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "300")

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        let refused = directory.appendingPathComponent("Other.png")
        model.exportScreenshot(of: 4, kind: .solo, to: refused, encode: encode)
        let failed = await eventually {
            if case .failed(.writeFailed) = model.screenshotExport { return true }
            return false
        }
        XCTAssertTrue(failed, "ended as \(model.screenshotExport)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: refused.path))
        model.dismissScreenshotExport()
        XCTAssertEqual(model.screenshotExport, .idle)

        // The layer went: the reason, and no file.
        model.exportScreenshot(of: 4, kind: .solo, to: url, encode: { _ in nil })
        let unencoded = await eventually { model.screenshotExport == .failed(.notCaptured) }
        XCTAssertTrue(unencoded, "ended as \(model.screenshotExport)")
        await session.close()
        await server.stop()
    }

    // MARK: - From an archive

    func test_C_ARCH_06_anArchiveExportsOnlyWhatItHolds() async throws {
        let source = ArchiveSource(decoder: try ArchiveDecoder(try Fixtures.archive()))
        XCTAssertEqual(source.knownImagePresence[8], ImagePresence(solo: false, group: true))
        XCTAssertEqual(source.knownImagePresence[4], ImagePresence(solo: true, group: true))
        XCTAssertEqual(source.knownImagePresence[1], ImagePresence(solo: false, group: false))

        let model = InspectionStore(source: source, maxTextureDimension: 4096, newLayers: .expanded)
        model.enter()
        let loaded = await eventually { model.loadState == .loaded }
        XCTAssertTrue(loaded)
        XCTAssertTrue(model.canExportImage(of: 8, kind: .group))
        XCTAssertTrue(model.canExportImage(of: 8, kind: .solo), "a missing solo is the group")
        XCTAssertFalse(model.canExportImage(of: 1, kind: .group))
        XCTAssertFalse(model.canExportImage(of: 1, kind: .solo))

        let bitmap = try await exported(model, 8, .group).get()
        XCTAssertEqual(bitmap.pixelWidth, 60)
        XCTAssertEqual(bitmap.pixelHeight, 30)
        XCTAssertEqual(color(of: bitmap), [0x00, 0x80, 0xFF, 0xFF])
    }
}
