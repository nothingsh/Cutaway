import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// The preview's cameras and switches as the model holds them: C-PREV-07 to C-PREV-09 and
/// C-SCENE-07.
final class PreviewControlsTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)

    @MainActor
    private func model() throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(
                channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")),
            newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        return model
    }

    @MainActor
    func test_C_SCENE_07_movingTheCameraDoesNotLayTheTreeOutAgain() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        let builds = model.geometryBuildCount
        model.rotate(byDragOf: 10, 5)
        model.pan(by: 3, 4)
        model.zoom(by: 2, about: ScenePoint(x: 10, y: 10), in: viewport)
        model.setLayerSpacing(80)
        model.resetCamera()
        model.setPreviewMode(.twoD)
        XCTAssertEqual(model.geometryBuildCount, builds)
    }

    @MainActor
    func test_C_PREV_07_eachModeKeepsItsCamera() throws {
        let model = try model()
        model.pan(by: 5, 0)
        XCTAssertEqual(model.camera.pan, ScenePoint(x: 5, y: 0))
        model.setPreviewMode(.threeD)
        XCTAssertEqual(model.camera, .standard3D)
        model.rotate(byDragOf: 20, 0)
        model.setPreviewMode(.twoD)
        XCTAssertEqual(model.camera.pan, ScenePoint(x: 5, y: 0))
        model.setPreviewMode(.threeD)
        XCTAssertNotEqual(model.camera.yaw, Camera.standard3D.yaw)
    }

    @MainActor
    func test_C_PREV_07_resettingResetsOnlyTheModeShown() throws {
        let model = try model()
        model.pan(by: 5, 0)
        model.setPreviewMode(.threeD)
        model.rotate(byDragOf: 20, 0)
        model.resetCamera()
        XCTAssertEqual(model.camera, .standard3D)
        XCTAssertEqual(model.cameras.twoD.pan, ScenePoint(x: 5, y: 0))
    }

    @MainActor
    func test_C_PREV_04_twoDNeitherTurnsNorSpreads() throws {
        let model = try model()
        model.rotate(byDragOf: 20, 20)
        model.setLayerSpacing(120)
        XCTAssertEqual(model.camera, .flat)
    }

    @MainActor
    func test_C_PREV_07_theSpacingStaysWithinItsRange() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        model.setLayerSpacing(500)
        XCTAssertEqual(model.camera.layerSpacing, 200)
        model.setLayerSpacing(-3)
        XCTAssertEqual(model.camera.layerSpacing, 0)
    }

    @MainActor
    func test_C_PREV_05_zoomingKeepsThePointerAndPublishesOnce() throws {
        let model = try model()
        var published = 0
        let subscription = model.$cameras.dropFirst().sink { _ in published += 1 }
        defer { subscription.cancel() }
        let pointer = ScenePoint(x: 100, y: 200)
        model.zoom(by: 2, about: pointer, in: viewport)
        XCTAssertEqual(model.camera, Camera.flat.zoomed(by: 2, about: pointer, in: viewport))
        XCTAssertEqual(published, 1)
    }

    @MainActor
    func test_C_PREV_07_aNewFocusFitsTheViewButKeepsTheTurn() throws {
        let model = try model()
        model.pan(by: 5, 5)
        model.zoom(by: 3, about: .zero, in: viewport)
        model.setPreviewMode(.threeD)
        model.rotate(byDragOf: 40, 0)
        model.setLayerSpacing(90)
        model.zoom(by: 2, about: .zero, in: viewport)
        let yaw = model.camera.yaw

        model.focus(on: 6)
        XCTAssertEqual(model.cameras.twoD, .flat)
        XCTAssertEqual(model.camera.zoom, 1)
        XCTAssertEqual(model.camera.pan, .zero)
        XCTAssertEqual(model.camera.yaw, yaw)
        XCTAssertEqual(model.camera.layerSpacing, 90)
    }

    @MainActor
    func test_C_PREV_08_showingHiddenLayersAsksForThem() throws {
        let model = try model()
        XCTAssertFalse(model.showsHiddenLayers)
        let builds = model.geometryBuildCount
        model.setShowsHiddenLayers(true)
        XCTAssertTrue(model.layout.isGhost(5))
        XCTAssertTrue(model.layout.neededTextures.contains { $0.layerID == 5 })
        XCTAssertEqual(model.geometryBuildCount, builds + 1)
        model.setShowsHiddenLayers(true)
        XCTAssertEqual(model.geometryBuildCount, builds + 1, "no change, no work")
        model.setShowsHiddenLayers(false)
        XCTAssertFalse(model.layout.isDisplayed(5))
    }

    @MainActor
    func test_C_PREV_08_imagesOfHiddenLayersAreKeptWhenTheSwitchIsOff() async throws {
        let model = try model()
        model.setShowsHiddenLayers(true)
        let image = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details").compactMap(\.group).first)
        await model.applyDetails([
            LayerDetail(layerID: 5, status: .ok, solo: nil, group: image, attributeGroups: []),
        ])
        XCTAssertNotNil(model.images[5])
        model.setShowsHiddenLayers(false)
        XCTAssertNotNil(model.images[5])
    }

    @MainActor
    func test_C_PREV_09_bordersAreOnUntilTurnedOffAndNeedNoLayout() throws {
        let model = try model()
        XCTAssertTrue(model.borders.showsBorders)
        let builds = model.geometryBuildCount
        model.setBorderStyle(.off)
        XCTAssertFalse(model.borders.showsBorders)
        model.setOnlyAppClasses(true)
        XCTAssertEqual(model.geometryBuildCount, builds)
    }

    // MARK: - Found in review

    @MainActor
    func test_C_PREV_07_aFocusThatEndsWithItsLayerFitsTheViewToo() throws {
        let model = try model()
        model.focus(on: 6)
        model.zoom(by: 5, about: ScenePoint(x: 30, y: 30), in: viewport)
        var hierarchy = try Fixtures.hierarchy()
        hierarchy.nodes.removeAll { $0.id == 6 || $0.id == 7 }
        model.apply(hierarchy)
        XCTAssertNil(model.focusedLayerID)
        XCTAssertEqual(model.camera, .flat)
    }

    @MainActor
    func test_C_PREV_07_aNewFocusIsLaidOutBeforeTheCameraMoves() throws {
        let model = try model()
        model.zoom(by: 2, about: .zero, in: viewport)
        var displayedWhenPublished: [Bool] = []
        let subscription = model.$cameras.dropFirst().sink { _ in
            displayedWhenPublished.append(model.layout.isDisplayed(1))
        }
        defer { subscription.cancel() }
        model.focus(on: 6)
        XCTAssertEqual(displayedWhenPublished, [false], "the window is outside the new focus")
    }

    @MainActor
    func test_C_PREV_08_hiddenLayersCountInTheProgress() throws {
        let model = try model()
        XCTAssertEqual(model.detailProgress.total, 7)
        model.setShowsHiddenLayers(true)
        XCTAssertEqual(model.detailProgress.total, 8, "layer 5 too")
        model.setShowsHiddenLayers(false)
        XCTAssertEqual(model.detailProgress.total, 7)
    }

    @MainActor
    func test_C_PREV_18_anArchivesSwitchIsTakenOver() throws {
        let model = try model()
        var state = model.archiveState
        state.showsConstraintEnds = true
        model.restore(state)
        XCTAssertTrue(model.showsAllConstraintEnds)
    }
}
