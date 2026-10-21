import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ARCH-07: an archive written over 1.2 says so, holds the environment, and keeps the
/// virtual (10 to 12) and excluded (13, 14) nodes of the `hierarchy` fixture without images;
/// opened, they are drawn as in the app, and nothing is missing.
final class ArchiveVirtualNodesTests: XCTestCase {
    private static let dark = Traits(userInterfaceStyle: .dark)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveVirtualNodesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The fixtures' app in Dark, archived over 1.2, with what it was asked.
    private static func saved(in directory: URL) async throws -> (Data, [LayerDetailRequest]) {
        var responder = try MockResponder.demo()
        var environment = MockEnvironment.iPhone()
        environment.overrides = Self.dark
        responder.environment = environment
        let server = try await ArchiveCaptureTests.server(responder)
        let session = try await ArchiveCaptureTests.session(to: server)
        let destination = directory.appendingPathComponent("Demo.cutaway")
        try await ArchiveCapture.run(
            from: session, to: destination,
            stamp: ArchiveCapture.Stamp(cutawayVersion: "1.2.0", savedAt: Date(), state: ArchiveState()),
            maxTextureDimension: 4096, progress: { _, _ in })
        let requests = await server.receivedFrames.flatMap { frame -> [LayerDetailRequest] in
            guard case .getLayerDetails(let request) = frame.body else { return [] }
            return request.requests
        }
        await session.close()
        await server.stop()
        return (try Data(contentsOf: destination), requests)
    }

    func test_C_ARCH_07_archivingAsksNoImagesOfVirtualNodesAndNoConstraints() async throws {
        let (_, requests) = try await Self.saved(in: directory)
        for id: UInt64 in [10, 11, 12] {
            let request = try XCTUnwrap(requests.first { $0.layerID == id })
            XCTAssertEqual(
                request,
                LayerDetailRequest(
                    layerID: id, wantSolo: false, wantGroup: false, wantAttributes: true,
                    wantConstraints: false),
                "node \(id)")
        }
        XCTAssertEqual(requests.first { $0.layerID == 4 }?.wantConstraints, true)
    }

    func test_C_ARCH_07_anArchiveWithVirtualExcludedAndEnvironmentRoundTrips() async throws {
        let (archive, _) = try await Self.saved(in: directory)
        let decoder = try ArchiveDecoder(archive)
        XCTAssertEqual(decoder.manifest.protocolVersion, Version(major: 1, minor: 2))
        let source = ArchiveSource(decoder: decoder)

        let hierarchy = try await source.hierarchy()
        XCTAssertEqual(hierarchy, try Fixtures.hierarchy(), "kinds, names and both marks too")
        let environment = try await source.environment()
        XCTAssertEqual(environment.overrides, Self.dark)

        let asked = GetLayerDetails(
            requests: [10, 13].map {
                LayerDetailRequest(
                    layerID: $0, wantSolo: true, wantGroup: true, wantAttributes: true,
                    wantConstraints: true)
            },
            maxTextureDimension: 0)
        var details: [LayerDetail] = []
        for try await chunk in await source.layerDetails(asked).chunks { details += chunk }
        let row = try XCTUnwrap(details.first { $0.layerID == 10 })
        XCTAssertEqual(row.status, .ok)
        XCTAssertNil(row.solo)
        XCTAssertNil(row.group)
        XCTAssertEqual(row.attributeGroups, try Fixtures.attributes(of: 10, scenario: "layer-details"))
        let card = try XCTUnwrap(details.first { $0.layerID == 13 })
        XCTAssertEqual(card.status, .excluded)
        XCTAssertNil(card.group)
        XCTAssertFalse(card.attributeGroups.isEmpty)
    }

    @MainActor
    func test_C_ARCH_07_anOpenedArchiveDrawsVirtualAndExcludedNodesAsLive() async throws {
        let (archive, _) = try await Self.saved(in: directory)
        let source = ArchiveSource(decoder: try ArchiveDecoder(archive))
        let model = InspectionStore(source: source, maxTextureDimension: 4096, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let done = await Wait.until {
            await MainActor.run {
                model.loadState == .loaded && model.detailProgress.total > 0
                    && model.detailProgress.completed == model.detailProgress.total
            }
        }
        XCTAssertTrue(done)
        let content = Dictionary(
            uniqueKeysWithValues: model.tree.sceneLayers().map { ($0.id, $0.content) })
        XCTAssertEqual([10, 11, 12].map { content[$0] }, Array(repeating: .drawnByParent, count: 3))
        XCTAssertEqual([13, 14].map { content[$0] }, [.excluded, .excluded])
        XCTAssertEqual(model.detailProgress.total, 7, "nothing asked for them")
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.canExportImage(of: 10, kind: .group))
        XCTAssertFalse(model.canExportImage(of: 13, kind: .group))
        XCTAssertTrue(model.canExportImage(of: 4, kind: .group))
    }
}
