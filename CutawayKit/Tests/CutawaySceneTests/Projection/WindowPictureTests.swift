import CutawayScene
import XCTest

/// C-SCENE-14: seen square on, a window whose `group` came composited is drawn as that picture.
/// Its layers draw no images and stay where they are, to be outlined and pointed at.
final class WindowPictureTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)
    private static let picture = TextureKey(layerID: 1, kind: .group, revision: 100)

    /// The `hierarchy` fixture, fully expanded, every layer with a solo of its own and layer 1
    /// with `Self.picture`.
    private func layout(
        composited: Bool = true, focus: UInt64? = nil, showsHidden: Bool = false
    ) throws -> SceneLayout {
        var textures: [UInt64: LayerTextures] = [:]
        for id in SceneFixtures.allIDs {
            textures[id] = LayerTextures(solo: TextureKey(layerID: id, kind: .solo, revision: id))
        }
        textures[1]?.group = Self.picture
        textures[1]?.groupIsComposited = composited
        return SceneLayout(
            layers: try SceneFixtures.hierarchyLayers(), expanded: SceneFixtures.allIDs,
            focus: focus, showsHidden: showsHidden
        ).replacingTextures(textures)
    }

    private func drawn(_ layout: SceneLayout, _ camera: Camera = .flat) -> [TextureKey] {
        layout.project(camera: camera, viewport: viewport, selected: nil, hovered: nil)
            .items.compactMap(\.texture)
    }

    func test_C_SCENE_14_inTwoDTheWindowIsItsPictureAndItsLayersDrawNoImages() throws {
        XCTAssertEqual(drawn(try layout()), [Self.picture])
    }

    func test_C_SCENE_14_aGroupThatIsNotCompositedChangesNothing() throws {
        let layout = try layout(composited: false)
        XCTAssertFalse(layout.usesWindowPictures)
        XCTAssertFalse(drawn(layout).contains(Self.picture))
        XCTAssertGreaterThan(drawn(layout).count, 1)
    }

    func test_C_SCENE_14_threeDFocusAndHiddenLayersDrawTheLayers() throws {
        XCTAssertGreaterThan(drawn(try layout(), .standard3D).count, 1)
        for layout in [try layout(focus: 2), try layout(showsHidden: true)] {
            XCTAssertFalse(layout.usesWindowPictures)
            XCTAssertFalse(drawn(layout).contains(Self.picture))
        }
    }

    func test_C_SCENE_14_whatIsPointedAtIsTheSameWithThePicture() throws {
        let plain = try layout(composited: false), pictured = try layout()
        let camera = Camera.flat
        for (x, y) in [(10.0, 10.0), (240.0, 450.0), (100.0, 300.0), (470.0, 890.0)] {
            let point = ScenePoint(x: x, y: y)
            XCTAssertEqual(
                pictured.hitTest(point: point, camera: camera, viewport: viewport),
                plain.hitTest(point: point, camera: camera, viewport: viewport), "\(point)")
        }
        let items = { (layout: SceneLayout) in
            layout.project(camera: camera, viewport: self.viewport, selected: nil, hovered: nil)
                .items.map(\.layerID)
        }
        XCTAssertEqual(items(pictured), items(plain), "the same outlines")
    }

    func test_C_SCENE_14_thePictureIsKeptAndSoAreTheLayersImages() throws {
        let kept = try layout().drawnTextures
        XCTAssertTrue(kept.contains(Self.picture))
        XCTAssertTrue(kept.contains(TextureKey(layerID: 3, kind: .solo, revision: 3)), "for 3D")
    }

    func test_C_SCENE_14_eachWindowGoesByItsOwnGroup() throws {
        let other = SceneFixtures.layer(100, x: 0, y: 0, width: 100, height: 100)
        let child = SceneFixtures.layer(101, parent: 100, x: 0, y: 0, width: 50, height: 50)
        let solo = TextureKey(layerID: 101, kind: .solo, revision: 1)
        var textures: [UInt64: LayerTextures] = [:]
        textures[1] = LayerTextures(group: Self.picture, groupIsComposited: true)
        textures[101] = LayerTextures(solo: solo)
        let layout = SceneLayout(
            layers: try SceneFixtures.hierarchyLayers() + [other, child],
            expanded: SceneFixtures.allIDs.union([100, 101])
        ).replacingTextures(textures)
        XCTAssertEqual(Set(drawn(layout)), [Self.picture, solo])
        XCTAssertEqual(layout.windowGroupNeeds.map(\.layerID), [1, 100])
    }
}
