import Foundation
import XCTest

@testable import CutawayTransport

/// What can be checked against the real usbmuxd without a device. These tests leave the test
/// double behind, so they run only on request: set CUTAWAY_REAL_USBMUXD=1.
final class RealUsbmuxdTests: XCTestCase {
    private func skipUnlessRequested() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CUTAWAY_REAL_USBMUXD"] == "1",
            "NOT RUN: talks to the real usbmuxd. Set CUTAWAY_REAL_USBMUXD=1 to run it.")
    }

    func test_C_CONN_02_theRealUsbmuxdAcceptsTheProductionListen() async throws {
        try skipUnlessRequested()
        let channel = try await ConnectionChannel.connect(
            unixSocketPath: Usbmuxd.defaultSocketPath, timeout: .seconds(2))
        defer { channel.close() }
        try await channel.send(UsbmuxdCodec.encode(.listen, tag: 9))

        var reader = UsbmuxdPacketReader()
        var packet: UsbmuxdPacket?
        while packet == nil {
            let bytes = try await channel.receive()
            reader.append(try XCTUnwrap(bytes))
            packet = try reader.next()
        }
        XCTAssertEqual(packet?.tag, 9)
        XCTAssertEqual(try UsbmuxdCodec.decodeIncoming(try XCTUnwrap(packet).payload), .result(0))
    }

    func test_C_CONN_02_theRealUsbmuxdRefusesConnectToAnUnknownDevice() async throws {
        try skipUnlessRequested()
        do {
            _ = try await Usbmuxd.connect(
                socketPath: Usbmuxd.defaultSocketPath, deviceID: 987_654, port: 48160,
                timeout: .seconds(2))
            XCTFail("usbmuxd accepted a Connect to a device that does not exist")
        } catch let error as UsbmuxdError {
            guard case .refused(let number) = error else {
                XCTFail("threw \(error)")
                return
            }
            XCTAssertNotEqual(number, 0)
            print("USBMUXD-MEASURED: Connect to an unknown device was answered with Result \(number)")
        }
    }
}
