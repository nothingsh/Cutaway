import CutawayWire
import Foundation
import os

public struct DiscoveryConfiguration: Sendable {
    /// The ports a server may listen on (P-TRANS-02).
    public static let ports: [UInt16] = Array(48160...48167)

    public var client: ClientInfo
    public var protocolVersion: Version
    /// Ports to try on this Mac's loopback address.
    public var simulatorPorts: [UInt16]
    /// Ports to try on each attached device.
    public var devicePorts: [UInt16]
    /// Nil turns device discovery off.
    public var usbmuxdSocketPath: String?
    public var scanInterval: Duration
    public var connectTimeout: Duration
    public var requestTimeout: Duration

    public init(
        client: ClientInfo,
        protocolVersion: Version = ProtocolVersion.current,
        simulatorPorts: [UInt16] = Self.ports,
        devicePorts: [UInt16] = Self.ports,
        usbmuxdSocketPath: String? = "/var/run/usbmuxd",
        scanInterval: Duration = .seconds(2),
        connectTimeout: Duration = .seconds(1),
        requestTimeout: Duration = .seconds(10)
    ) {
        self.client = client
        self.protocolVersion = protocolVersion
        self.simulatorPorts = simulatorPorts
        self.devicePorts = devicePorts
        self.usbmuxdSocketPath = usbmuxdSocketPath
        self.scanInterval = scanInterval
        self.connectTimeout = connectTimeout
        self.requestTimeout = requestTimeout
    }
}

public enum DiscoveryEvent: Sendable {
    /// An app answered the handshake. The session is the one connection to it: the list and
    /// the inspection both use it (C-CONN-09).
    case found(AppLocation, AppInfo, Session)
    case stateChanged(AppLocation, AppState)
    /// An app whose protocol major version differs. Reported again every round it is still
    /// there (C-LIST-02).
    case incompatible(AppLocation, AppInfo?, local: Version, remote: Version)
    /// A found or incompatible app is gone.
    case lost(AppLocation)
}

