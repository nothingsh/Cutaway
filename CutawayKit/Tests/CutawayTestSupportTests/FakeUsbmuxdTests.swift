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
}
