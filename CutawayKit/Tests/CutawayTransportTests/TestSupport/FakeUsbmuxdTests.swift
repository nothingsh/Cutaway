import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayTransport

/// C-MOCK-02: a fake usbmuxd on a temporary Unix socket.
final class FakeUsbmuxdTests: XCTestCase {
    /// Collects the first `count` device events, or fewer when `timeout` passes first.
    private func events(
        _ count: Int, from stream: AsyncStream<DeviceEvent>, within timeout: Duration = .seconds(2)
    ) async -> [DeviceEvent] {
        let collector = Task {
            var events: [DeviceEvent] = []
            for await event in stream {
                events.append(event)
                if events.count == count { break }
            }
            return events
        }
        let limit = Task {
            try await Task.sleep(for: timeout)
            collector.cancel()
        }
        let events = await collector.value
        limit.cancel()
        return events
    }

    func test_C_MOCK_02_listenReportsAttachedDevicesThenChanges() async throws {
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 1, serial: "SERIAL-A", ports: [:]))

        let stream = Usbmuxd.deviceEvents(socketPath: fake.socketPath, timeout: .seconds(2))
        let listening = await Harness.eventually { await fake.listenerCount == 1 }
        XCTAssertTrue(listening)
        await fake.attach(FakeDevice(deviceID: 2, serial: "SERIAL-B", ports: [:]))
        await fake.detach(deviceID: 1)

        let events = await events(3, from: stream)
        XCTAssertEqual(events, [
            .attached(deviceID: 1, serial: "SERIAL-A"),
            .attached(deviceID: 2, serial: "SERIAL-B"),
            .detached(deviceID: 1),
        ])
        await fake.stop()
    }

    func test_C_MOCK_02_devicesReachedOverTheNetworkAreNotReported() async throws {
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(
            deviceID: 1, serial: "WIFI", ports: [:], connectionType: "Network"))
        await fake.attach(FakeDevice(deviceID: 2, serial: "CABLE", ports: [:]))

        let stream = Usbmuxd.deviceEvents(socketPath: fake.socketPath, timeout: .seconds(2))
        let events = await events(1, from: stream)
        XCTAssertEqual(events, [.attached(deviceID: 2, serial: "CABLE")])
        await fake.stop()
    }

    func test_C_MOCK_02_connectIsForwardedToTheLocalPort() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 7, serial: "SERIAL", ports: [48160: server.port]))

        let channel = try await Usbmuxd.connect(
            socketPath: fake.socketPath, deviceID: 7, port: 48160, timeout: .seconds(2))
        let session = Session(channel: channel, client: Harness.client)
        let outcome = try await session.handshake()
        XCTAssertEqual(outcome, .ready(Harness.demoApp, negotiated: Version(major: 1, minor: 0)))

        let requests = await fake.connectRequests
        XCTAssertEqual(requests, [FakeUsbmuxd.ConnectRequest(deviceID: 7, port: 48160)])

        await session.close()
        await fake.stop()
        await server.stop()
    }

    func test_C_MOCK_02_connectToAnUnknownDeviceOrPortIsRefused() async throws {
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 7, serial: "SERIAL", ports: [:]))

        for (deviceID, expected) in [(99, 2), (7, 3)] {
            do {
                _ = try await Usbmuxd.connect(
                    socketPath: fake.socketPath, deviceID: deviceID, port: 48160,
                    timeout: .seconds(2))
                XCTFail("device \(deviceID) was connected")
            } catch {
                XCTAssertEqual(error as? UsbmuxdError, .refused(expected))
            }
        }
        await fake.stop()
    }

    func test_C_MOCK_02_bytesTheDeviceSendsFirstAreNotLost() async throws {
        // A busy app speaks first: its Error is on the wire as soon as the tunnel exists, and
        // may reach the client together with usbmuxd's Result.
        for round in 0..<10 {
            let server = try await MockServer.start(
                script: try .fixtures("busy", closesWhenDone: true))
            let fake = try await FakeUsbmuxd.start()
            await fake.attach(FakeDevice(deviceID: 1, serial: "S", ports: [48160: server.port]))

            let channel = try await Usbmuxd.connect(
                socketPath: fake.socketPath, deviceID: 1, port: 48160, timeout: .seconds(2))
            let session = Session(channel: channel, client: Harness.client)
            let outcome = try await session.handshake()
            XCTAssertEqual(outcome, .busy, "round \(round)")

            await fake.stop()
            await server.stop()
        }
    }

    func test_C_MOCK_02_detachingADeviceEndsItsTunnels() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 7, serial: "SERIAL", ports: [48160: server.port]))
        let channel = try await Usbmuxd.connect(
            socketPath: fake.socketPath, deviceID: 7, port: 48160, timeout: .seconds(2))
        let session = Session(channel: channel, client: Harness.client)
        _ = try await session.handshake()

        await fake.detach(deviceID: 7)

        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events.last, .closed)
        await fake.stop()
        await server.stop()
    }

    func test_C_MOCK_02_theSocketPathIsItsOwnTemporaryFile() async throws {
        let first = try await FakeUsbmuxd.start()
        let second = try await FakeUsbmuxd.start()
        XCTAssertNotEqual(first.socketPath, second.socketPath)
        XCTAssertNotEqual(first.socketPath, Usbmuxd.defaultSocketPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.socketPath))
        await first.stop()
        await second.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.socketPath))
    }
}
