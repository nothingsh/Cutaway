import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-CONN-02: apps on USB devices, against the fake usbmuxd, so that the discovery is tested
/// without a device; real devices are a person's to try.
final class DeviceDiscoveryTests: XCTestCase {
    private func configuration(
        fake: FakeUsbmuxd?, devicePorts: [UInt16] = [48160], simulatorPorts: [UInt16] = [],
        socketPath: String? = nil, requestTimeout: Duration = .seconds(1)
    ) -> DiscoveryConfiguration {
        DiscoveryConfiguration(
            client: Harness.client, simulatorPorts: simulatorPorts, devicePorts: devicePorts,
            usbmuxdSocketPath: socketPath ?? fake?.socketPath, scanInterval: .milliseconds(50),
            connectTimeout: .seconds(1), requestTimeout: requestTimeout)
    }

    func test_C_CONN_02_findsAnAppOnAnAttachedDeviceAndLosesItOnDetach() async throws {
        let app = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        let discovery = Discovery(configuration: configuration(fake: fake))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let listening = await Harness.eventually { await fake.listenerCount == 1 }
        XCTAssertTrue(listening)

        await fake.attach(FakeDevice(deviceID: 7, serial: "SERIAL-7", ports: [48160: app.port]))

        let location = AppLocation.device(serial: "SERIAL-7", port: 48160)
        let found = await Harness.eventually { await recorder.seen.contains(.found(location, Harness.demoApp)) }
        XCTAssertTrue(found)
        // The client reached it by asking usbmuxd for that device and port.
        let requests = await fake.connectRequests
        XCTAssertEqual(requests.first, FakeUsbmuxd.ConnectRequest(deviceID: 7, port: 48160))

        await fake.detach(deviceID: 7)

        let lost = await Harness.eventually { await recorder.seen.contains(.lost(location)) }
        XCTAssertTrue(lost)
        // Gone for good: not found again while the device stays away.
        try await Task.sleep(for: .milliseconds(200))
        let seen = await recorder.seen
        XCTAssertEqual(seen.last, .lost(location))
        XCTAssertEqual(seen.filter { $0 == .lost(location) }.count, 1)

        await discovery.stop()
        await fake.stop()
        await app.stop()
    }

