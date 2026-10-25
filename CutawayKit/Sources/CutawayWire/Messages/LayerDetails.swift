import Foundation

// MARK: - Layer details

public enum DetailStatus: Sendable {
    case ok, layerNotFound, captureFailed
    /// The host app excludes the node from images (P-DET-10). Protocol 1.2.
    case excluded
}

public struct LayerDetailRequest: Equatable, Sendable {
    public var layerID: UInt64
    public var wantSolo: Bool
    public var wantGroup: Bool
    public var wantAttributes: Bool
    /// Protocol 0.4.
    public var wantConstraints: Bool
    /// The `digest` of the solo image held for this layer, as received (P-DET-11). Nil: none
    /// given, and none is written. Protocol 1.3.
    public var knownSoloDigest: Data?
    /// The same for the group image.
    public var knownGroupDigest: Data?

    public init(
        layerID: UInt64, wantSolo: Bool, wantGroup: Bool, wantAttributes: Bool,
        wantConstraints: Bool = false, knownSoloDigest: Data? = nil, knownGroupDigest: Data? = nil
    ) {
        self.layerID = layerID
        self.wantSolo = wantSolo
        self.wantGroup = wantGroup
        self.wantAttributes = wantAttributes
        self.wantConstraints = wantConstraints
        self.knownSoloDigest = knownSoloDigest
        self.knownGroupDigest = knownGroupDigest
    }
}

public struct GetLayerDetails: Equatable, Sendable {
    public var requests: [LayerDetailRequest]
    /// In pixels; 0 means no limit.
    public var maxTextureDimension: UInt32

    public init(requests: [LayerDetailRequest], maxTextureDimension: UInt32) {
        self.requests = requests
        self.maxTextureDimension = maxTextureDimension
    }
}

/// An image in a layer's details.
public enum DetailImage: Equatable, Sendable {
    case full(EncodedImage)
    /// The image the Client holds with this digest still stands; no pixels came (P-IMG-05,
    /// protocol 1.3). The digest is empty when the Server gave none, which matches no image.
    case unchanged(digest: Data)

    /// The image itself; nil when it is `unchanged`.
    public var fullImage: EncodedImage? {
        guard case .full(let image) = self else { return nil }
        return image
    }
}

public struct LayerDetail: Equatable, Sendable {
    public var layerID: UInt64
    public var status: DetailStatus
    /// The layer without its sublayers.
    public var solo: DetailImage?
    /// The layer with its whole subtree.
    public var group: DetailImage?
    public var attributeGroups: [AttributeGroup]
    /// Protocol 0.4 (P-LAYOUT-01). Empty when they were not asked for, when the layer backs no
    /// view, and when the view has none: the wire cannot tell an absent list from an empty
    /// one, so the caller goes by the layer.
    public var constraints: [LayoutConstraint]

    public init(
        layerID: UInt64, status: DetailStatus, solo: DetailImage?, group: DetailImage?,
        attributeGroups: [AttributeGroup], constraints: [LayoutConstraint] = []
    ) {
        self.layerID = layerID
        self.status = status
        self.solo = solo
        self.group = group
        self.attributeGroups = attributeGroups
        self.constraints = constraints
    }
}

public struct LayerDetailsChunk: Equatable, Sendable {
    /// Starts at 0 and increases by 1.
    public var sequence: UInt32
    public var details: [LayerDetail]

    public init(sequence: UInt32, details: [LayerDetail]) {
        self.sequence = sequence
        self.details = details
    }
}
