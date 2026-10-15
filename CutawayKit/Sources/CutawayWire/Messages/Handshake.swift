// MARK: - Handshake

/// The protocol version this client speaks. A test compares it with Protocol/PROTOCOL_VERSION,
/// so that moving the submodule to a new protocol without updating the code fails.
public enum ProtocolVersion {
    public static let current = Version(major: 1, minor: 1)
}

public enum Role: Sendable { case client, server }

public enum DeviceKind: Sendable { case unknown, phone, pad, mac }

public struct Version: Hashable, Sendable {
    public var major: UInt16
    public var minor: UInt16

    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }
}

public struct ClientInfo: Equatable, Sendable {
    public var name: String?
    public var version: String?

    public init(name: String?, version: String?) {
        self.name = name
        self.version = version
    }
}

public struct AppInfo: Equatable, Sendable {
    public var name: String?
    public var bundleID: String?
    public var appVersion: String?
    public var deviceName: String?
    public var deviceKind: DeviceKind
    public var isSimulator: Bool
    public var osName: String?
    public var osVersion: String?
    public var screenSize: Size?
    public var screenScale: Float
    public var serverVersion: String?

    public init(
        name: String?, bundleID: String?, appVersion: String?, deviceName: String?,
        deviceKind: DeviceKind, isSimulator: Bool, osName: String?, osVersion: String?,
        screenSize: Size?, screenScale: Float, serverVersion: String?
    ) {
        self.name = name
        self.bundleID = bundleID
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.deviceKind = deviceKind
        self.isSimulator = isSimulator
        self.osName = osName
        self.osVersion = osVersion
        self.screenSize = screenSize
        self.screenScale = screenScale
        self.serverVersion = serverVersion
    }
}

public struct Hello: Equatable, Sendable {
    public var protocolVersion: Version?
    public var role: Role
    /// Set when `role` is `.client`.
    public var client: ClientInfo?
    /// Set when `role` is `.server`.
    public var app: AppInfo?

    public init(protocolVersion: Version?, role: Role, client: ClientInfo?, app: AppInfo?) {
        self.protocolVersion = protocolVersion
        self.role = role
        self.client = client
        self.app = app
    }
}