    func test_C_CONN_02_aDeviceAttachedBeforeDiscoveryStartsIsFound() async throws {
        let app = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 3, serial: "EARLY", ports: [48160: app.port]))

        let discovery = Discovery(configuration: configuration(fake: fake))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let location = AppLocation.device(serial: "EARLY", port: 48160)
        let found = await Harness.eventually { await recorder.seen.contains(.found(location, Harness.demoApp)) }
        XCTAssertTrue(found)

        await discovery.stop()
        await fake.stop()
        await app.stop()
    }

    func test_C_CONN_02_onlyThePortsThatAnswerAreListed() async throws {
        let app = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        // Of the two ports the client tries, only 48161 has an app.
        await fake.attach(FakeDevice(deviceID: 1, serial: "S", ports: [48161: app.port]))
        let discovery = Discovery(configuration: configuration(fake: fake, devicePorts: [48160, 48161]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let found = await Harness.eventually {
            await recorder.seen.contains(.found(.device(serial: "S", port: 48161), Harness.demoApp))
        }
        XCTAssertTrue(found)
        let bothTried = await Harness.eventually {
            await Set(fake.connectRequests.map(\.port)) == [48160, 48161]
        }
        XCTAssertTrue(bothTried)
        let founds = await recorder.seen.filter {
            if case .found = $0 { return true }
            return false
        }
        XCTAssertEqual(founds, [.found(.device(serial: "S", port: 48161), Harness.demoApp)])

        await discovery.stop()
        await fake.stop()
        await app.stop()
    }

    func test_C_CONN_02_appsOnTwoDevicesAreToldApart() async throws {
        let first = try await MockServer.start(script: try .fixtures("handshake"))
        let second = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 1, serial: "A", ports: [48160: first.port]))
        await fake.attach(FakeDevice(deviceID: 2, serial: "B", ports: [48160: second.port]))
        let discovery = Discovery(configuration: configuration(fake: fake))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let both = await Harness.eventually {
            let seen = await recorder.seen
            return seen.contains(.found(.device(serial: "A", port: 48160), Harness.demoApp))
                && seen.contains(.found(.device(serial: "B", port: 48160), Harness.demoApp))
        }
        XCTAssertTrue(both)

        // Unplugging one leaves the other.
        await fake.detach(deviceID: 1)
        let lost = await Harness.eventually {
            await recorder.seen.contains(.lost(.device(serial: "A", port: 48160)))
        }
        XCTAssertTrue(lost)
        let otherLost = await recorder.seen.contains(.lost(.device(serial: "B", port: 48160)))
        XCTAssertFalse(otherLost)

        await discovery.stop()
        await fake.stop()
        await first.stop()
        await second.stop()
    }

    func test_C_CONN_02_aProbeThatFinishesAfterTheDeviceLeftReportsNothing() async throws {
        // The app answers the Hello only when the test lets it; the device leaves before that.
        let gate = MockGate()
        var hello = try MockScript.fixtures("handshake").steps
        hello.insert(.hold(gate), at: 1)
        let app = try await MockServer.start(script: MockScript(steps: hello))
        let other = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        // Long enough that the held handshake cannot time out first: the test must reach the
        // check for the device, not a timeout.
        let discovery = Discovery(configuration: configuration(fake: fake, requestTimeout: .seconds(10)))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let listening = await Harness.eventually { await fake.listenerCount == 1 }
        XCTAssertTrue(listening)

        await fake.attach(FakeDevice(deviceID: 1, serial: "S", ports: [48160: app.port]))
        let asked = await Harness.eventually { await app.receivedFrames.count == 1 }
        XCTAssertTrue(asked, "the probe's Hello did not arrive")
        // The tunnel is left open, so the probe's handshake completes after the device is
        // gone. Nothing may be reported for it: no later event would ever take it back.
        await fake.detach(deviceID: 1, closingTunnels: false)
        // Device messages are handled in order: once T is found, the detach has been handled.
        await fake.attach(FakeDevice(deviceID: 2, serial: "T", ports: [48160: other.port]))
        let t = AppLocation.device(serial: "T", port: 48160)
        let foundT = await Harness.eventually { await recorder.seen.contains(.found(t, Harness.demoApp)) }
        XCTAssertTrue(foundT)

        await gate.open()
        // The probe finished and closed its connection.
        let closed = await Harness.eventually { await app.clientCloseCount == 1 }
        XCTAssertTrue(closed, "the probe's connection was not closed")
        let seen = await recorder.seen
        XCTAssertFalse(seen.contains { event in
            if case .found(.device(serial: "S", port: _), _) = event { return true }
            if case .incompatible(.device(serial: "S", port: _), _, _, _) = event { return true }
            return false
        }, "the probe reported an app on a device that left: \(seen)")

        await discovery.stop()
        await fake.stop()
        await app.stop()
        await other.stop()
    }

    func test_C_CONN_02_aDeviceMessageThatCannotBeReadIsSkipped() async throws {
        let first = try await MockServer.start(script: try .fixtures("handshake"))
        let second = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        let discovery = Discovery(configuration: configuration(fake: fake))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let listening = await Harness.eventually { await fake.listenerCount == 1 }
        XCTAssertTrue(listening)

        await fake.attach(FakeDevice(deviceID: 1, serial: "S", ports: [48160: first.port]))
        let s = AppLocation.device(serial: "S", port: 48160)
        let foundS = await Harness.eventually { await recorder.seen.contains(.found(s, Harness.demoApp)) }
        XCTAssertTrue(foundS)

        // An Attached without its SerialNumber.
        await fake.sendToListeners(raw: UsbmuxdCodec.packet([
            "MessageType": "Attached",
            "DeviceID": 9,
            "Properties": ["ConnectionType": "USB", "DeviceID": 9] as [String: Any],
        ], tag: 0))
        // Messages on the listening connection are handled in order: once T is found, the
        // bad message before it has been handled too.
        await fake.attach(FakeDevice(deviceID: 2, serial: "T", ports: [48160: second.port]))
        let t = AppLocation.device(serial: "T", port: 48160)
        let foundT = await Harness.eventually { await recorder.seen.contains(.found(t, Harness.demoApp)) }
        XCTAssertTrue(foundT)

        let seen = await recorder.seen
        XCTAssertFalse(seen.contains(.lost(s)), "the bad message dropped the device list: \(seen)")
        XCTAssertEqual(seen.filter { $0 == .found(s, Harness.demoApp) }.count, 1)

        await discovery.stop()
        await fake.stop()
        await first.stop()
        await second.stop()
    }

    /// Bytes that are not a usbmuxd message at all end the listening connection, which is
    /// made again; the devices come back with it (the packet reader has a test of its own for
    /// the broken header).
    func test_C_CONN_02_aBrokenHeaderEndsTheListeningConnectionWhichIsMadeAgain() async throws {
        let app = try await MockServer.start(script: try .fixtures("handshake"))
        let fake = try await FakeUsbmuxd.start()
        let discovery = Discovery(configuration: configuration(fake: fake))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let listening = await Harness.eventually { await fake.listenerCount == 1 }
        XCTAssertTrue(listening)
        await fake.attach(FakeDevice(deviceID: 1, serial: "S", ports: [48160: app.port]))
        let s = AppLocation.device(serial: "S", port: 48160)
        let found = await Harness.eventually { await recorder.seen.contains(.found(s, Harness.demoApp)) }
        XCTAssertTrue(found)

        // A header whose length is shorter than a header.
        var broken = Data()
        for field: UInt32 in [4, 1, 8, 0] {
            withUnsafeBytes(of: field.littleEndian) { broken.append(contentsOf: $0) }
        }
        await fake.sendToListeners(raw: broken)

        let again = await Harness.eventually(within: .seconds(5)) {
            await recorder.seen.filter { $0 == .found(s, Harness.demoApp) }.count == 2
        }
        let seen = await recorder.seen
        XCTAssertTrue(again, "listening again, the device is found again: \(seen)")
        XCTAssertTrue(seen.contains(.lost(s)), "the connection ended, and its devices with it")

        await discovery.stop()
        await fake.stop()
        await app.stop()
    }

    func test_C_CONN_02_aMissingUsbmuxdDoesNotStopSimulatorDiscovery() async throws {
        let app = try await MockServer.start(script: try .fixtures("handshake"))
        let discovery = Discovery(configuration: configuration(
            fake: nil, simulatorPorts: [app.port],
            socketPath: NSTemporaryDirectory() + "cutaway-no-such-usbmuxd.sock"))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let found = await Harness.eventually {
            await recorder.seen.contains(.found(.simulator(port: app.port), Harness.demoApp))
        }
        XCTAssertTrue(found)

        await discovery.stop()
        await app.stop()
    }

    func test_C_CONN_02_devicesAreFoundAgainAfterUsbmuxdRestarts() async throws {
        let app = try await MockServer.start(script: try .fixtures("handshake"))
        let location = AppLocation.device(serial: "S", port: 48160)

        var fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 1, serial: "S", ports: [48160: app.port]))
        // The path the client keeps using across the restarts.
        let path = fake.socketPath
        let discovery = Discovery(configuration: configuration(fake: fake))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let found = await Harness.eventually { await recorder.seen.contains(.found(location, Harness.demoApp)) }
        XCTAssertTrue(found)

        // usbmuxd numbers devices afresh when it restarts, so the same device comes back
        // under another ID. The old IDs have to be forgotten, or the next Connect would name
        // a device that is not there.
        for restart in 1...3 {
            await fake.stop()
            let lost = await Harness.eventually {
                await recorder.seen.filter { $0 == .lost(location) }.count == restart
            }
            XCTAssertTrue(lost, "restart \(restart): the app was not lost")

            fake = try await FakeUsbmuxd.start(socketPath: path)
            await fake.attach(FakeDevice(
                deviceID: 1 + restart * 10, serial: "S", ports: [48160: app.port]))
            let foundAgain = await Harness.eventually(within: .seconds(3)) {
                await recorder.seen.filter { $0 == .found(location, Harness.demoApp) }.count
                    == restart + 1
            }
            XCTAssertTrue(foundAgain, "restart \(restart): the app was not found again")
        }

        await discovery.stop()
        await fake.stop()
        await app.stop()
    }

    func test_C_CONN_02_anIncompatibleAppOnADeviceIsLostWhenTheDeviceLeaves() async throws {
        // An incompatible app holds no connection, so nothing closes when its device leaves;
        // discovery has to drop it on the detach itself.
        let app = try await MockServer.start(
            script: try .fixtures("handshake-version-mismatch", closesWhenDone: true))
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 4, serial: "OLD", ports: [48160: app.port]))
        var settings = configuration(fake: fake)
        settings.protocolVersion = Version(major: 1, minor: 0)
        let discovery = Discovery(configuration: settings)
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let location = AppLocation.device(serial: "OLD", port: 48160)
        let listed = await Harness.eventually {
            await recorder.seen.contains(.incompatible(
                location, Harness.demoApp, local: Version(major: 1, minor: 0),
                remote: Version(major: 0, minor: 5)))
        }
        XCTAssertTrue(listed)

        await fake.detach(deviceID: 4)

        let lost = await Harness.eventually { await recorder.seen.last == .lost(location) }
        XCTAssertTrue(lost)
        await discovery.stop()
        await fake.stop()
        await app.stop()
    }

    func test_C_CONN_02_anIncompatibleAppOnADeviceIsLostWhenUsbmuxdGoesAway() async throws {
        let app = try await MockServer.start(
            script: try .fixtures("handshake-version-mismatch", closesWhenDone: true))
        let fake = try await FakeUsbmuxd.start()
        await fake.attach(FakeDevice(deviceID: 4, serial: "OLD", ports: [48160: app.port]))
        var settings = configuration(fake: fake)
        settings.protocolVersion = Version(major: 1, minor: 0)
        let discovery = Discovery(configuration: settings)
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let location = AppLocation.device(serial: "OLD", port: 48160)
        let listed = await Harness.eventually {
            await recorder.seen.contains { event in
                if case .incompatible(location, _, _, _) = event { return true }
                return false
            }
        }
        XCTAssertTrue(listed)

        await fake.stop()

        let lost = await Harness.eventually { await recorder.seen.last == .lost(location) }
        XCTAssertTrue(lost)
        await discovery.stop()
        await app.stop()
    }
}
