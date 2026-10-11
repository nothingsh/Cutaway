/// Where an app's server is reached. It is also the app's identity: when an app quits and
/// another one takes its port, the first is lost and the second is found.
public enum AppLocation: Hashable, Sendable {
    /// A port on this Mac's loopback address: an app in a simulator.
    case simulator(port: UInt16)
    /// A port on a USB device, reached through usbmuxd.
    case device(serial: String, port: UInt16)
}

extension AppLocation: Comparable {
    /// Simulators first, by port; then devices, by serial number and port.
    public static func < (lhs: AppLocation, rhs: AppLocation) -> Bool {
        switch (lhs, rhs) {
        case (.simulator(let left), .simulator(let right)):
            return left < right
        case (.simulator, .device):
            return true
        case (.device, .simulator):
            return false
        case (.device(let leftSerial, let leftPort), .device(let rightSerial, let rightPort)):
            return (leftSerial, leftPort) < (rightSerial, rightPort)
        }
    }
}
