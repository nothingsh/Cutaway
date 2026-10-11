import CutawayTransport
import CutawayWire

/// What identifies an app across connections (C-WIN-04): not where it is reached, which can
/// change when it starts again, but which app on which device.
public struct AppIdentity: Hashable, Sendable {
    public let bundleID: String
    public let deviceName: String?
    public let isSimulator: Bool

    /// Nil without a bundle identifier: such an app cannot be recognised again.
    public init?(_ info: AppInfo) {
        guard let bundleID = info.bundleID, !bundleID.isEmpty else { return nil }
        self.bundleID = bundleID
        deviceName = info.deviceName
        isSimulator = info.isSimulator
    }
}

/// One app in the list.
public struct AppEntry: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Connected, and can be inspected. The state is the last one the app reported.
        case ready(AppState)
        /// The app speaks another major version of the protocol. It is listed so that the
        /// user sees why it cannot be inspected (C-LIST-02).
        case incompatible(local: Version, remote: Version)
    }

    /// Where the app is reached, which is also what identifies it.
    public var id: AppLocation
    /// Nil when an incompatible app's Hello carried no app info.
    public var info: AppInfo?
    public var status: Status
    public var icon: Bitmap?

    public init(id: AppLocation, info: AppInfo?, status: Status, icon: Bitmap?) {
        self.id = id
        self.info = info
        self.status = status
        self.icon = icon
    }

    public var isInspectable: Bool {
        if case .ready = status { return true }
        return false
    }
}
