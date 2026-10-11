import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// Discovery of apps on local ports: C-CONN-01, C-CONN-07, C-CONN-08, C-CONN-09, and the
/// discovery side of C-LIST-02.
final class DiscoveryTests: XCTestCase {
    /// A configuration that scans the given local ports every 50 ms and ignores devices.
    private func configuration(
        ports: [UInt16], protocolVersion: Version = ProtocolVersion.current
    ) -> DiscoveryConfiguration {
        DiscoveryConfiguration(
            client: Harness.client, protocolVersion: protocolVersion, simulatorPorts: ports,
            devicePorts: [], usbmuxdSocketPath: nil, scanInterval: .milliseconds(50),
            connectTimeout: .seconds(1), requestTimeout: .seconds(1))
    }

    /// A port nothing listens on: one that a server just gave back.
    private func unusedPort() async throws -> UInt16 {
        let server = try await MockServer.start(script: MockScript(steps: []))
        let port = server.port
        await server.stop()
        return port
    }

    // MARK: - C-CONN-01

    func test_C_CONN_01_findsAnAppInTheRealPortRangeWithinTwoSeconds() async throws {
        // The real range and the real two-second interval. Other apps may be running in the
        // range, so the server takes whichever port is free.
        var server: MockServer?
        for port in DiscoveryConfiguration.ports {
            server = try? await MockServer.start(port: port, script: try .fixtures("handshake"))
            if server != nil { break }
        }
        let mock = try XCTUnwrap(server, "every port from 48160 to 48167 is in use")

        let discovery = Discovery(configuration: DiscoveryConfiguration(
            client: Harness.client, usbmuxdSocketPath: nil))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let found = await Harness.eventually(within: .seconds(2)) {
            await recorder.seen.contains(.found(.simulator(port: mock.port), Harness.demoApp))
        }
        XCTAssertTrue(found)

        await discovery.stop()
        await mock.stop()
    }

    func test_C_CONN_01_theDefaultConfigurationCoversTheProtocolsPorts() {
        let configuration = DiscoveryConfiguration(client: Harness.client)
        XCTAssertEqual(configuration.simulatorPorts, [48160, 48161, 48162, 48163, 48164, 48165, 48166, 48167])
        XCTAssertEqual(configuration.devicePorts, configuration.simulatorPorts)
        XCTAssertEqual(configuration.scanInterval, .seconds(2))
        XCTAssertEqual(configuration.requestTimeout, .seconds(10))
        XCTAssertEqual(configuration.usbmuxdSocketPath, "/var/run/usbmuxd")
    }

    func test_C_CONN_01_portsNobodyListensOnYieldNothing() async throws {
        let ports = [try await unusedPort(), try await unusedPort()]
        let discovery = Discovery(configuration: configuration(ports: ports))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        try await Task.sleep(for: .milliseconds(300))
        let seen = await recorder.seen
        XCTAssertEqual(seen, [])
        await discovery.stop()
    }

