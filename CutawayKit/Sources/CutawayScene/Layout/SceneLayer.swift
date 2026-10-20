/// One layer as the scene sees it. A list of them comes in the order of the wire: a parent
/// before its children, siblings back to front (P-HIER-01).
public struct SceneLayer: Equatable, Sendable {
    public var id: UInt64
    /// 0 for the root layer of a window.
    public var parentID: UInt64
    public var bounds: SceneRect
    /// In the parent's coordinates (P-HIER-06).
    public var position: ScenePoint
    public var anchorPoint: ScenePoint
    public var transform: SceneTransform
    public var isHidden: Bool
    public var opacity: Double
    public var solo: TextureKey?
    public var group: TextureKey?
    /// False for a layer the app does not let be captured (P-DET-10): no image is asked for
    /// it (C-DET-11).
    public var capturesImage: Bool

    public init(
        id: UInt64, parentID: UInt64, bounds: SceneRect, position: ScenePoint,
        anchorPoint: ScenePoint = ScenePoint(x: 0.5, y: 0.5),
        transform: SceneTransform = .identity, isHidden: Bool = false, opacity: Double = 1,
        solo: TextureKey? = nil, group: TextureKey? = nil, capturesImage: Bool = true
    ) {
        self.id = id
        self.parentID = parentID
        self.bounds = bounds
        self.position = position
        self.anchorPoint = anchorPoint
        self.transform = transform
        self.isHidden = isHidden
        self.opacity = opacity
        self.solo = solo
        self.group = group
        self.capturesImage = capturesImage
    }
}

/// Names one image of one layer for the texture cache.
public struct TextureKey: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The layer without its sublayers.
        case solo
        /// The layer with its whole subtree.
        case group
    }

    public var layerID: UInt64
    public var kind: Kind
    /// Changes whenever the layer's image of this kind is replaced, so that a draw list with a
    /// new image is not equal to the one before it.
    public var revision: UInt64

    public init(layerID: UInt64, kind: Kind, revision: UInt64) {
        self.layerID = layerID
        self.kind = kind
        self.revision = revision
    }
}

/// The images a layer has.
public struct LayerTextures: Equatable, Sendable {
    public var solo: TextureKey?
    public var group: TextureKey?

    public init(solo: TextureKey? = nil, group: TextureKey? = nil) {
        self.solo = solo
        self.group = group
    }
}

/// A layer that is drawn, and the kind of image it is drawn with (C-SCENE-03). The inspection
/// asks the app for these.
public struct TextureNeed: Hashable, Sendable {
    public var layerID: UInt64
    public var kind: TextureKey.Kind

    public init(layerID: UInt64, kind: TextureKey.Kind) {
        self.layerID = layerID
        self.kind = kind
    }
}
