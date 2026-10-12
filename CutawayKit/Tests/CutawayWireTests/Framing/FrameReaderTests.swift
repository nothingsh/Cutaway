import CutawayTestSupport
import CutawayWire
import XCTest

/// C-WIRE-02: cutting frames out of a byte stream.
final class FrameReaderTests: XCTestCase {
    /// Every (scenario, direction) that has a .stream file, with the payloads it must yield.
    private func streams() throws -> [(name: String, stream: Data, payloads: [Data])] {
        var result: [(name: String, stream: Data, payloads: [Data])] = []
        for scenario in try Fixtures.scenarios() {
            let frames = try Fixtures.frames(scenario: scenario)
            for direction in [FixtureFrame.Direction.clientToServer, .serverToClient] {
                guard let stream = try Fixtures.stream(scenario: scenario, direction: direction)
                else { continue }
                result.append((
                    name: "\(scenario)/\(direction.rawValue)", stream: stream,
                    payloads: frames.filter { $0.direction == direction }.map(\.payload)))
            }
        }
        return result
    }

    private func drain(_ reader: inout FrameReader) throws -> [Data] {
        var payloads: [Data] = []
        while let payload = try reader.nextPayload() {
            payloads.append(payload)
        }
        return payloads
    }

    func test_C_WIRE_02_wholeStreamsYieldTheFixtureFrames() throws {
        let all = try streams()
        XCTAssertEqual(all.count, 27)
        for entry in all {
            var reader = FrameReader()
            reader.append(entry.stream)
            XCTAssertEqual(try drain(&reader), entry.payloads, entry.name)
        }
    }

    func test_C_WIRE_02_everyTwoWaySplitYieldsTheSameFrames() throws {
        for entry in try streams() {
            for cut in 1..<entry.stream.count {
                var reader = FrameReader()
                reader.append(entry.stream.prefix(cut))
                var payloads = try drain(&reader)
                reader.append(entry.stream.suffix(from: cut))
                payloads += try drain(&reader)
                if payloads != entry.payloads {
                    XCTFail("\(entry.name) split at \(cut)")
                    return
                }
            }
        }
    }

    func test_C_WIRE_02_byteByByteYieldsTheSameFrames() throws {
        for entry in try streams() {
            var reader = FrameReader()
            var payloads: [Data] = []
            for byte in entry.stream {
                reader.append(Data([byte]))
                payloads += try drain(&reader)
            }
            XCTAssertEqual(payloads, entry.payloads, entry.name)
        }
    }

    func test_C_WIRE_02_lengthOverTheMaximumIsRejected() {
        var reader = FrameReader()
        // 268435457 = 0x10000001, little-endian.
        reader.append(Data([0x01, 0x00, 0x00, 0x10]))
        XCTAssertThrowsError(try reader.nextPayload()) { error in
            XCTAssertEqual(error as? FrameError, .tooLarge(length: 268_435_457))
        }
    }

    func test_C_WIRE_02_readerStaysFailedAfterAnOversizedLength() throws {
        var reader = FrameReader()
        reader.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertThrowsError(try reader.nextPayload())
        // More bytes, even a valid frame, must not bring it back to life.
        reader.append(try XCTUnwrap(
            try Fixtures.stream(scenario: "handshake", direction: .serverToClient)))
        XCTAssertThrowsError(try reader.nextPayload()) { error in
            XCTAssertEqual(error as? FrameError, .tooLarge(length: 4_294_967_295))
        }
    }

    func test_C_WIRE_02_maximumLengthIsNotAnError() throws {
        var reader = FrameReader()
        // 268435456 = 0x10000000: allowed. The payload has not arrived, so there is no frame yet.
        reader.append(Data([0x00, 0x00, 0x00, 0x10]))
        XCTAssertNil(try reader.nextPayload())
    }

