import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ENV-04: an archive holds the environment it was saved in, as an optional frame after the
/// Hierarchy (Resources/ARCHIVE.md).
final class ArchiveEnvironmentTests: XCTestCase {
    private static let darkAX3 = Traits(
        userInterfaceStyle: .dark, contentSizeCategory: .accessibilityExtraLarge)

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveEnvironmentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// An archive of the fixtures' app with Dark and AX3 overridden, saved over `version`.
    private func saved(
        overriding overrides: Traits = darkAX3, version: Version = ProtocolVersion.current
    ) async throws -> (Data, [MessageKind]) {
        var responder = try MockResponder.demo()
        var environment = MockEnvironment.iPhone()
        environment.overrides = overrides
        responder.environment = environment
        let server = try await ArchiveCaptureTests.server(responder)
        let session = try await ArchiveCaptureTests.session(to: server, protocolVersion: version)
        let destination = directory.appendingPathComponent("Demo.cutaway")
        try await ArchiveCapture.run(
            from: session, to: destination,
            stamp: ArchiveCapture.Stamp(cutawayVersion: "1.2.0", savedAt: Date(), state: ArchiveState()),
            maxTextureDimension: 0, progress: { _, _ in })
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        await session.close()
        await server.stop()
        return (try Data(contentsOf: destination), kinds)
    }

    /// The archive with its frames as `arrange` lays them out.
    private static func rewritten(_ archive: Data, _ arrange: ([Data]) -> [Data]) throws -> Data {
        let decoder = try ArchiveDecoder(archive)
        var encoder = ArchiveEncoder()
        var data = encoder.header(manifest: decoder.manifest, state: decoder.state)
        for payload in arrange(decoder.payloads) { data += try encoder.frame(payload) }
        return data + encoder.trailer()
    }

    func test_C_ENV_04_anArchiveSavedInDarkAX3HoldsItsEnvironment() async throws {
        let (archive, kinds) = try await saved()
        XCTAssertEqual(Array(kinds.prefix(5)), [.hello, .getAppIcon, .getHierarchy, .getEnvironment, .getLayerDetails])

        let decoder = try ArchiveDecoder(archive)
        XCTAssertEqual(decoder.environment?.overrides, Self.darkAX3)
        XCTAssertEqual(decoder.environment?.current.userInterfaceStyle, .dark)
        XCTAssertEqual(decoder.chunkCount, 2, "the chunks follow it")
        let source = ArchiveSource(decoder: decoder)
        let environment = try await source.environment()
        XCTAssertEqual(environment.overrides, Self.darkAX3)
        XCTAssertEqual(source.savedEnvironment?.overrides, Self.darkAX3)
        // An archive is looked at, never changed.
        do {
            _ = try await source.setEnvironment(.unspecified)
            XCTFail("an archive changed its environment")
        } catch {}
    }

    func test_C_ENV_04_anArchiveWithoutTheFrameOpensAsBefore() async throws {
        let (archive, _) = try await saved()
        let without = try Self.rewritten(archive) { payloads in
            var payloads = payloads
            payloads.remove(at: 3)
            return payloads
        }
        let decoder = try ArchiveDecoder(without)
        XCTAssertNil(decoder.environment)
        XCTAssertEqual(decoder.chunkCount, 2)
        XCTAssertEqual(try decoder.layers(inChunk: 0).first?.layerID, 1)
        let source = ArchiveSource(decoder: decoder)
        XCTAssertNil(source.savedEnvironment)
    }

    func test_C_ENV_04_theFrameElsewhereIsDamaged() async throws {
        let (archive, _) = try await saved()
        let moved = try Self.rewritten(archive) { payloads in
            var payloads = payloads
            let environment = payloads.remove(at: 3)
            payloads.append(environment)
            return payloads
        }
        XCTAssertThrowsError(try ArchiveDecoder(moved)) { error in
            guard case .damaged = error as? ArchiveError else {
                XCTFail("\(error) is not damaged")
                return
            }
        }
    }

    func test_C_ENV_04_aProtocol11ConnectionSavesNoFrame() async throws {
        let (archive, kinds) = try await saved(version: Version(major: 1, minor: 1))
        XCTAssertFalse(kinds.contains(.getEnvironment))
        let decoder = try ArchiveDecoder(archive)
        XCTAssertNil(decoder.environment)
        XCTAssertEqual(decoder.manifest.protocolVersion, Version(major: 1, minor: 1))
    }
}
