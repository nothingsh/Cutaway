import Foundation

/// The app's version and build, as `project.yml` sets them, the one place they are written
/// (C-DIST-01). The About panel, the archive's manifest and the handshake's `ClientInfo` all
/// read them here.
public struct AppVersion: Equatable, Sendable {
    /// `CFBundleShortVersionString`; empty when the bundle has none.
    public let version: String
    /// `CFBundleVersion`; empty when the bundle has none.
    public let build: String

    /// The running app's.
    public static var current: Self { Self(bundle: .main) }

    public init(bundle: Bundle) {
        self.init(info: bundle.infoDictionary ?? [:])
    }

    /// From an Info.plist's keys.
    public init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? ""
        build = info["CFBundleVersion"] as? String ?? ""
    }

    /// `major.minor.patch`, or `major.minor.patch-beta.N` for a prerelease: decimal numbers
    /// without leading zeros, `N` at least 1. The release script is to hold a tag to the same
    /// rule.
    public static func isValid(version: String) -> Bool {
        let number = #"(0|[1-9][0-9]*)"#
        let pattern = #"\A"# + number + #"\."# + number + #"\."# + number
            + #"(-beta\.[1-9][0-9]*)?\z"#
        return version.range(of: pattern, options: .regularExpression) != nil
    }

    /// A positive integer without leading zeros, which each release increases.
    public static func isValid(build: String) -> Bool {
        build.range(of: #"\A[1-9][0-9]*\z"#, options: .regularExpression) != nil
    }
}
