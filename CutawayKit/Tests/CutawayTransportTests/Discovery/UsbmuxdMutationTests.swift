import CutawayTestSupport
import XCTest

@testable import CutawayTransport

/// C-WIRE-09 for usbmuxd: whatever bytes the socket delivers, reading them ends in a message
/// or a `UsbmuxdError`, never a crash.
final class UsbmuxdMutationTests: XCTestCase {
    private let settings = FuzzSettings.current(defaultIterations: 300)

    /// The messages FakeUsbmuxd sends, as whole packets with their headers.
    private let packets: [Data] = [
        UsbmuxdIncoming.result(0), .result(2), .result(3),
        .attached(deviceID: 4, serial: "00008030-001A", connectionType: "USB"),
        .detached(deviceID: 4), .other("Paired"),
    ].map { UsbmuxdCodec.encode($0, tag: 1) }

    /// Cuts every packet out of `pieces` and decodes it. Returns how many were decoded.
    @discardableResult
    private func read(_ pieces: [Data], _ context: @autoclosure () -> String) -> Int {
        var reader = UsbmuxdPacketReader()
        var decoded = 0
        for piece in pieces {
            reader.append(piece)
            while true {
                do {
                    guard let packet = try reader.next() else { break }
                    _ = try UsbmuxdCodec.decodeIncoming(packet.payload)
                    decoded += 1
                } catch {
                    XCTAssertTrue(error is UsbmuxdError, "\(context()) threw \(error)")
                    // The connection to usbmuxd is dropped on any such error.
                    return decoded
                }
            }
        }
        return decoded
    }

    func test_C_WIRE_09_everyUsbmuxdMessageSurvivesEveryMutation() {
        var decoded = 0
        for (number, packet) in packets.enumerated() {
            let mutations = Mutation.all(
                of: packet, randomCount: settings.iterations, seed: settings.seed)
            for mutation in mutations {
                decoded += read([mutation.applied(to: packet)], "packet \(number), \(mutation)")
            }
        }
        // Changes to the property list's values still decode.
        XCTAssertGreaterThan(decoded, 0)
    }

    func test_C_WIRE_09_randomStreamsNeverCrashTheUsbmuxdReader() {
        var generator = SeededGenerator(seed: settings.seed)
        for run in 0..<settings.iterations {
            // Real packets and random ones, mutated together, in random pieces.
            var stream = Data()
            for _ in 0..<Int.random(in: 1...5, using: &generator) {
                if Bool.random(using: &generator) {
                    stream += packets.randomElement(using: &generator)!
                } else {
                    stream += generator.randomPieces(
                        totalLength: Int.random(in: 1...64, using: &generator), longestPiece: 64
                    ).reduce(Data(), +)
                }
            }
            stream = Mutation.random(seed: settings.seed, index: run).applied(to: stream)
            var pieces: [Data] = []
            var cursor = stream.startIndex
            while cursor < stream.endIndex {
                let end = min(cursor + Int.random(in: 1...40, using: &generator), stream.endIndex)
                pieces.append(stream[cursor..<end])
                cursor = end
            }
            read(pieces, "stream \(run) of seed \(settings.seed)")
        }
    }
}
