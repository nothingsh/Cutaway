import CutawayModel
import CutawayScene
import CutawayTestSupport
import CutawayWire
import XCTest

/// The layer tree turned into the scene's input (C-SCENE-01 starts from it).
final class SceneConversionTests: XCTestCase {
    func test_C_SCENE_01_theFixtureBecomesSceneLayersInTheOrderOfTheWire() throws {
        let layers = try LayerTree(try Fixtures.hierarchy()).sceneLayers()
        let byID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })

        XCTAssertEqual(layers.map(\.id), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        XCTAssertEqual(layers.map(\.parentID), [0, 1, 2, 2, 4, 10, 4, 4, 2, 6, 2, 2, 2, 13])

        let scroll = try XCTUnwrap(byID[6])
        XCTAssertEqual(scroll.bounds, SceneRect(x: 0, y: 100, width: 300, height: 200))
        XCTAssertEqual(scroll.position, ScenePoint(x: 196.5, y: 600))

        XCTAssertEqual(byID[8]?.anchorPoint, ScenePoint(x: 0, y: 0))
        XCTAssertEqual(byID[3]?.anchorPoint, ScenePoint(x: 0.5, y: 0.5))

        let card = try XCTUnwrap(byID[4]).transform
        XCTAssertEqual(card.m11, 0.8660254037844387)
        XCTAssertEqual(card.m12, 0.5)
        XCTAssertEqual(card.m21, -0.5)
        XCTAssertEqual(card.m22, 0.8660254037844387)
        XCTAssertEqual(byID[3]?.transform, .identity)

        XCTAssertEqual(byID[5]?.isHidden, true)
        XCTAssertEqual(byID[5]?.opacity, 0.5)
        XCTAssertEqual(byID[3]?.opacity, 1)
        XCTAssertTrue(layers.allSatisfy { $0.solo == nil && $0.group == nil })
        // The app excludes 13 and 14 from images (C-DET-11).
        XCTAssertEqual(layers.filter { !$0.capturesImage }.map(\.id), [13, 14])
    }

    func test_C_SCENE_01_absentGeometryTakesTheDefaults() throws {
        // LayerTreeTests.node leaves bounds, position, anchor point and transform out.
        let tree = try LayerTree(Hierarchy(nodes: [LayerTreeTests.node(1)], keyWindowID: 0))
        let layer = try XCTUnwrap(tree.sceneLayers().first)

        XCTAssertEqual(layer.bounds, .zero)
        XCTAssertEqual(layer.position, .zero)
        XCTAssertEqual(layer.anchorPoint, ScenePoint(x: 0.5, y: 0.5))
        XCTAssertEqual(layer.transform, .identity)
    }

    func test_C_SCENE_03_theTexturesGoWithTheirLayers() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        let solo = TextureKey(layerID: 4, kind: .solo, revision: 1)
        let group = TextureKey(layerID: 4, kind: .group, revision: 2)
        let layers = tree.sceneLayers(textures: [4: LayerTextures(solo: solo, group: group)])

        XCTAssertEqual(layers[3].solo, solo)
        XCTAssertEqual(layers[3].group, group)
        XCTAssertNil(layers[2].solo)
        XCTAssertNil(layers[2].group)
    }

    // MARK: - The scene's tests make their input without the model

    func test_C_SCENE_01_theSceneTestsInputIsTheTreesOwn() throws {
        let textures: [UInt64: LayerTextures] = [4: LayerTextures(
            solo: TextureKey(layerID: 4, kind: .solo, revision: 1),
            group: TextureKey(layerID: 4, kind: .group, revision: 2))]
        XCTAssertEqual(
            try SceneInput.hierarchyFixture(textures: textures),
            try LayerTree(try Fixtures.hierarchy()).sceneLayers(textures: textures))
    }

    func test_C_SCALE_01_theScaleSceneLayersAreTheTreesOwn() throws {
        XCTAssertEqual(
            try SceneInput.scaleScene(), try LayerTree(ScaleScene.hierarchy()).sceneLayers())
    }
}
