import CutawayScene
import CutawayWire

/// The scene's input made from a hierarchy as the app sends it, for the scene's tests, which
/// do without the model. It takes the nodes in the order of the wire, as `LayerTree` does;
/// `CutawayModelTests` checks that `LayerTree.sceneLayers` makes the same.
public enum SceneInput {
    public static func layers(
        of hierarchy: Hierarchy, textures: [UInt64: LayerTextures] = [:]
    ) -> [SceneLayer] {
        hierarchy.nodes.map { node in
            let images = textures[node.id]
            return SceneLayer(
                id: node.id,
                parentID: node.parentID,
                bounds: node.bounds.map {
                    SceneRect(
                        x: $0.origin.x, y: $0.origin.y, width: $0.size.width,
                        height: $0.size.height)
                } ?? .zero,
                position: node.position.map { ScenePoint(x: $0.x, y: $0.y) } ?? .zero,
                anchorPoint: node.anchorPoint.map { ScenePoint(x: $0.x, y: $0.y) }
                    ?? ScenePoint(x: 0.5, y: 0.5),
                transform: node.transform.map {
                    SceneTransform(
                        m11: $0.m11, m12: $0.m12, m13: $0.m13, m14: $0.m14,
                        m21: $0.m21, m22: $0.m22, m23: $0.m23, m24: $0.m24,
                        m31: $0.m31, m32: $0.m32, m33: $0.m33, m34: $0.m34,
                        m41: $0.m41, m42: $0.m42, m43: $0.m43, m44: $0.m44)
                } ?? .identity,
                isHidden: node.isHidden,
                opacity: Double(node.opacity),
                solo: images?.solo,
                group: images?.group,
                capturesImage: !node.isCaptureExcluded)
        }
    }

    /// The fourteen layers of the `hierarchy` fixture.
    public static func hierarchyFixture(
        textures: [UInt64: LayerTextures] = [:]
    ) throws -> [SceneLayer] {
        layers(of: try Fixtures.hierarchy(), textures: textures)
    }

    /// The layers C-SCALE-01 is measured with (`ScaleScene`).
    public static func scaleScene() throws -> [SceneLayer] {
        layers(of: try ScaleScene.hierarchy())
    }
}
