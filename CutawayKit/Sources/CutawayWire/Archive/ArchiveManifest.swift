import Foundation

// The archive format of Resources/ARCHIVE.md (C-ARCH-01). Only bytes: reading and writing files
// is up to the caller.

/// What an archive says about itself.
public struct ArchiveManifest: Equatable, Sendable {
    /// The protocol version negotiated when the frames were fetched (P-HELLO-04).
    public var protocolVersion: Version
    /// The version of the Cutaway that wrote the archive. For display only.
    public var cutawayVersion: String
    /// When the archive was saved. Stored to the second.
    public var savedAt: Date

    public init(protocolVersion: Version, cutawayVersion: String, savedAt: Date) {
        self.protocolVersion = protocolVersion
        self.cutawayVersion = cutawayVersion
        self.savedAt = savedAt
    }
}

enum ArchiveLayout {
    static let magic = Data("CTWYARCH".utf8)
    static let endMagic = Data("CTWYDONE".utf8)
}

/// The JSON form of the manifest. Internal only so the encoder and the decoder, in their own
/// files, can reach it.
struct ManifestJSON: Codable {
    struct VersionJSON: Codable {
        var major: UInt16
        var minor: UInt16
    }

    var `protocol`: VersionJSON
    var cutawayVersion: String
    var savedAt: Date
}
