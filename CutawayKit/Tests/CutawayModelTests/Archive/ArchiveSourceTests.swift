import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ARCH-05: an archive answers an inspection's questions as the app would.
final class ArchiveSourceTests: XCTestCase {
    private func source(chunkSize: Int = 4) throws -> ArchiveSource {
        ArchiveSource(decoder: try ArchiveDecoder(try Fixtures.archive(chunkSize: chunkSize)))
    }

    private func details(
        _ request: GetLayerDetails, from source: ArchiveSource
    ) async throws -> [LayerDetail] {
        var all: [LayerDetail] = []
        for try await chunk in await source.layerDetails(request).chunks { all += chunk }
        return all
    }

    func test_C_ARCH_05_theSourceAnswersFromTheArchive() async throws {
        let source = try source()
        let responder = try MockResponder.demo()
        XCTAssertFalse(source.isLive)
        let version = await source.negotiatedVersion
        XCTAssertEqual(version, ProtocolVersion.current)
        let hierarchy = try await source.hierarchy()
        XCTAssertEqual(hierarchy, try Fixtures.hierarchy())

        let request = GetLayerDetails(
            requests: [
                LayerDetailRequest(layerID: 4, wantSolo: true, wantGroup: false, wantAttributes: false),
                LayerDetailRequest(
                    layerID: 3, wantSolo: false, wantGroup: true, wantAttributes: true,
                    wantConstraints: true),
                LayerDetailRequest(layerID: 77, wantSolo: true, wantGroup: true, wantAttributes: true),
            ],
            maxTextureDimension: 4096)
        let answer = try await details(request, from: source)
        XCTAssertEqual(answer, responder.answer(request))
        XCTAssertEqual(answer.map(\.status), [.ok, .ok, .layerNotFound])
        XCTAssertNotNil(answer[0].solo)
        XCTAssertEqual(answer[1].constraints.count, 4)

        do {
            _ = try await source.subtree(of: 4)
            XCTFail("an archive has no subtrees to send")
        } catch {
            XCTAssertEqual(error as? RequestError, .unsupported)
        }
        do {
            _ = try await source.setAttribute(SetAttribute(
                layerID: 3, attributeID: "view.alpha", value: .double(0.5)))
            XCTFail("an archive cannot be changed")
        } catch {
            XCTAssertEqual(error as? RequestError, .unsupported)
        }
    }

    func test_C_ARCH_05_onlyTheChunksAskedForAreDecoded() async throws {
        // Nine layers, four to a chunk: 1-4, 5-8, 9.
        let source = try source(chunkSize: 4)
        let decodedAtFirst = await source.decodedChunkCount
        XCTAssertEqual(decodedAtFirst, 0)

        let one = GetLayerDetails(
            requests: [LayerDetailRequest(layerID: 9, wantSolo: true, wantGroup: true, wantAttributes: true)],
            maxTextureDimension: 0)
        _ = try await details(one, from: source)
        let afterOne = await source.decodedChunkCount
        XCTAssertEqual(afterOne, 1)

        _ = try await details(one, from: source)
        let again = await source.decodedChunkCount
        XCTAssertEqual(again, 1, "a chunk just decoded is decoded again")

        let two = GetLayerDetails(
            requests: [1, 5].map {
                LayerDetailRequest(layerID: $0, wantSolo: true, wantGroup: true, wantAttributes: true)
            },
            maxTextureDimension: 0)
        let answer = try await details(two, from: source)
        XCTAssertEqual(answer.map(\.layerID), [1, 5])
        let afterTwo = await source.decodedChunkCount
        XCTAssertEqual(afterTwo, 3)
    }
}
