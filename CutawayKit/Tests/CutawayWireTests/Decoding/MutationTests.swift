import CutawayTestSupport
import CutawayWire
import XCTest

/// C-WIRE-09: whatever bytes arrive, reading them ends in a value or an error, never a crash.
/// A crash ends the test process, so a run that finishes has survived every input; what is
/// checked here is that each error is of the kind the reader promises.
final class MutationTests: XCTestCase {
    private let settings = FuzzSettings.current(defaultIterations: 300)

    /// The frames a server sends in every scenario.
    private func serverFrames() throws -> [FixtureFrame] {
        try Fixtures.scenarios().flatMap { try Fixtures.frames(scenario: $0) }
            .filter { $0.direction == .serverToClient }
    }

    /// Decodes the bytes and, when they decode, every image in them: the images are read
    /// further only after the frame is, so a frame that decodes must not carry an image that
    /// crashes the decompression.
    private func read(_ payload: Data, _ context: @autoclosure () -> String) {
        let frame: Frame
        do {
            frame = try FrameCodec.decode(payload)
        } catch {
            XCTAssertTrue(error is FrameError, "\(context()) threw \(error)")
            return
        }
        for image in Self.images(in: frame) {
            do {
                _ = try image.decoded()
            } catch {
                XCTAssertTrue(error is ImageError, "\(context()): an image threw \(error)")
            }
        }
    }

    private static func images(in frame: Frame) -> [EncodedImage] {
        switch frame.body {
        case .appIcon(let icon): [icon.image].compactMap { $0 }
        case .layerDetailsChunk(let chunk):
            chunk.details.flatMap { [$0.solo, $0.group].compactMap { $0 } }
        default: []
        }
    }

