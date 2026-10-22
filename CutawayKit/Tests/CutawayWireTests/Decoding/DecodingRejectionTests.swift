import CutawayTestSupport
import CutawayWire
import XCTest

/// C-WIRE-02, the rejection half: bytes that are not a valid frame are refused with an error.
final class DecodingRejectionTests: XCTestCase {
    private func hello() throws -> Data {
        try Fixtures.data(scenario: "handshake", file: "02-s2c-hello.bin")
    }

    func test_C_WIRE_02_wrongFileIdentifierIsRejected() throws {
        var payload = try hello()
        // Bytes 4..<8 of a plain FlatBuffer are the file identifier (P-FRAME-01).
        payload.replaceSubrange(4..<8, with: Data("XXXX".utf8))
        XCTAssertThrowsError(try FrameCodec.decode(payload)) { error in
            XCTAssertEqual(error as? FrameError, .wrongFileIdentifier)
        }
    }

    func test_C_WIRE_02_truncatedFramesNeverDecodeToSomethingElse() throws {
        let payload = try hello()
        let whole = try FrameCodec.decode(payload)
        // Every proper prefix, including the empty one, must either be refused or decode to
        // exactly the same frame. The second case exists because a FlatBuffer may end with
        // alignment padding that nothing refers to; losing only that padding loses nothing.
        for length in 0..<payload.count {
            do {
                let frame = try FrameCodec.decode(payload.prefix(length))
                XCTAssertEqual(frame, whole, "prefix of \(length) bytes")
                XCTAssertGreaterThan(
                    length, payload.count - 8,
                    "prefix of \(length) bytes was accepted but lost more than padding")
            } catch {
                XCTAssertTrue(error is FrameError, "prefix of \(length) bytes threw \(error)")
            }
        }
    }

    func test_C_WIRE_02_decodesASliceOfALargerBuffer() throws {
        let payload = try hello()
        // A slice keeps the indices of the buffer it was cut from.
        let padded = Data([0xAA, 0xBB, 0xCC]) + payload + Data([0xDD])
        let slice = padded[3..<(3 + payload.count)]
        XCTAssertEqual(slice.startIndex, 3)
        XCTAssertEqual(try FrameCodec.decode(slice), try FrameCodec.decode(payload))
    }

    func test_C_WIRE_02_decodesABufferThatStartsAtZeroOffAnAlignedAddress() throws {
        // An archive maps its file; a frame inside it may start on any byte. This buffer is not
        // a slice, so only its address tells that the decoder must copy it.
        let payload = try Fixtures.data(scenario: "app-icon", file: "02-s2c-app-icon.bin")
        let memory = UnsafeMutableRawPointer.allocate(byteCount: payload.count + 1, alignment: 8)
        defer { memory.deallocate() }
        payload.copyBytes(to: memory.advanced(by: 1).assumingMemoryBound(to: UInt8.self),
                          count: payload.count)
        let unaligned = Data(
            bytesNoCopy: memory.advanced(by: 1), count: payload.count, deallocator: .none)
        XCTAssertEqual(unaligned.startIndex, 0)
        XCTAssertEqual(try FrameCodec.decode(unaligned), try FrameCodec.decode(payload))
    }

    /// C-WIRE-08: a frame within the length limit is not refused for how many tables it holds
    /// (P-FRAME-06). The runtime's default limit is 1,000,000 tables; this frame has 1,000,002
    /// (the frame, the chunk and one per detail).
    func test_C_WIRE_08_aChunkWithAMillionDetailsPassesVerification() throws {
        let count: UInt64 = 1_000_000
        let details = (1...count).map {
            LayerDetail(layerID: $0, status: .ok, solo: nil, group: nil, attributeGroups: [])
        }
        let payload = FrameCodec.encode(
            Frame(requestID: 1, body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: details))))
        XCTAssertLessThanOrEqual(payload.count, FrameCodec.maximumFrameLength)

        let frame = try FrameCodec.decode(payload)
        guard case .layerDetailsChunk(let chunk) = frame.body else {
            XCTFail("decoded \(String(describing: frame.body))")
            return
        }
        XCTAssertEqual(chunk.details.count, Int(count))
        XCTAssertEqual(chunk.details.first?.layerID, 1)
        XCTAssertEqual(chunk.details.last?.layerID, count)
    }
}
