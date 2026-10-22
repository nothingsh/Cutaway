import CutawayTestSupport
import Foundation
import XCTest
@testable import CutawayWire

/// Opening an archive reads its frames where they lie in the mapped file whenever their
/// first byte is on an 8-byte boundary: checking the chunks side by side, then decoding one,
/// copies only the frames the runtime cannot read in place (C-ARCH-04, C-SCALE-01).
final class InPlaceReadingTests: XCTestCase {
    private func chunkPayload() throws -> Data {
        try Fixtures.data(scenario: "layer-details", file: "02-s2c-chunk-0.bin")
    }

    /// `payload` placed `offset` bytes into a larger buffer, as a slice whose indices start there.
    private func slice(of payload: Data, at offset: Int) -> Data {
        var bytes = Data(count: offset + payload.count + 8)
        bytes.replaceSubrange(offset..<(offset + payload.count), with: payload)
        return bytes[offset..<(offset + payload.count)]
    }

    private func startsAligned(_ data: Data) -> Bool {
        data.withUnsafeBytes { Int(bitPattern: $0.baseAddress) % 8 == 0 }
    }

    func test_C_ARCH_04_aSliceOnAnEightByteBoundaryIsReadWithoutACopy() throws {
        let payload = try chunkPayload()
        let expected = try FrameCodec.decode(Data(payload))
        let aligned = slice(of: payload, at: 16)
        XCTAssertNotEqual(aligned.startIndex, 0)
        try XCTSkipUnless(startsAligned(aligned), "the allocator did not align the buffer")

        let before = FrameCodec.copyCount
        XCTAssertEqual(try FrameCodec.decode(aligned), expected)
        XCTAssertEqual(
            try FrameCodec.withCheckedRoot(aligned) { $0.bodyType == .layerdetailschunk }, true)
        XCTAssertEqual(FrameCodec.copyCount - before, 0, "an aligned slice was copied")
    }

    func test_C_ARCH_04_aSliceOffAnEightByteBoundaryIsCopiedAndReadsTheSame() throws {
        let payload = try chunkPayload()
        let expected = try FrameCodec.decode(Data(payload))
        let misaligned = slice(of: payload, at: 12)
        try XCTSkipIf(startsAligned(misaligned), "the allocator did not align the buffer")

        let before = FrameCodec.copyCount
        XCTAssertEqual(try FrameCodec.decode(misaligned), expected)
        XCTAssertEqual(FrameCodec.copyCount - before, 1)
    }

    func test_C_ARCH_04_openingAMappedArchiveCopiesOnlyTheFramesOffABoundary() throws {
        // Chunks of several lengths, so that their frames land both on and off a boundary.
        let chunks = try [
            Fixtures.data(scenario: "layer-details", file: "02-s2c-chunk-0.bin"),
            Fixtures.data(scenario: "layer-details", file: "03-s2c-chunk-1.bin"),
            Fixtures.data(scenario: "layout-constraints", file: "02-s2c-chunk-0.bin"),
        ]
        var encoder = ArchiveEncoder()
        var bytes = encoder.header(
            manifest: ArchiveManifest(
                protocolVersion: ProtocolVersion.current, cutawayVersion: "0.1.0",
                savedAt: Date(timeIntervalSince1970: 1_791_280_000)),
            state: Data())
        bytes += try encoder.frame(Fixtures.data(scenario: "handshake", file: "02-s2c-hello.bin"))
        bytes += try encoder.frame(Fixtures.data(scenario: "app-icon", file: "02-s2c-app-icon.bin"))
        bytes += try encoder.frame(Fixtures.data(scenario: "hierarchy", file: "02-s2c-hierarchy.bin"))
        for index in 0..<24 { bytes += try encoder.frame(chunks[index % chunks.count]) }
        bytes += encoder.trailer()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".cutaway")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let mapped = try Data(contentsOf: url, options: .alwaysMapped)

        let before = FrameCodec.copyCount
        let decoder = try ArchiveDecoder(mapped)
        let opened = FrameCodec.copyCount - before

        let offBoundary = decoder.frames.map { range in
            mapped.withUnsafeBytes {
                Int(bitPattern: $0.baseAddress! + (range.lowerBound - mapped.startIndex)) % 8 != 0
            }
        }
        XCTAssertTrue(offBoundary.contains(false), "no frame lies on a boundary to read in place")
        XCTAssertTrue(offBoundary.contains(true), "no frame lies off a boundary")
        // Every frame is checked once; frame 3 is looked at once more, to see whether it is the
        // Environment.
        let expected = offBoundary.filter(\.self).count + (offBoundary[3] ? 1 : 0)
        XCTAssertEqual(opened, expected)

        for index in 0..<decoder.chunkCount {
            guard case .layerDetailsChunk(let expected) = try FrameCodec.decode(chunks[index % 3]).body
            else {
                XCTFail("fixture \(index % 3) is not a chunk")
                return
            }
            let before = FrameCodec.copyCount
            let chunk = try decoder.chunk(at: index)
            XCTAssertEqual(
                FrameCodec.copyCount - before, offBoundary[3 + index] ? 1 : 0, "chunk \(index)")
            XCTAssertEqual(chunk, expected)
        }
    }
}
