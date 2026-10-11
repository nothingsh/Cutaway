// MARK: - Layer details

public enum DetailStatus: Sendable { case ok, layerNotFound, captureFailed }

public struct LayerDetailRequest: Equatable, Sendable {
    public var layerID: UInt64
    public var wantSolo: Bool
    public var wantGroup: Bool
    public var wantAttributes: Bool
    /// Protocol 0.4. A 0.3 server ignores it.
    public var wantConstraints: Bool

    public init(
        layerID: UInt64, wantSolo: Bool, wantGroup: Bool, wantAttributes: Bool,
        wantConstraints: Bool = false
    ) {
        self.layerID = layerID
        self.wantSolo = wantSolo
        self.wantGroup = wantGroup
        self.wantAttributes = wantAttributes
        self.wantConstraints = wantConstraints
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

public struct LayerDetail: Equatable, Sendable {
    public var layerID: UInt64
    public var status: DetailStatus
    /// The layer without its sublayers.
    public var solo: EncodedImage?
    /// The layer with its whole subtree.
    public var group: EncodedImage?
    public var attributeGroups: [AttributeGroup]
    /// Protocol 0.4 (P-LAYOUT-01). Empty when they were not asked for, when the layer backs no
    /// view, when the view has none, and from a 0.3 server: the wire cannot tell an absent list
    /// from an empty one, so the caller goes by the negotiated version and the layer.
    public var constraints: [LayoutConstraint]

    public init(
        layerID: UInt64, status: DetailStatus, solo: EncodedImage?, group: EncodedImage?,
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