    func test_C_CONN_01_aPortThatSpeaksSomethingElseIsIgnored() async throws {
        // Something that accepts the connection and answers with bytes that are no frame.
        let other = try await MockServer.start(script: MockScript(steps: [
            .sendBytes(Data("HTTP/1.1 400 Bad Request\r\n\r\n".utf8)), .close,
        ]))
        let app = try await MockServer.start(script: try .fixtures("handshake"))
        let discovery = Discovery(configuration: configuration(ports: [other.port, app.port]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let found = await Harness.eventually {
            await recorder.seen.contains(.found(.simulator(port: app.port), Harness.demoApp))
        }
        XCTAssertTrue(found)
        // The other port keeps being probed and never shows up.
        let retried = await Harness.eventually { await other.connectionCount >= 3 }
        XCTAssertTrue(retried)
        let seen = await recorder.seen
        XCTAssertFalse(seen.contains { event in
            if case .found(.simulator(port: other.port), _) = event { return true }
            return false
        })

        await discovery.stop()
        await other.stop()
        await app.stop()
    }

    // MARK: - C-CONN-09

    func test_C_CONN_09_aStoppedDiscoveryDoesNotStartAgain() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let discovery = Discovery(configuration: configuration(ports: [server.port]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let found = await Harness.eventually {
            await recorder.seen.contains(.found(.simulator(port: server.port), Harness.demoApp))
        }
        XCTAssertTrue(found)

        await discovery.stop()
        await discovery.start()
        // Six scan intervals. A restarted discovery would have probed the port at once, with
        // nobody to hear of it (the event stream ended at stop()), holding the app's one
        // client slot.
        try await Task.sleep(for: .milliseconds(300))
        let connections = await server.connectionCount
        XCTAssertEqual(connections, 1)

        await discovery.stop()
        await server.stop()
    }

    func test_C_CONN_09_aProbeUnderWayWhenDiscoveryStopsGivesItsConnectionBack() async throws {
        // The app answers the Hello only when the test lets it; discovery stops before that.
        let gate = MockGate()
        var hello = try MockScript.fixtures("handshake").steps
        hello.insert(.hold(gate), at: 1)
        let server = try await MockServer.start(script: MockScript(steps: hello))
        var settings = configuration(ports: [server.port])
        settings.requestTimeout = .seconds(10)
        let discovery = Discovery(configuration: settings)
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let asked = await Harness.eventually { await server.receivedFrames.count == 1 }
        XCTAssertTrue(asked, "the probe's Hello did not arrive")

        await discovery.stop()
        await gate.open()

        // The probe completed its handshake after the stop, and closed the connection rather
        // than keeping the app's one client slot.
        let closed = await Harness.eventually { await server.clientCloseCount == 1 }
        XCTAssertTrue(closed, "the probe kept its connection")
        let seen = await recorder.seen
        XCTAssertEqual(seen, [])

        await server.stop()
    }

    func test_C_CONN_09_anAppKeepsOneConnectionAcrossRounds() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let discovery = Discovery(configuration: configuration(ports: [server.port]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let found = await Harness.eventually { await recorder.session(at: .simulator(port: server.port)) != nil }
        XCTAssertTrue(found)
        // Several rounds later the port has still been connected to exactly once.
        try await Task.sleep(for: .milliseconds(400))
        let connections = await server.connectionCount
        XCTAssertEqual(connections, 1)

        // The same connection serves requests: a server serves one client at a time, so the list
        // and the inspection share it.
        let unwrapped = await recorder.session(at: .simulator(port: server.port))
        let session = try XCTUnwrap(unwrapped)
        do {
            _ = try await session.appIcon()
        } catch {
            // The script has no AppIcon to send, so this times out; what matters is below.
        }
        let frames = await server.receivedFrames
        XCTAssertEqual(frames.map { MessageKind($0.body) }, [.hello, .getAppIcon])
        let connectionsAfter = await server.connectionCount
        XCTAssertEqual(connectionsAfter, 1)

        await discovery.stop()
        await server.stop()
    }

    func test_C_CONN_09_aBusyAppIsNotListedAndIsTriedAgain() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("busy", closesWhenDone: true))
        let discovery = Discovery(configuration: configuration(ports: [server.port]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        // Tried again each round…
        let retried = await Harness.eventually { await server.connectionCount >= 3 }
        XCTAssertTrue(retried)
        // …and never reported, neither as an app nor as an error.
        let seen = await recorder.seen
        XCTAssertEqual(seen, [])

        await discovery.stop()
        await server.stop()
    }

    // MARK: - C-CONN-07

    func test_C_CONN_07_anAppThatGoesAwayIsLost() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let location = AppLocation.simulator(port: server.port)
        let discovery = Discovery(configuration: configuration(ports: [server.port]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let found = await Harness.eventually { await recorder.seen.contains(.found(location, Harness.demoApp)) }
        XCTAssertTrue(found)

        await server.stop()

        let lost = await Harness.eventually { await recorder.seen.last == .lost(location) }
        XCTAssertTrue(lost)
        await discovery.stop()
    }

    func test_C_CONN_07_anAppThatClosesRightAfterTheHandshakeIsLost() async throws {
        var steps = try MockScript.fixtures("handshake").steps
        steps.append(.close)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let location = AppLocation.simulator(port: server.port)
        let discovery = Discovery(configuration: configuration(ports: [server.port]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        // Found, lost, and found again on a later round: never found twice in a row.
        let cycled = await Harness.eventually {
            await recorder.seen.filter { $0 == .lost(location) }.count >= 2
        }
        XCTAssertTrue(cycled)
        await discovery.stop()
        await server.stop()

        var isListed = false
        for event in await recorder.seen {
            switch event {
            case .found:
                XCTAssertFalse(isListed, "found again without having been lost")
                isListed = true
            case .lost:
                XCTAssertTrue(isListed, "lost without having been found")
                isListed = false
            case .stateChanged, .incompatible:
                break
            }
        }
    }

    func test_C_CONN_07_stoppingDiscoveryClosesItsConnections() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let location = AppLocation.simulator(port: server.port)
        let discovery = Discovery(configuration: configuration(ports: [server.port]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()
        let found = await Harness.eventually { await recorder.session(at: location) != nil }
        XCTAssertTrue(found)
        let unwrapped = await recorder.session(at: location)
        let session = try XCTUnwrap(unwrapped)

        await discovery.stop()

        do {
            _ = try await session.hierarchy()
            XCTFail("the session is still open")
        } catch {
            XCTAssertEqual(error as? RequestError, .disconnected)
        }
        await server.stop()
    }

    // MARK: - C-CONN-08

    func test_C_CONN_08_stateChangesAreReportedForTheirApp() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-not-active"))
        let location = AppLocation.simulator(port: server.port)
        let discovery = Discovery(configuration: configuration(ports: [server.port]))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let reported = await Harness.eventually { await recorder.seen.count >= 3 }
        XCTAssertTrue(reported)
        let seen = await recorder.seen
        XCTAssertEqual(Array(seen.prefix(3)), [
            .found(location, Harness.demoApp),
            .stateChanged(location, .active),
            .stateChanged(location, .background),
        ])

        await discovery.stop()
        await server.stop()
    }

    // MARK: - C-LIST-02

    func test_C_LIST_02_anIncompatibleAppIsReportedEachRoundAndLostWhenItGoes() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake-version-mismatch", closesWhenDone: true))
        let location = AppLocation.simulator(port: server.port)
        // The fixture's client speaks 1.0; the server answers 0.5.
        let local = Version(major: 1, minor: 0)
        let discovery = Discovery(configuration: configuration(
            ports: [server.port], protocolVersion: local))
        let recorder = DiscoveryRecorder(discovery)
        await discovery.start()

        let expected = DiscoveryRecorder.Seen.incompatible(
            location, Harness.demoApp, local: local, remote: Version(major: 0, minor: 5))
        let repeated = await Harness.eventually {
            await recorder.seen.filter { $0 == expected }.count >= 2
        }
        XCTAssertTrue(repeated)
        let onlyThat = await recorder.seen.allSatisfy { $0 == expected }
        XCTAssertTrue(onlyThat)

        await server.stop()
        let lost = await Harness.eventually { await recorder.seen.last == .lost(location) }
        XCTAssertTrue(lost)
        // Lost once, not once per round.
        try await Task.sleep(for: .milliseconds(200))
        let lostCount = await recorder.seen.filter { $0 == .lost(location) }.count
        XCTAssertEqual(lostCount, 1)

        await discovery.stop()
    }
}
