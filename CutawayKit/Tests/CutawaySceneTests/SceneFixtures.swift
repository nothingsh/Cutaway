import CutawayScene
import CutawayTestSupport
import Foundation

enum SceneFixtures {
    /// The nine layers the `hierarchy` fixture had before 1.2 as the scene's input: its
    /// virtual and excluded nodes (10 to 14) are left out until the scene places them in
    /// a later change (C-SCENE-13).
    static func hierarchyLayers(textures: [UInt64: LayerTextures] = [:]) throws -> [SceneLayer] {
        SceneInput.layers(of: try Fixtures.hierarchyBeforeProtocol12(), textures: textures)
    }

    static let allIDs: Set<UInt64> = Set(1...9)

    /// A layer whose bounds start at 0 and whose anchor point is its top left corner, so its
    /// window rectangle is `x, y, width, height` when its parent sits at the window's origin
    /// without a transform.
    static func layer(
        _ id: UInt64, parent: UInt64 = 0, x: Double, y: Double, width: Double, height: Double,
        transform: SceneTransform = .identity, hidden: Bool = false, opacity: Double = 1,
        solo: TextureKey? = nil, group: TextureKey? = nil
    ) -> SceneLayer {
        SceneLayer(
            id: id, parentID: parent, bounds: SceneRect(x: 0, y: 0, width: width, height: height),
            position: ScenePoint(x: x, y: y), anchorPoint: .zero, transform: transform,
            isHidden: hidden, opacity: opacity, solo: solo, group: group)
    }

    /// A window with `count` full-screen layers, each a child of the one before: `count`
    /// levels, the depth of a real screen's nested views.
    static func nestedScreens(_ count: Int) -> [SceneLayer] {
        (1...count).map { index in
            layer(
                UInt64(index), parent: UInt64(index - 1), x: 0, y: 0, width: 393, height: 852)
        }
    }

    /// A rotation about the z axis by `degrees`, in the layout of CATransform3D.
    static func rotation(degrees: Double) -> SceneTransform {
        let radians = degrees * .pi / 180
        var t = SceneTransform.identity
        t.m11 = cos(radians); t.m12 = sin(radians)
        t.m21 = -sin(radians); t.m22 = cos(radians)
        return t
    }

    static func solo(_ id: UInt64) -> TextureKey { TextureKey(layerID: id, kind: .solo, revision: 1) }
    static func group(_ id: UInt64) -> TextureKey { TextureKey(layerID: id, kind: .group, revision: 1) }
}
