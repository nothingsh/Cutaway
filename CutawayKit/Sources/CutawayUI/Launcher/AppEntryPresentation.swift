import CutawayModel
import CutawayTransport
import CutawayWire

/// What one row of the app list says about an app (C-LIST-01 to C-LIST-04): its name and
/// version, the second line, the mark of an app that is not active or not compatible, and
/// whether it is dimmed. The inspector window's title uses the name and the device line.
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
    /// The row's second line (C-LIST-04): "bundle ID · system" for a USB device, whose name is
    /// the group's header; "bundle ID · simulator · system" on this Mac, which may run several
    /// simulators; the reason for an app that is not compatible. Nil when nothing is known.
    var subtitle: String?
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
        let onThisMac = if case .simulator = entry.id { true } else { false }
        subtitle = compatibility ?? Self.subtitle(info, onThisMac: onThisMac)
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
        let parts = [text(info?.deviceName), system(info)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The second line of an app that can be inspected, or as much of it as is known.
    static func subtitle(_ info: AppInfo?, onThisMac: Bool) -> String? {
        let parts = [text(info?.bundleID), onThisMac ? text(info?.deviceName) : nil, system(info)]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "iOS 18.0", or as much of it as is known.
    private static func system(_ info: AppInfo?) -> String? {
        text([text(info?.osName), text(info?.osVersion)].compactMap { $0 }.joined(separator: " "))
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
