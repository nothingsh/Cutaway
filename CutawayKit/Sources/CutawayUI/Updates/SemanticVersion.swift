import Foundation

/// A version in the form of C-DIST-01, `major.minor.patch` with an optional `-beta.N`, in the
/// order Check for Updates… compares them (C-DIST-02): number by number, and a release after
/// the betas of the same numbers.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// `N` of `-beta.N`; nil for a release.
    public let beta: Int?

    public var isPrerelease: Bool { beta != nil }

    /// The version `string` writes, which must be in the form `AppVersion` accepts.
    public init?(_ string: String) {
        guard AppVersion.isValid(version: string) else { return nil }
        let parts = string.split(separator: "-", maxSplits: 1)
        // A number too large for an Int is not a version this app can compare.
        let numbers = parts[0].split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        if parts.count > 1 {
            guard let beta = parts[1].split(separator: ".").last.flatMap({ Int($0) }) else { return nil }
            self.beta = beta
        } else {
            beta = nil
        }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    /// The version of a release's tag, `v` and the version (C-DIST-01).
    public init?(tag: String) {
        guard tag.hasPrefix("v") else { return nil }
        self.init(String(tag.dropFirst()))
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (beta.map { "-beta.\($0)" } ?? "")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        switch (lhs.beta, rhs.beta) {
        case (let left?, let right?): return left < right
        case (.some, nil): return true
        default: return false
        }
    }
}
