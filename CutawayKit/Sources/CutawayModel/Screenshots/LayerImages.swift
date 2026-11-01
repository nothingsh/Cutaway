import CutawayScene
import CutawayWire

/// An image as it arrived, compressed, and the revision it is known by (C-DET-08). Two of
/// these are equal when their revisions are: a revision is never given to another image, so
/// comparing never reads the data.
public struct RevisionedImage: Equatable, Sendable {
    public var revision: UInt64
    public var image: EncodedImage

    public init(revision: UInt64, image: EncodedImage) {
        self.revision = revision
        self.image = image
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.revision == b.revision
    }
}

/// The images of one layer, as the inspection holds them. Each kind is replaced on its own.
public struct LayerImages: Equatable, Sendable {
    public var solo: RevisionedImage?
    public var group: RevisionedImage?

    public init(solo: RevisionedImage? = nil, group: RevisionedImage? = nil) {
        self.solo = solo
        self.group = group
    }

    public var isEmpty: Bool { solo == nil && group == nil }

    /// One kind of image.
    subscript(kind: TextureKey.Kind) -> RevisionedImage? {
        get { kind == .solo ? solo : group }
        set {
            if kind == .solo { solo = newValue } else { group = newValue }
        }
    }

    /// The image a request for one kind compares with: that kind, or for a solo not held, the
    /// group, which is the same picture when the layer has no sublayers (P-DET-04, P-IMG-06).
    func held(answering need: TextureNeed) -> RevisionedImage? {
        need.kind == .solo ? solo ?? group : group
    }

    /// The keys the scene and the texture cache know these images by.
    public func textures(layerID: UInt64) -> LayerTextures {
        LayerTextures(
            solo: solo.map { TextureKey(layerID: layerID, kind: .solo, revision: $0.revision) },
            group: group.map { TextureKey(layerID: layerID, kind: .group, revision: $0.revision) },
            groupIsComposited: group?.image.composited ?? false)
    }

    /// The image a key names, when it is held under that key's revision.
    public func image(for key: TextureKey) -> EncodedImage? {
        let held = key.kind == .solo ? solo : group
        return held?.revision == key.revision ? held?.image : nil
    }
}
