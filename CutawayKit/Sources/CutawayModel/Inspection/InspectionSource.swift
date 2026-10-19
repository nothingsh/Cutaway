import CutawayTransport
import CutawayWire
import Foundation

/// What an inspection may ask its source for (C-ARCH-05), in one place: whether the source is
/// an app or an archive, and what the negotiated version has. Every version the handshake
/// accepts can refresh subtrees and edit attributes (P-HELLO-03); overriding the environment
/// came in 1.2.
public struct InspectionCapabilities: Equatable, Sendable {
    /// `GetSubtree`: only an app can send one (C-DET-07).
    public var canRefreshSubtrees: Bool
    /// `SetAttribute`: only an app can take one (C-ATTR-04).
    public var canEditAttributes: Bool
    /// `GetEnvironment` and `SetEnvironment`: only an app, and from protocol 1.2 on
    /// (C-WIRE-12, C-ENV-01).
    public var canOverrideEnvironment: Bool

    public init(
        canRefreshSubtrees: Bool, canEditAttributes: Bool, canOverrideEnvironment: Bool = false
    ) {
        self.canRefreshSubtrees = canRefreshSubtrees
        self.canEditAttributes = canEditAttributes
        self.canOverrideEnvironment = canOverrideEnvironment
    }

    /// The capabilities of an app that negotiated `version`, or of an archive, which can only
    /// be looked at.
    public init(isLive: Bool, version: Version) {
        canRefreshSubtrees = isLive
        canEditAttributes = isLive
        canOverrideEnvironment = isLive && version.minor >= 2
    }
}

/// Which images a source is known to hold of a layer (C-ARCH-06).
public struct ImagePresence: Equatable, Sendable {
    public var solo: Bool
    public var group: Bool

    public init(solo: Bool, group: Bool) {
        self.solo = solo
        self.group = group
    }
}

/// Where an inspection's data comes from: the app over a connection, or an archive of it
/// (C-ARCH-05). The inspection asks the same questions of either.
public protocol InspectionSource: AnyObject, Sendable {
    /// Whether this is a connection: only then can attributes be changed, subtrees refreshed
    /// and archives saved.
    nonisolated var isLive: Bool { get }
    /// The protocol version the data follows (P-HELLO-04). Nil before a handshake.
    var negotiatedVersion: Version? { get async }
    /// What the inspection may ask for. Nil before a handshake.
    var capabilities: InspectionCapabilities? { get async }
    /// The images the source holds of each layer, when that is known without asking: an
    /// archive knows from opening on; an app is asked when the time comes, so nil (C-ARCH-06).
    nonisolated var imagePresence: [UInt64: ImagePresence]? { get }
    /// What an archive is captured from (C-ARCH-02); nil for a source that cannot be
    /// captured, such as an archive itself.
    nonisolated var recordable: (any ArchiveRecordable)? { get }
    func hierarchy() async throws -> Hierarchy
    func subtree(of rootID: UInt64) async throws -> Hierarchy
    func layerDetails(_ request: GetLayerDetails) async -> LayerDetailsStream
    func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult
}

extension InspectionSource {
    /// By default, those of an app or an archive, once a version is negotiated.
    public var capabilities: InspectionCapabilities? {
        get async {
            await negotiatedVersion.map { InspectionCapabilities(isLive: isLive, version: $0) }
        }
    }

    /// By default, nothing is known without asking.
    public nonisolated var imagePresence: [UInt64: ImagePresence]? { nil }

    /// By default, nothing can be captured.
    public nonisolated var recordable: (any ArchiveRecordable)? { nil }
}

/// What capturing an archive needs of a connection (C-ARCH-02, Resources/ARCHIVE.md): the
/// server's `Hello` and the answers as received, bytes and all.
public protocol ArchiveRecordable: AnyObject, Sendable {
    var negotiatedVersion: Version? { get async }
    var serverHelloPayload: Data? { get async }
    func recordedAppIcon() async throws -> Recorded<EncodedImage?>
    func recordedHierarchy() async throws -> Recorded<Hierarchy>
    func recordedLayerDetails(_ request: GetLayerDetails) async -> RecordedLayerDetailsStream
}

extension Session: InspectionSource, ArchiveRecordable {
    public nonisolated var isLive: Bool { true }

    public nonisolated var recordable: (any ArchiveRecordable)? { self }
}