    func test_C_WIRE_09_theSameSeedGivesTheSameMutations() {
        // No byte is 0x00 or 0xFF, nor the complement of either: each takes three new values.
        let bytes = Data((1...64).map { UInt8($0) })
        let first = Mutation.all(of: bytes, randomCount: 50, seed: 7)
        let second = Mutation.all(of: bytes, randomCount: 50, seed: 7)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map { $0.applied(to: bytes) }, second.map { $0.applied(to: bytes) })
        // Every truncation, three values for each byte, then the random ones.
        XCTAssertEqual(first.count, 64 + 64 * 3 + 50)
        let other = Mutation.all(of: bytes, randomCount: 50, seed: 8).suffix(50)
        XCTAssertNotEqual(
            other.map { $0.applied(to: bytes) }, first.suffix(50).map { $0.applied(to: bytes) })
    }

    func test_C_WIRE_09_everyFixtureFrameSurvivesEveryMutation() throws {
        let frames = try serverFrames()
        XCTAssertGreaterThanOrEqual(frames.count, 30)
        var decoded = 0
        var total = 0
        for frame in frames {
            for mutation in Mutation.all(
                of: frame.payload, randomCount: settings.iterations, seed: settings.seed)
            {
                let payload = mutation.applied(to: frame.payload)
                if (try? FrameCodec.decode(payload)) != nil { decoded += 1 }
                read(payload, "\(frame.scenario)/\(frame.fileName), \(mutation)")
                total += 1
            }
        }
        // Some of the mutations only change values and still pass verification: those are the
        // inputs that reach the conversion to value types and the images.
        XCTAssertGreaterThan(decoded, total / 100, "\(decoded) of \(total) decoded")
    }

    func test_C_WIRE_09_randomStreamsNeverCrashTheFrameReader() throws {
        let frames = try serverFrames().map(\.payload)
        var generator = SeededGenerator(seed: settings.seed)
        var payloads = 0
        for run in 0..<settings.iterations {
            // Real frames, frames with random bodies and lengths, and now and then a length
            // over the limit, all mutated together and handed over in random pieces.
            var stream = Data()
            for _ in 0..<Int.random(in: 1...6, using: &generator) {
                let body: Data
                switch Int.random(in: 0..<4, using: &generator) {
                case 0, 1: body = frames.randomElement(using: &generator)!
                default:
                    body = Data((0..<Int.random(in: 0...512, using: &generator)).map { _ in
                        UInt8.random(in: 0...255, using: &generator)
                    })
                }
                var length = UInt32(body.count)
                if Int.random(in: 0..<20, using: &generator) == 0 {
                    length = UInt32.random(in: 268_435_457...UInt32.max, using: &generator)
                } else if Int.random(in: 0..<5, using: &generator) == 0 {
                    length = UInt32.random(in: 0...1024, using: &generator)
                }
                stream += withUnsafeBytes(of: length.littleEndian) { Data($0) } + body
            }
            stream = Mutation.random(seed: settings.seed, index: run).applied(to: stream)

            var reader = FrameReader()
            var cursor = stream.startIndex
            reading: while cursor < stream.endIndex {
                let end = min(cursor + Int.random(in: 1...700, using: &generator), stream.endIndex)
                reader.append(stream[cursor..<end])
                cursor = end
                while true {
                    do {
                        guard let payload = try reader.nextPayload() else { break }
                        payloads += 1
                        read(payload, "stream \(run) of seed \(settings.seed)")
                    } catch {
                        XCTAssertTrue(
                            error is FrameError,
                            "stream \(run) of seed \(settings.seed) threw \(error)")
                        break reading
                    }
                }
            }
        }
        XCTAssertGreaterThan(payloads, settings.iterations / 2, "payloads cut out of the streams")
    }

    func test_C_WIRE_09_mutatedArchivesAreReadOrRefused() throws {
        let archive = try Fixtures.archive()
        let mutations = Mutation.all(
            of: archive, randomCount: settings.iterations, seed: settings.seed)
        var opened = 0
        for mutation in mutations {
            let bytes = mutation.applied(to: archive)
            let decoder: ArchiveDecoder
            do {
                decoder = try ArchiveDecoder(bytes)
            } catch {
                continue  // Typed: only an ArchiveError can come out.
            }
            opened += 1
            for index in 0..<decoder.chunkCount {
                for result in [
                    Result { try decoder.chunk(at: index).details.count },
                    Result { try decoder.layers(inChunk: index).count },
                ] {
                    if case .failure(let error) = result {
                        XCTAssertTrue(
                            error is ArchiveError || error is FrameError,
                            "\(mutation), chunk \(index) threw \(error)")
                    }
                }
                for detail in (try? decoder.chunk(at: index).details) ?? [] {
                    for image in [detail.solo, detail.group].compactMap({ $0 }) {
                        do {
                            _ = try image.decoded()
                        } catch {
                            XCTAssertTrue(
                                error is ImageError, "\(mutation): an image threw \(error)")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(opened, 0)
    }

    func test_C_WIRE_09_aRowOutsideTheBitmapIsNil() {
        let bitmap = Bitmap(
            pixelWidth: 2, pixelHeight: 2, bytesPerRow: 12, scale: 1,
            pixels: Data(repeating: 0xAB, count: 24))
        XCTAssertEqual(bitmap.row(1), Data(repeating: 0xAB, count: 8))
        XCTAssertNil(bitmap.row(2))
        XCTAssertNil(bitmap.row(-1))
        // The initializer checks nothing: pixels too short for the rows it claims.
        let short = Bitmap(
            pixelWidth: 2, pixelHeight: 2, bytesPerRow: 12, scale: 1,
            pixels: Data(repeating: 0, count: 16))
        XCTAssertNotNil(short.row(0))
        XCTAssertNil(short.row(1))
        let huge = Bitmap(
            pixelWidth: Int.max / 2, pixelHeight: 2, bytesPerRow: Int.max, scale: 1,
            pixels: Data(count: 4))
        XCTAssertNil(huge.row(1))
        XCTAssertNil(huge.row(0))
    }

    func test_C_WIRE_09_aChunkIndexOutsideTheArchiveThrows() throws {
        let decoder = try ArchiveDecoder(try Fixtures.archive())
        for index in [-1, decoder.chunkCount, Int.max] {
            XCTAssertThrowsError(try decoder.chunk(at: index)) { error in
                XCTAssertEqual(error as? ArchiveError, .noSuchChunk(index))
            }
            XCTAssertThrowsError(try decoder.layers(inChunk: index)) { error in
                XCTAssertEqual(error as? ArchiveError, .noSuchChunk(index))
            }
        }
    }
}
