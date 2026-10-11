import CutawayTransport
import CutawayWire
import Foundation

/// What an inspection may ask its source for (P-HELLO-04, C-ARCH-05): worked out from the
/// negotiated protocol version and from whether the source is an app or an archive, in one
/// place, so that the inspection never reads version numbers itself.
public struct InspectionCapabilities: Equatable, Sendable {
    /// `GetSubtree`: protocol 0.3, and only an app can send one (C-DET-07).
    public var canRefreshSubtrees: Bool
    /// `SetAttribute`: protocol 0.3, and only an app can take one (C-ATTR-04).
    public var canEditAttributes: Bool
    /// The constraints in a layer's detail: protocol 0.4 (C-LAYOUT-01).
    public var givesConstraints: Bool

    public init(canRefreshSubtrees: Bool, canEditAttributes: Bool, givesConstraints: Bool) {
        self.canRefreshSubtrees = canRefreshSubtrees
        self.canEditAttributes = canEditAttributes
        self.givesConstraints = givesConstraints
    }

    /// The capabilities of a source speaking `features`; an archive can only be looked at.
    public init(features: ProtocolFeatures, isLive: Bool) {
        canRefreshSubtrees = features.sendsSubtrees && isLive
        canEditAttributes = features.changesAttributes && isLive
        givesConstraints = features.givesConstraints
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
    /// By default, what the negotiated version has, for an app or an archive.
    public var capabilities: InspectionCapabilities? {
        get async {
            await negotiatedVersion.map {
                InspectionCapabilities(features: ProtocolFeatures(negotiated: $0), isLive: isLive)
            }
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