    func test_C_WIRE_02_zeroLengthFrameIsDeliveredAsAnEmptyPayload() throws {
        var reader = FrameReader()
        reader.append(Data([0x00, 0x00, 0x00, 0x00]))
        let payload = try XCTUnwrap(try reader.nextPayload())
        XCTAssertTrue(payload.isEmpty)
        XCTAssertNil(try reader.nextPayload())
        // The empty payload is not a frame: the decoder refuses it.
        XCTAssertThrowsError(try FrameCodec.decode(payload))
    }

    func test_C_WIRE_02_incompleteLengthYieldsNothing() throws {
        var reader = FrameReader()
        XCTAssertNil(try reader.nextPayload())
        reader.append(Data([0x10, 0x00, 0x00]))
        XCTAssertNil(try reader.nextPayload())
    }

    /// Feeds `stream` in pieces of the sizes `nextSize` gives, draining after each.
    private func read(
        _ stream: Data, in nextSize: (Int) -> Int
    ) throws -> [Data] {
        var reader = FrameReader()
        var payloads: [Data] = []
        var at = stream.startIndex
        while at < stream.endIndex {
            let end = min(at + nextSize(stream.endIndex - at), stream.endIndex)
            reader.append(stream[at..<end])
            payloads += try drain(&reader)
            at = end
        }
        return payloads
    }

    func test_C_WIRE_02_randomSplitsOfAllStreamsInARowYieldTheSameFrames() throws {
        // Every stream one after another, so that pieces end and start frames anywhere and
        // often hold several frames, or the end of one and the start of the next.
        let all = try streams()
        let stream = all.reduce(Data()) { $0 + $1.stream }
        let expected = all.flatMap(\.payloads)
        for seed in UInt64(1)...20 {
            var generator = SeededGenerator(seed: seed)
            let maximum = [3, 40, 600, 5000][Int(seed) % 4]
            let payloads = try read(stream) { _ in Int.random(in: 1...maximum, using: &generator) }
            XCTAssertEqual(payloads, expected, "seed \(seed)")
        }
    }

    func test_C_WIRE_02_aLargeFrameBetweenSmallOnesArrivesWholeInAnyPieces() throws {
        // 32 MiB, with a small frame on either side sharing its first and last pieces.
        // A pattern whose length is no power of two, so a piece put in the wrong place shows.
        let pattern = Data((0..<1_048_583).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ $0 >> 13) })
        var large = Data(capacity: 32 * pattern.count)
        for _ in 0..<32 { large.append(pattern) }
        let small = Data("before".utf8)
        let after = Data("after".utf8)
        var stream = Data()
        for payload in [small, large, after] {
            withUnsafeBytes(of: UInt32(payload.count).littleEndian) { stream.append(contentsOf: $0) }
            stream.append(payload)
        }
        for size in [65536, 65537, 1_000_003] {
            let payloads = try read(stream) { _ in size }
            XCTAssertEqual(payloads.count, 3, "pieces of \(size)")
            XCTAssertEqual(payloads.first, small)
            XCTAssertTrue(payloads.dropFirst().first == large, "pieces of \(size)")
            XCTAssertEqual(payloads.last, after)
        }
    }

    func test_C_WIRE_02_payloadsStartAtIndexZeroAndAreAligned() throws {
        // Whole in one piece, and spread over many, from a slice that does not start at 0:
        // either way the decoder can read the payload where it is.
        let stream = try XCTUnwrap(
            try Fixtures.stream(scenario: "layer-details", direction: .serverToClient))
        let padded = Data([0xEE]) + stream
        for size in [stream.count, 7] {
            let payloads = try read(padded[1...]) { _ in size }
            XCTAssertFalse(payloads.isEmpty)
            for payload in payloads {
                XCTAssertEqual(payload.startIndex, 0)
                payload.withUnsafeBytes { bytes in
                    XCTAssertEqual(Int(bitPattern: bytes.baseAddress) % 8, 0)
                }
            }
        }
    }
}
