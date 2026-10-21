import CutawayScene
import CutawayWire

extension LayerTree {
    /// The tree as the scene's input, in the order of the wire. `textures` says which images
    /// each layer has; a layer that is not in it has none. Geometry that the wire left out
    /// takes Core Animation's defaults: zero bounds and position, the anchor point in the
    /// middle, no transform. A virtual node and a node the app excludes from images ask for none (C-DET-11).
    public func sceneLayers(textures: [UInt64: LayerTextures] = [:]) -> [SceneLayer] {
        ids.compactMap { id -> SceneLayer? in
            guard let node = node(id) else { return nil }
            let images = textures[id]
            return SceneLayer(
                id: id,
                parentID: node.parentID,
                bounds: node.bounds.map(SceneRect.init) ?? .zero,
                position: node.position.map(ScenePoint.init) ?? .zero,
                anchorPoint: node.anchorPoint.map(ScenePoint.init) ?? ScenePoint(x: 0.5, y: 0.5),
                transform: node.transform.map(SceneTransform.init) ?? .identity,
                isHidden: node.isHidden,
                opacity: Double(node.opacity),
                solo: images?.solo,
                group: images?.group,
                content: SceneLayer.Content(node))
        }
    }

    /// The tree as the scene's input, with the images the inspection holds.
    public func sceneLayers(images: [UInt64: LayerImages]) -> [SceneLayer] {
        sceneLayers(
            textures: Dictionary(
                uniqueKeysWithValues: images.map { ($0.key, $0.value.textures(layerID: $0.key)) }))
    }
}

extension SceneLayer.Content {
    /// A virtual node stays one below an excluded layer too: it has no images either way, and
    /// is outlined, not hatched (C-REND-11).
    init(_ node: LayerNode) {
        if node.kind == .virtual {
            self = .drawnByParent
        } else {
            self = node.isCaptureExcluded ? .excluded : .captured
        }
    }
}

extension ScenePoint {
    init(_ point: Point) {
        self.init(x: point.x, y: point.y)
    }
}

// Internal only so that ConstraintEnd.swift can use it.
extension SceneRect {
    init(_ rect: Rect) {
        self.init(
            x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}

extension SceneTransform {
    init(_ t: Transform3D) {
        self.init(
            m11: t.m11, m12: t.m12, m13: t.m13, m14: t.m14,
            m21: t.m21, m22: t.m22, m23: t.m23, m24: t.m24,
            m31: t.m31, m32: t.m32, m33: t.m33, m34: t.m34,
            m41: t.m41, m42: t.m42, m43: t.m43, m44: t.m44)
    }
}
