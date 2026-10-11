import Darwin
import Foundation
import XCTest

/// Probes that an app that is not sandboxed can reach usbmuxd and is told when devices come
/// and go. Test-only code; the real client is `CutawayTransport`'s, and its `UsbmuxdCodec` is
/// the reference for the message format.
final class UsbmuxdProbeTests: XCTestCase {
    private static let socketPath = "/var/run/usbmuxd"
    private static let headerLength = 16

    private enum ProbeError: Error {
        case timedOut
        case closedByPeer
        case malformedMessage
    }

    private struct Message {
        var version: UInt32
        var type: UInt32
        var tag: UInt32
        var payload: [String: Any]
    }

    /// These probes talk to the real usbmuxd, so they run only on request: with xcodebuild,
    /// set TEST_RUNNER_CUTAWAY_REAL_USBMUXD=1.
    private func skipUnlessRequested() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CUTAWAY_REAL_USBMUXD"] == "1",
            "NOT RUN: talks to the real usbmuxd. Set TEST_RUNNER_CUTAWAY_REAL_USBMUXD=1 to run it.")
    }

    // Level a: needs no knowledge of the message format.
    func test_M0_H3_unsandboxedAppConnectsToTheUsbmuxdSocket() throws {
        try skipUnlessRequested()
        let descriptor = try Self.openSocket()
        close(descriptor)
    }

    // Level b.
    func test_M0_H3_usbmuxdAcceptsListen() throws {
        try skipUnlessRequested()
        let descriptor = try Self.openSocket()
        defer { close(descriptor) }

        try Self.sendListen(to: descriptor, tag: 7)
        let reply = try Self.receiveMessage(from: descriptor, deadline: Date().addingTimeInterval(5))

        XCTAssertEqual(reply.version, 1)
        XCTAssertEqual(reply.type, 8)
        XCTAssertEqual(reply.tag, 7, "the reply carries the request's tag")
        XCTAssertEqual(reply.payload["MessageType"] as? String, "Result")
        XCTAssertEqual(reply.payload["Number"] as? Int, 0)
    }

    // Level c: needs a person to plug a device in and out, so it only runs on request.
    func test_M0_H3_usbmuxdReportsAttachAndDetach() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CUTAWAY_USBMUXD_DEVICE"] == "1",
            "NOT VERIFIED: needs a USB device. Run with TEST_RUNNER_CUTAWAY_USBMUXD_DEVICE=1, "
                + "starting with the device unplugged; plug it in and unplug it when asked.")

        let descriptor = try Self.openSocket()
        defer { close(descriptor) }
        try Self.sendListen(to: descriptor, tag: 1)
        let reply = try Self.receiveMessage(from: descriptor, deadline: Date().addingTimeInterval(5))
        XCTAssertEqual(reply.payload["Number"] as? Int, 0)

        // Start with the device unplugged: a device that is already attached is reported right
        // after Listen, and that would not show that a live attach is notified.
        print("M0-H3: PLUG THE DEVICE IN NOW; waiting up to 60 s")
        let attached = try Self.waitForMessage(
            from: descriptor, timeout: 60
        ) { message in
            message["MessageType"] as? String == "Attached"
                && (message["Properties"] as? [String: Any])?["ConnectionType"] as? String == "USB"
        }
        let deviceID = try XCTUnwrap(attached["DeviceID"] as? Int)
        print("M0-H3: device \(deviceID) attached. UNPLUG IT NOW; waiting up to 60 s")

        let detached = try Self.waitForMessage(
            from: descriptor, timeout: 60
        ) { message in
            message["MessageType"] as? String == "Detached" && message["DeviceID"] as? Int == deviceID
        }
        XCTAssertEqual(detached["DeviceID"] as? Int, deviceID)
        print("M0-H3: device \(deviceID) detached")
    }

    // MARK: - Helpers

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private static func openSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw posixError() }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            precondition(path.count < buffer.count)
            buffer.copyBytes(from: path)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let error = posixError()
            close(descriptor)
            throw error
        }
        return descriptor
    }

    private static func sendListen(to descriptor: Int32, tag: UInt32) throws {
        let payload = try PropertyListSerialization.data(
            fromPropertyList: [
                "MessageType": "Listen",
                "ClientVersionString": "cutaway-m0-probe",
                "ProgName": "Cutaway",
            ],
            format: .xml, options: 0)

        var message = Data()
        for field in [UInt32(headerLength + payload.count), 1, 8, tag] {
            withUnsafeBytes(of: field.littleEndian) { message.append(contentsOf: $0) }
        }
        message.append(payload)

        var sent = 0
        while sent < message.count {
            let count = message.withUnsafeBytes {
                write(descriptor, $0.baseAddress! + sent, message.count - sent)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            sent += count
        }
    }

    private static func readExactly(_ count: Int, from descriptor: Int32, deadline: Date) throws -> Data {
        var data = Data(count: count)
        var received = 0
        while received < count {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw ProbeError.timedOut }

            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollDescriptor, 1, Int32(max(1, min(remaining, 1) * 1000)))
            if ready < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if ready == 0 { continue }

            let chunk = data.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress! + received, count - received)
            }
            if chunk == 0 { throw ProbeError.closedByPeer }
            if chunk < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            received += chunk
        }
        return data
    }

    private static func receiveMessage(from descriptor: Int32, deadline: Date) throws -> Message {
        let header = try readExactly(headerLength, from: descriptor, deadline: deadline)
        let fields = (0..<4).map { index in
            header.withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self))
            }
        }
        let length = Int(fields[0])
        guard length >= headerLength, length <= 1 << 20 else { throw ProbeError.malformedMessage }

        let body = try readExactly(length - headerLength, from: descriptor, deadline: deadline)
        guard
            let payload = try PropertyListSerialization.propertyList(from: body, format: nil)
            as? [String: Any]
        else { throw ProbeError.malformedMessage }
        return Message(version: fields[1], type: fields[2], tag: fields[3], payload: payload)
    }

    private static func waitForMessage(
        from descriptor: Int32,
        timeout: TimeInterval,
        where matches: ([String: Any]) -> Bool
    ) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let message = try receiveMessage(from: descriptor, deadline: deadline).payload
            if matches(message) { return message }
        }
    }
}
