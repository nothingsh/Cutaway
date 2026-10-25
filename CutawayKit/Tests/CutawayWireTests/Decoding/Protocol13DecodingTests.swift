import CutawayTestSupport
import FlatBuffers
import XCTest

@testable import CutawayWire

/// C-WIRE-13: what protocol 1.3's `dev.1` (`v1.3.0-dev.1`) appended — images' digests,
/// unchanged images and the digests a request gives. The expected values come from
/// Protocol/fixtures/README.md and Protocol/fixtures/src/layer-details-digest.
final class Protocol13DecodingTests: XCTestCase {
    private struct UnexpectedBody: Error {}

    private func decode(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    private func request(_ file: String) throws -> GetLayerDetails {
        guard case .getLayerDetails(let request) = try decode("layer-details-digest", file).body
        else { throw UnexpectedBody() }
        return request
    }

    private func chunk(_ file: String) throws -> LayerDetailsChunk {
        guard case .layerDetailsChunk(let chunk) = try decode("layer-details-digest", file).body
        else { throw UnexpectedBody() }
        return chunk
    }

    private struct NotFull: Error {}

    private func full(_ image: DetailImage?) throws -> EncodedImage {
        guard case .full(let image) = image else { throw NotFull() }
        return image
    }

    /// Layer 3's opaque red 200×24 group and layer 8's opaque orange 60×30 group, with the
    /// suggested algorithm (README, "Images").
    private static let red = Data([
        9, 136, 181, 224, 100, 253, 207, 200, 219, 178, 16, 26, 42, 236, 171, 89,
    ])
    private static let orange = Data([
        152, 60, 148, 35, 245, 62, 184, 98, 64, 130, 105, 173, 103, 185, 100, 119,
    ])

    private func pixels(_ image: EncodedImage) throws -> [UInt8] {
        let bitmap = try image.decoded()
        return Array(bitmap.pixels.prefix(4))
    }

    func test_C_WIRE_13_theDigestScenarioDecodesAsTheFixturesSay() throws {
        // First round: no digests to give; full images, each with its digest.
        XCTAssertEqual(try request("01-c2s-get-layer-details.bin"), GetLayerDetails(
            requests: [
                LayerDetailRequest(layerID: 3, wantSolo: true, wantGroup: true, wantAttributes: false),
                LayerDetailRequest(layerID: 8, wantSolo: false, wantGroup: true, wantAttributes: false),
            ],
            maxTextureDimension: 16384))
        let first = try chunk("02-s2c-chunk-0.bin")
        XCTAssertEqual(first.details.map(\.layerID), [3, 8])
        // Layer 3 is a leaf: only its group comes (P-DET-04).
        XCTAssertNil(first.details[0].solo)
        let red = try full(first.details[0].group)
        XCTAssertEqual(red.digest, Self.red)
        XCTAssertEqual(try pixels(red), [0x00, 0x00, 0xFF, 0xFF])
        let orange = try full(first.details[1].group)
        XCTAssertEqual(orange.digest, Self.orange)
        XCTAssertEqual(orange.bytesPerRow, 256)
        XCTAssertEqual(try pixels(orange), [0x00, 0x80, 0xFF, 0xFF])

        // Second round: the digests held, byte for byte; both answered unchanged, the leaf's
        // group standing for its solo as well (P-IMG-06).
        XCTAssertEqual(try request("04-c2s-get-layer-details.bin"), GetLayerDetails(
            requests: [
                LayerDetailRequest(
                    layerID: 3, wantSolo: true, wantGroup: true, wantAttributes: false,
                    knownSoloDigest: Self.red, knownGroupDigest: Self.red),
                LayerDetailRequest(
                    layerID: 8, wantSolo: false, wantGroup: true, wantAttributes: false,
                    knownGroupDigest: Self.orange),
            ],
            maxTextureDimension: 16384))
        XCTAssertEqual(try chunk("05-s2c-chunk-0.bin").details, [
            LayerDetail(
                layerID: 3, status: .ok, solo: nil, group: .unchanged(digest: Self.red),
                attributeGroups: []),
            LayerDetail(
                layerID: 8, status: .ok, solo: nil, group: .unchanged(digest: Self.orange),
                attributeGroups: []),
        ])

        // Third round: the same digests; layer 3 unchanged, layer 8 redrawn blue.
        XCTAssertEqual(
            try request("07-c2s-get-layer-details.bin"), try request("04-c2s-get-layer-details.bin"))
        let third = try chunk("08-s2c-chunk-0.bin")
        XCTAssertEqual(third.details[0].group, .unchanged(digest: Self.red))
        let blue = try full(third.details[1].group)
        XCTAssertEqual(try pixels(blue), [0xFF, 0x00, 0x00, 0xFF])
        let blueDigest = try XCTUnwrap(blue.digest)
        XCTAssertNotEqual(blueDigest, Self.orange)
        XCTAssertEqual(blueDigest.count, 16)
    }

    func test_C_WIRE_13_everyDetailImageInTheFixturesCarriesADigest() throws {
        var digests: [String: Set<Data>] = [:]
        for scenario in try Fixtures.scenarios() {
            for detail in try Fixtures.layerDetails(scenario: scenario) {
                for (kind, image) in [("solo", detail.solo), ("group", detail.group)] {
                    guard case .full(let image) = image else { continue }
                    let digest = try XCTUnwrap(image.digest, "\(scenario) \(detail.layerID) \(kind)")
                    XCTAssertTrue((1...32).contains(digest.count))
                    // The same picture has the same digest in every scenario (README).
                    let picture = "\(image.pixelWidth)×\(image.pixelHeight) \(try pixels(image))"
                    digests[picture, default: []].insert(digest)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(digests.count, 5)
        for (picture, set) in digests {
            XCTAssertEqual(set.count, 1, picture)
        }
        XCTAssertEqual(digests["200×24 [0, 0, 255, 255]"], [Self.red])
        XCTAssertEqual(digests["60×30 [0, 128, 255, 255]"], [Self.orange])
    }

    func test_C_WIRE_13_newFieldsSurviveARoundTrip() throws {
        let image = EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: 1, pixelHeight: 1, bytesPerRow: 4,
            scale: 2, data: Data([1, 2, 3]), digest: Data([7]))
        let chunk = Frame(requestID: 4, body: .layerDetailsChunk(LayerDetailsChunk(
            sequence: 0, details: [
                LayerDetail(
                    layerID: 1, status: .ok, solo: .full(image),
                    group: .unchanged(digest: Data(repeating: 9, count: 32)), attributeGroups: []),
            ])))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(chunk)), chunk)

        let request = Frame(requestID: 5, body: .getLayerDetails(GetLayerDetails(
            requests: [
                LayerDetailRequest(
                    layerID: 1, wantSolo: true, wantGroup: true, wantAttributes: false,
                    knownSoloDigest: Data([1]), knownGroupDigest: Data([2, 3])),
                LayerDetailRequest(
                    layerID: 2, wantSolo: true, wantGroup: true, wantAttributes: false,
                    knownGroupDigest: Data([4])),
                LayerDetailRequest(layerID: 3, wantSolo: true, wantGroup: false, wantAttributes: false),
            ],
            maxTextureDimension: 0)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(request)), request)
    }

    func test_C_WIRE_13_framesWithoutTheNewFieldsReadAsFullImagesWithoutDigests() throws {
        // What a 1.2 Server sends: an image with neither `digest` nor `unchanged`.
        let fixture = try full(try Fixtures.layerDetails(scenario: "layer-details-edge")[1].group)
        var builder = FlatBufferBuilder()
        let data = builder.createVector(bytes: fixture.data)
        let image = Cutaway_Wire_Image.createImage(
            &builder, pixelWidth: fixture.pixelWidth, pixelHeight: fixture.pixelHeight,
            bytesPerRow: fixture.bytesPerRow, scale: fixture.scale, dataVectorOffset: data)
        let detail = Cutaway_Wire_LayerDetail.createLayerDetail(&builder, layerId: 8, groupOffset: image)
        let details = builder.createVector(ofOffsets: [detail])
        let chunk = Cutaway_Wire_LayerDetailsChunk.createLayerDetailsChunk(
            &builder, detailsVectorOffset: details)
        let frame = Cutaway_Wire_Frame.createFrame(
            &builder, requestId: 4, bodyType: .layerdetailschunk, bodyOffset: chunk)
        builder.finish(offset: frame, fileId: FrameCodec.fileIdentifier)

        guard case .layerDetailsChunk(let read) = try FrameCodec.decode(builder.data).body
        else { throw UnexpectedBody() }
        var expected = fixture
        expected.digest = nil
        XCTAssertEqual(read.details.first?.group, .full(expected))
        XCTAssertNil(read.details.first?.solo)

        // A 1.2 Client's request: no digests given.
        let oneTwo = try request("01-c2s-get-layer-details.bin")
        XCTAssertTrue(oneTwo.requests.allSatisfy { $0.knownSoloDigest == nil && $0.knownGroupDigest == nil })
    }

    func test_C_WIRE_13_aRequestLeavesOutTheDigestsItDoesNotGive() throws {
        // Absent, not empty: the protocol does not say an empty digest means none (P-DET-11).
        let frame = Frame(requestID: 2, body: .getLayerDetails(GetLayerDetails(
            requests: [
                LayerDetailRequest(layerID: 1, wantSolo: true, wantGroup: true, wantAttributes: true),
                LayerDetailRequest(
                    layerID: 2, wantSolo: true, wantGroup: true, wantAttributes: false,
                    wantConstraints: true, knownGroupDigest: Data([8])),
            ],
            maxTextureDimension: 4096)))
        let payload = FrameCodec.encode(frame)
        let root = try FrameCodec.checkedRoot(payload)
        XCTAssertEqual(root.requestId, 2)
        let body = try XCTUnwrap(root.body(type: Cutaway_Wire_GetLayerDetails.self))
        XCTAssertEqual(body.requests.count, 2)
        let first = body.requests[0], second = body.requests[1]
        XCTAssertNil(first.withUnsafePointerToKnownSoloDigest { _, count in count })
        XCTAssertNil(first.withUnsafePointerToKnownGroupDigest { _, count in count })
        XCTAssertNil(second.withUnsafePointerToKnownSoloDigest { _, count in count })
        XCTAssertEqual(second.withUnsafePointerToKnownGroupDigest { _, count in count }, 1)
        XCTAssertEqual(try FrameCodec.decode(payload), frame)
    }

    /// An image made with the generated object API, which can give what the value types cannot.
    private func detailImage(_ configure: (Cutaway_Wire_ImageT) -> Void) throws -> DetailImage? {
        let detail = Cutaway_Wire_LayerDetailT()
        detail.layerId = 1
        let image = Cutaway_Wire_ImageT()
        configure(image)
        detail.group = image
        let chunk = Cutaway_Wire_LayerDetailsChunkT()
        chunk.details = [detail]
        var object = chunk
        var builder = FlatBufferBuilder()
        let end = Cutaway_Wire_LayerDetailsChunk.pack(&builder, obj: &object)
        Cutaway_Wire_LayerDetailsChunk.finish(&builder, end: end)
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_LayerDetailsChunk = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        return LayerDetailsChunk(wire).details.first?.group
    }

    func test_C_WIRE_13_anUnchangedImageWithoutADigestHasAnEmptyDigest() throws {
        // It matches no digest the Client holds, so the image counts as not received (C-DET-13).
        XCTAssertEqual(try detailImage { $0.unchanged = true }, .unchanged(digest: Data()))
        // Whatever else it carries is not looked at (P-IMG-05).
        XCTAssertEqual(
            try detailImage {
                $0.unchanged = true
                $0.digest = [5, 6]
                $0.pixelWidth = 3
                $0.data = [1, 2, 3]
            },
            .unchanged(digest: Data([5, 6])))
    }

    func test_C_WIRE_13_aDigestThatIsNotOneToThirtyTwoBytesIsDropped() throws {
        func digest(_ bytes: [UInt8]) throws -> Data? {
            try full(try detailImage {
                $0.pixelWidth = 1
                $0.pixelHeight = 1
                $0.bytesPerRow = 4
                $0.scale = 1
                $0.data = [0]
                $0.digest = bytes
            }).digest
        }
        XCTAssertNil(try digest([]))
        XCTAssertEqual(try digest([1]), Data([1]))
        XCTAssertEqual(try digest([UInt8](repeating: 2, count: 32)), Data(repeating: 2, count: 32))
        XCTAssertNil(try digest([UInt8](repeating: 3, count: 33)))
    }
}
