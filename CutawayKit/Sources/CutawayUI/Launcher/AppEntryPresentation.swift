import CutawayModel
import CutawayWire

/// What one row of the app list says about an app (C-LIST-01 to C-LIST-03): its name and
/// version, the bundle ID, the device and system, the mark of an app that is not active or not
/// compatible, and whether it is dimmed. The inspector window's title uses the name and the
/// device line too.
struct AppEntryPresentation: Equatable {
    /// The mark of an app that is not active (C-LIST-03) or not compatible (C-LIST-02).
    enum Badge: Equatable {
        case inactive
        case background
        case incompatible

        var text: String {
            switch self {
            case .inactive: return localized("app.badge.inactive")
            case .background: return localized("app.badge.background")
            case .incompatible: return localized("app.badge.incompatible")
            }
        }

        var symbol: String {
            switch self {
            case .inactive: return Theme.Symbol.inactive
            case .background: return Theme.Symbol.background
            case .incompatible: return Theme.Symbol.incompatible
            }
        }
    }

    var name: String
    var version: String?
    var bundleID: String?
    /// "iPhone 16 · iOS 18.0", or as much of it as is known; nil when nothing is.
    var deviceLine: String?
    var deviceSymbolName: String
    var badge: Badge?
    /// Both protocol versions, for an app that is not compatible.
    var compatibility: String?
    /// Listed, but not a choice: an app that is not compatible.
    var isDimmed: Bool

    init(_ entry: AppEntry) {
        let info = entry.info
        name = Self.name(of: info)
        version = Self.text(info?.appVersion)
        bundleID = Self.text(info?.bundleID)
        deviceLine = Self.deviceLine(info)
        deviceSymbolName = Self.deviceSymbolName(info?.deviceKind)

        switch entry.status {
        case .ready(let state):
            badge = Self.badge(for: state)
            compatibility = nil
            isDimmed = false
        case .incompatible(let local, let remote):
            badge = .incompatible
            compatibility = localized(
                "app.incompatible.detail", "\(remote.major).\(remote.minor)",
                "\(local.major).\(local.minor)")
            isDimmed = true
        }
    }

    /// The app's name, or "Unnamed app" when it has none.
    static func name(of info: AppInfo?) -> String {
        text(info?.name) ?? localized("app.unnamed")
    }

    private static func text(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// "iPhone 16 · iOS 18.0", or as much of it as is known.
    static func deviceLine(_ info: AppInfo?) -> String? {
        let system = [text(info?.osName), text(info?.osVersion)].compactMap { $0 }
            .joined(separator: " ")
        let parts = [text(info?.deviceName), text(system)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func deviceSymbolName(_ kind: DeviceKind?) -> String {
        switch kind {
        case .phone: return Theme.Symbol.phone
        case .pad: return Theme.Symbol.pad
        case .mac: return Theme.Symbol.mac
        case .unknown, nil: return Theme.Symbol.unknownDevice
        }
    }

    /// The mark of an app that is not active (C-LIST-03).
    private static func badge(for state: AppState) -> Badge? {
        switch state {
        case .active: return nil
        case .inactive: return .inactive
        case .background: return .background
        }
    }
}
