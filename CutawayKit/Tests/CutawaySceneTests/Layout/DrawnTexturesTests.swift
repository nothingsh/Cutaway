import CutawayScene
import CutawayTestSupport
import XCTest

/// The textures a layout, or a transition between two, draws with: the preview keeps those
/// and no others (C-SCALE-02).
final class DrawnTexturesTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)

    /// The `hierarchy` fixture with a solo and a group image for every layer.
    private func layers() throws -> [SceneLayer] {
        try SceneFixtures.hierarchyLayers(
            textures: Dictionary(
                uniqueKeysWithValues: SceneFixtures.allIDs.map {
                    ($0, LayerTextures(solo: SceneFixtures.solo($0), group: SceneFixtures.group($0)))
                }))
    }

    private func layout(collapsed: Set<UInt64> = [], focus: UInt64? = nil) throws -> SceneLayout {
        SceneLayout(
            layers: try layers(), expanded: SceneFixtures.allIDs.subtracting(collapsed),
            focus: focus)
    }

    /// The textures of every item of the list.
    private func textures(of list: DrawList) -> Set<TextureKey> {
        Set(list.items.compactMap(\.texture))
    }

    func test_C_SCALE_02_aLayoutDrawsTheTexturesOfItsDrawnLayersOnly() throws {
        typealias Fix = SceneFixtures
        // Expanded nodes with their solo, layers without sublayers with their group; layer 5
        // is hidden and layer 9 has no area.
        let expanded = try layout()
        XCTAssertEqual(
            expanded.drawnTextures,
            [Fix.solo(1), Fix.solo(2), Fix.group(3), Fix.solo(4), Fix.solo(6), Fix.group(7), Fix.group(8)])
        // A collapsed node with its group, and nothing inside it.
        let collapsed = try layout(collapsed: [4, 6])
        XCTAssertEqual(
            collapsed.drawnTextures,
            [Fix.solo(1), Fix.solo(2), Fix.group(3), Fix.group(4), Fix.group(6), Fix.group(8)])
        // Nothing outside the focus.
        XCTAssertEqual(try layout(focus: 6).drawnTextures, [Fix.solo(6), Fix.group(7)])
        // What a projection draws with, whatever the camera.
        for layout in [expanded, collapsed, try layout(focus: 6)] {
            for camera in [Camera.flat, .standard3D] {
                XCTAssertEqual(
                    textures(
                        of: layout.project(
                            camera: camera, viewport: viewport, selected: nil, hovered: nil)),
                    layout.drawnTextures)
            }
        }
    }

    func test_C_SCALE_02_aLayerWithoutAnImageAddsNoTexture() throws {
        let layers = try SceneFixtures.hierarchyLayers(
            textures: [2: LayerTextures(solo: SceneFixtures.solo(2))])
        let layout = SceneLayout(layers: layers, expanded: SceneFixtures.allIDs)
        XCTAssertEqual(layout.drawnTextures, [SceneFixtures.solo(2)])
    }

    func test_C_SCALE_02_aTransitionDrawsTheTexturesOfBothEnds() throws {
        typealias Fix = SceneFixtures
        for (from, to) in [([], [6]), ([6], []), ([], [2])] as [(Set<UInt64>, Set<UInt64>)] {
            let start = try layout(collapsed: from), end = try layout(collapsed: to)
            let transition = try XCTUnwrap(SceneTransition(from: start.presentation, to: end))
            XCTAssertTrue(
                transition.drawnTextures.isSuperset(of: end.drawnTextures),
                "\(from) to \(to): the end's")
            var drawn = Set<TextureKey>()
            for step in 0...20 {
                for camera in [Camera.flat, .standard3D] {
                    drawn.formUnion(
                        textures(
                            of: transition.project(
                                progress: Double(step) / 20, lens: Lens(camera),
                                viewport: viewport, selected: nil, hovered: nil)))
                }
            }
            XCTAssertEqual(transition.drawnTextures, drawn, "\(from) to \(to)")
        }
        // Collapsing layer 6: its sublayer comes down onto it with its image, and layer 6
        // keeps its solo until the end, when it takes its group.
        let collapsing = try XCTUnwrap(
            SceneTransition(from: try layout().presentation, to: try layout(collapsed: [6])))
        XCTAssertTrue(
            collapsing.drawnTextures.isSuperset(of: [Fix.solo(6), Fix.group(6), Fix.group(7)]))
    }
}

/// Changing the images of a few layers gives the same layout as choosing every layer's image
/// again (C-SCALE-02).
final class PartialTextureReplacementTests: XCTestCase {
    func test_C_SCALE_02_replacingSomeLayersImagesEqualsReplacingAll() throws {
        let viewport = Viewport(width: 480, height: 900)
        for seed in UInt64(1)...20 {
            var random = SeededGenerator(seed: seed)
            let layers = try SceneFixtures.hierarchyLayers()
            let expanded = SceneFixtures.allIDs.filter { _ in Bool.random(using: &random) }
            var layout = SceneLayout(layers: layers, expanded: expanded)
            var textures: [UInt64: LayerTextures] = [:]
            var revision: UInt64 = 1
            for step in 0..<30 {
                // A few layers get new images, lose theirs, or are named without a change.
                let changed = SceneFixtures.allIDs.union([42]).filter { _ in
                    Int.random(in: 0..<4, using: &random) == 0
                }
                for id in changed {
                    switch Int.random(in: 0..<4, using: &random) {
                    case 0: textures[id] = nil
                    case 1: break
                    default:
                        func key(_ kind: TextureKey.Kind) -> TextureKey? {
                            guard Bool.random(using: &random) else { return nil }
                            revision += 1
                            return TextureKey(layerID: id, kind: kind, revision: revision)
                        }
                        textures[id] = LayerTextures(solo: key(.solo), group: key(.group))
                    }
                }
                layout = layout.replacingTextures(textures, of: changed)
                let whole = SceneLayout(layers: layers, expanded: expanded)
                    .replacingTextures(textures)
                let label = "seed \(seed), step \(step)"
                XCTAssertTrue(layout.isSameBuild(as: layout.replacingTextures(textures)), label)
                for id in SceneFixtures.allIDs {
                    XCTAssertEqual(layout.texture(of: id), whole.texture(of: id), "\(label), \(id)")
                }
                XCTAssertEqual(layout.drawnTextures, whole.drawnTextures, label)
                XCTAssertEqual(
                    layout.project(camera: .standard3D, viewport: viewport, selected: 3, hovered: nil),
                    whole.project(camera: .standard3D, viewport: viewport, selected: 3, hovered: nil),
                    label)
            }
        }
    }
}