/// Finds apps on local ports and on USB devices, round after round, and keeps one connection
/// to each.
public actor Discovery {
    /// Where discovery says what it found and lost; nothing is shown.
    private static let log = Logger(subsystem: "dev.cutaway", category: "discovery")

    private let configuration: DiscoveryConfiguration

    private var isRunning = false
    /// Set by `stop()`. Its event stream has ended, so it cannot run again.
    private var hasStopped = false
    private var sessions: [AppLocation: Session] = [:]
    private var incompatible: Set<AppLocation> = []
    /// Locations with a probe in flight; they are not probed again until it ends.
    private var probing: Set<AppLocation> = []
    /// usbmuxd's device ID → serial number, for the devices attached now.
    private var devices: [Int: String] = [:]
    private var scanTask: Task<Void, Never>?
    private var deviceTask: Task<Void, Never>?

    /// What discovery finds and loses. Meant for one consumer. Ends when discovery is stopped.
    public nonisolated let events: AsyncStream<DiscoveryEvent>
    private let continuation: AsyncStream<DiscoveryEvent>.Continuation

    public init(configuration: DiscoveryConfiguration) {
        self.configuration = configuration
        let (events, continuation) = AsyncStream.makeStream(of: DiscoveryEvent.self)
        self.events = events
        self.continuation = continuation
    }

    /// Starts scanning. The first round begins at once. Does nothing after `stop()`.
    public func start() {
        guard !isRunning, !hasStopped else { return }
        isRunning = true
        let interval = configuration.scanInterval

        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard (await self?.scan()) != nil else { return }
                try? await Task.sleep(for: interval)
            }
        }

        if let path = configuration.usbmuxdSocketPath {
            let timeout = configuration.connectTimeout
            deviceTask = Task { [weak self] in
                while !Task.isCancelled {
                    for await event in Usbmuxd.deviceEvents(socketPath: path, timeout: timeout) {
                        await self?.handle(event)
                    }
                    // usbmuxd is not there, or went away: its devices went with it.
                    guard (await self?.forgetAllDevices()) != nil else { return }
                    try? await Task.sleep(for: interval)
                }
            }
        }
    }

    /// Stops scanning and closes every connection. A stopped discovery cannot be restarted.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        hasStopped = true
        scanTask?.cancel()
        deviceTask?.cancel()

        let open = Array(sessions.values)
        sessions = [:]
        incompatible = []
        devices = [:]
        for session in open {
            Task { await session.close() }
        }
        continuation.finish()
    }

    // MARK: - Rounds

    private func scan() {
        guard isRunning else { return }
        var candidates = configuration.simulatorPorts.map { AppLocation.simulator(port: $0) }
        for serial in Set(devices.values).sorted() {
            candidates += configuration.devicePorts.map { .device(serial: serial, port: $0) }
        }
        // Only locations that have no connection and no probe in flight (C-CONN-09).
        for location in candidates where sessions[location] == nil && !probing.contains(location) {
            probing.insert(location)
            Task { await self.probe(location) }
        }
    }

    private func probe(_ location: AppLocation) async {
        defer { probing.remove(location) }

        let session: Session
        let outcome: HandshakeOutcome
        do {
            let channel = try await openChannel(to: location)
            session = Session(
                channel: channel, client: configuration.client,
                protocolVersion: configuration.protocolVersion,
                requestTimeout: configuration.requestTimeout)
            outcome = try await session.handshake()
        } catch {
            // Nothing listens there, or what listens is not a Cutaway server. Only a server
            // that answered wrongly is worth a line: a closed port is the usual case.
            if case RequestError.protocolViolation(let reason) = error {
                Self.log.notice("\(String(describing: location), privacy: .public): \(reason, privacy: .public)")
            }
            forgetIncompatible(location)
            return
        }

        guard isRunning, isAttached(location) else {
            // Discovery was stopped, or the device left, while the probe was under way.
            // Reporting the app now would list something no later event takes back: an
            // incompatible app holds no connection whose end could announce its loss.
            await session.close()
            return
        }

        switch outcome {
        case .ready(let app, _):
            Self.log.info(
                "found \(app.name ?? "an app", privacy: .public) at \(String(describing: location), privacy: .public)")
            incompatible.remove(location)
            sessions[location] = session
            continuation.yield(.found(location, app, session))
            follow(session, at: location)
        case .incompatible(let local, let remote, let app):
            Self.log.notice(
                """
                \(String(describing: location), privacy: .public) speaks protocol \
                \(remote.major).\(remote.minor), this Cutaway \(local.major).\(local.minor)
                """)
            incompatible.insert(location)
            continuation.yield(.incompatible(location, app, local: local, remote: remote))
        case .busy:
            // Another client holds it. Not an app in the list and not an error; the next
            // round tries again.
            forgetIncompatible(location)
        }
    }

    private func openChannel(to location: AppLocation) async throws -> any ByteChannel {
        switch location {
        case .simulator(let port):
            return try await ConnectionChannel.connect(
                host: "127.0.0.1", port: port, timeout: configuration.connectTimeout)
        case .device(let serial, let port):
            guard let path = configuration.usbmuxdSocketPath,
                  let deviceID = devices.first(where: { $0.value == serial })?.key
            else { throw ChannelError.connectionFailed("the device is not attached") }
            return try await Usbmuxd.connect(
                socketPath: path, deviceID: deviceID, port: port,
                timeout: configuration.connectTimeout)
        }
    }

    private func isAttached(_ location: AppLocation) -> Bool {
        switch location {
        case .simulator: return true
        case .device(let serial, _): return devices.values.contains(serial)
        }
    }

    // MARK: - Connections

    /// Forwards a session's events until it closes. Discovery is the session's one consumer.
    private func follow(_ session: Session, at location: AppLocation) {
        Task { [weak self] in
            for await event in session.events {
                if case .appStateChanged(let state) = event {
                    await self?.report(state, at: location, from: session)
                }
            }
            await self?.sessionEnded(session, at: location)
        }
    }

    private func report(_ state: AppState, at location: AppLocation, from session: Session) {
        guard sessions[location] === session else { return }
        continuation.yield(.stateChanged(location, state))
    }

    private func sessionEnded(_ session: Session, at location: AppLocation) {
        guard sessions[location] === session else { return }
        Self.log.info("lost \(String(describing: location), privacy: .public)")
        sessions[location] = nil
        continuation.yield(.lost(location))
    }

    private func forgetIncompatible(_ location: AppLocation) {
        if incompatible.remove(location) != nil {
            continuation.yield(.lost(location))
        }
    }

    // MARK: - Devices

    private func handle(_ event: DeviceEvent) {
        guard isRunning else { return }
        switch event {
        case .attached(let deviceID, let serial):
            devices[deviceID] = serial
            // Do not wait for the next round.
            scan()
        case .detached(let deviceID):
            guard let serial = devices.removeValue(forKey: deviceID) else { return }
            if !devices.values.contains(serial) { forget(serial: serial) }
        }
    }

    private func forgetAllDevices() {
        let serials = Set(devices.values)
        devices = [:]
        for serial in serials { forget(serial: serial) }
    }

    /// Drops everything that was reached through a device that is gone.
    private func forget(serial: String) {
        func isOnDevice(_ location: AppLocation) -> Bool {
            if case .device(serial, _) = location { return true }
            return false
        }
        for location in sessions.keys.filter(isOnDevice).sorted() {
            guard let session = sessions.removeValue(forKey: location) else { continue }
            continuation.yield(.lost(location))
            Task { await session.close() }
        }
        for location in incompatible.filter(isOnDevice).sorted() {
            incompatible.remove(location)
            continuation.yield(.lost(location))
        }
    }
}
