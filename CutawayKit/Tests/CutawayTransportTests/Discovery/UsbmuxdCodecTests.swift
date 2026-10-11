import Foundation
import XCTest

@testable import CutawayTransport

/// The usbmuxd messages, checked byte by byte where usbmuxd's published description of them is
/// that precise.
final class UsbmuxdCodecTests: XCTestCase {
    private func header(_ packet: Data) -> [UInt32] {
        (0..<4).map { index in
            packet.withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self))
            }
        }
    }

    private func dictionary(_ packet: Data) throws -> NSDictionary {
        let payload = packet.dropFirst(16)
        return try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: Data(payload), format: nil)
                as? NSDictionary)
    }

    func test_C_CONN_02_listenIsEncodedAsDocumented() throws {
        let packet = UsbmuxdCodec.encode(.listen, tag: 7)
        // length (whole message), version 1, type 8 (plist), tag.
        XCTAssertEqual(header(packet), [UInt32(packet.count), 1, 8, 7])
        XCTAssertEqual(
            try dictionary(packet),
            ["MessageType": "Listen", "ClientVersionString": "cutaway", "ProgName": "Cutaway"])
        // The payload is an XML property list.
        XCTAssertEqual(String(bytes: packet.dropFirst(16).prefix(5), encoding: .utf8), "<?xml")
    }

    func test_C_CONN_02_connectCarriesThePortInNetworkByteOrder() throws {
        let packet = UsbmuxdCodec.encode(.connect(deviceID: 12, port: 48160), tag: 3)
        XCTAssertEqual(header(packet), [UInt32(packet.count), 1, 8, 3])
        XCTAssertEqual(
            try dictionary(packet),
            [
                "MessageType": "Connect", "DeviceID": 12, "PortNumber": 8380,
                "ClientVersionString": "cutaway", "ProgName": "Cutaway",
            ])
    }

    func test_C_CONN_02_requestsRoundTrip() throws {
        for request in [UsbmuxdRequest.listen, .connect(deviceID: 5, port: 48167)] {
            let packet = UsbmuxdCodec.encode(request, tag: 1)
            XCTAssertEqual(try UsbmuxdCodec.decodeRequest(Data(packet.dropFirst(16))), request)
        }
    }

    func test_C_CONN_02_incomingMessagesRoundTrip() throws {
        let messages: [UsbmuxdIncoming] = [
            .result(0), .result(3),
            .attached(deviceID: 4, serial: "00008030-001A", connectionType: "USB"),
            .attached(deviceID: 9, serial: "00008030-001B", connectionType: "Network"),
            .detached(deviceID: 4),
            .other("Paired"),
        ]
        for message in messages {
            let packet = UsbmuxdCodec.encode(message, tag: 0)
            XCTAssertEqual(try UsbmuxdCodec.decodeIncoming(Data(packet.dropFirst(16))), message)
        }
    }

    func test_C_CONN_02_aPayloadThatIsNotADictionaryIsMalformed() {
        XCTAssertThrowsError(try UsbmuxdCodec.decodeIncoming(Data("garbage".utf8))) { error in
            guard case .malformed = error as? UsbmuxdError else { return XCTFail("threw \(error)") }
        }
        XCTAssertThrowsError(try UsbmuxdCodec.decodeRequest(Data())) { error in
            guard case .malformed = error as? UsbmuxdError else { return XCTFail("threw \(error)") }
        }
    }

    func test_C_CONN_02_readerCutsPacketsOutOfAnyChunking() throws {
        let first = UsbmuxdCodec.encode(.result(0), tag: 1)
        let second = UsbmuxdCodec.encode(.detached(deviceID: 2), tag: 0)
        let stream = first + second
        for cut in 1..<stream.count {
            var reader = UsbmuxdPacketReader()
            var packets: [UsbmuxdPacket] = []
            for piece in [stream.prefix(cut), stream.suffix(from: cut)] {
                reader.append(piece)
                while let packet = try reader.next() { packets.append(packet) }
            }
            XCTAssertEqual(packets.map(\.tag), [1, 0], "split at \(cut)")
            XCTAssertEqual(try UsbmuxdCodec.decodeIncoming(packets[0].payload), .result(0))
            XCTAssertEqual(try UsbmuxdCodec.decodeIncoming(packets[1].payload), .detached(deviceID: 2))
        }
    }

    func test_C_CONN_02_readerRejectsBadHeaders() {
        func reader(_ fields: [UInt32]) -> UsbmuxdPacketReader {
            var reader = UsbmuxdPacketReader()
            var bytes = Data()
            for field in fields { withUnsafeBytes(of: field.littleEndian) { bytes.append(contentsOf: $0) } }
            reader.append(bytes)
            return reader
        }
        var tooShort = reader([15, 1, 8, 0])
        XCTAssertThrowsError(try tooShort.next())
        var tooLong = reader([UInt32(UsbmuxdCodec.maximumLength + 1), 1, 8, 0])
        XCTAssertThrowsError(try tooLong.next())
        var wrongVersion = reader([16, 0, 8, 0])
        XCTAssertThrowsError(try wrongVersion.next())
        var wrongType = reader([16, 1, 3, 0])
        XCTAssertThrowsError(try wrongType.next())
    }

    func test_C_CONN_02_readerHandsBackTheBytesAfterAPacket() throws {
        var reader = UsbmuxdPacketReader()
        reader.append(UsbmuxdCodec.encode(.result(0), tag: 1) + Data([0xAA, 0xBB]))
        XCTAssertNotNil(try reader.next())
        XCTAssertEqual(reader.takeRemainder(), Data([0xAA, 0xBB]))
        XCTAssertEqual(reader.takeRemainder(), Data())
    }
}
