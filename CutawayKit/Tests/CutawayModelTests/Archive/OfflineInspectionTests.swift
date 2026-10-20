import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ARCH-05 and C-ARCH-03: an archive inspected offline, and its interface state restored.
@MainActor
final class OfflineInspectionTests: XCTestCase {
    private func inspection(
        state: ArchiveState? = nil, newLayers: InspectionStore.NewLayers = .expanded
    ) throws -> (InspectionStore, ArchiveSource) {
        let data = try Fixtures.archive(state: state?.encoded() ?? Data())
        let source = ArchiveSource(decoder: try ArchiveDecoder(data))
        return (InspectionStore(
            source: source, maxTextureDimension: 4096, newLayers: newLayers), source)
    }

    private func eventually(
        within timeout: Duration = .seconds(3), _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: - C-ARCH-05

    func test_C_ARCH_05_anArchiveIsInspectedLikeAnApp() async throws {
        let (model, _) = try inspection()
        model.enter()
        let loaded = await eventually { model.loadState == .loaded }
        XCTAssertTrue(loaded)
        XCTAssertEqual(model.tree.count, 14)

        // The screenshots come in as they do from an app.
        let imaged = await eventually {
            model.images[4]?.solo != nil && model.images[3]?.group != nil
        }
        XCTAssertTrue(imaged, "the images did not arrive")

        model.select(3)
        let attributes = await eventually {
            if case .loaded(let groups, let constraints) = model.attributes.state {
                return groups.flatMap(\.attributes).count == 22 && constraints.count == 4
            }
            return false
        }
        XCTAssertTrue(attributes, "the attributes are \(model.attributes.state)")
    }

    func test_C_ARCH_05_anArchiveIsReadOnly() async throws {
        let (model, _) = try inspection()
        model.enter()
        let loaded = await eventually { model.loadState == .loaded }
        XCTAssertTrue(loaded)
        model.select(3)
        _ = await eventually {
            if case .loaded = model.attributes.state { return true }
            return false
        }
        // What enter() learns from the source has been learnt.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.attributes.canEdit)
        XCTAssertFalse(model.canRefreshSubtrees)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineInspectionTests-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("Again.cutaway")
        model.saveArchive(to: url, cutawayVersion: "0.1.0")
        XCTAssertFalse(model.isSavingArchive)
        XCTAssertEqual(model.archiveSave, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - C-ARCH-03

    func test_C_ARCH_03_theSavedStateIsRestored() async throws {
        var cameras = PreviewCameras()
        cameras.twoD.zoom = 2
        cameras.twoD.pan = ScenePoint(x: 10, y: -20)
        cameras.threeD.yaw = 0.3
        cameras.threeD.pitch = -0.4
        cameras.threeD.zoom = 1.5
        cameras.threeD.layerSpacing = 120
        let state = ArchiveState(
            expanded: [1, 2, 4], selected: 5, focused: 2, previewMode: .threeD,
            cameras: cameras, showsHiddenLayers: true, borders: BorderOptions(style: .off))
        let (model, _) = try inspection(state: state)

        model.restore(state)
        model.enter()
        let restored = await eventually { model.focusedLayerID == 2 }
        XCTAssertTrue(restored)
        XCTAssertEqual(model.expandedLayerIDs, [1, 2, 4])
        XCTAssertEqual(model.selectedLayerID, 5)
        XCTAssertEqual(model.previewMode, .threeD)
        XCTAssertEqual(model.cameras, cameras)
        XCTAssertTrue(model.showsHiddenLayers)
        XCTAssertFalse(model.borders.showsBorders)
    }

    /// The expansion, the focus and the hidden layers of the state are taken in before the
    /// tree is laid out, so an archive of thousands of layers is laid out once as it opens
    /// A focus opens the layers above it, as focusing does.
    func test_C_SCALE_01_anArchivesStateIsTakenInWithOneLayout() async throws {
        let state = ArchiveState(
            expanded: [4], selected: 5, focused: 5, previewMode: .threeD,
            cameras: PreviewCameras(), showsHiddenLayers: true, borders: BorderOptions())
        let (model, _) = try inspection(state: state)

        model.restore(state)
        model.enter()
        let restored = await eventually { model.focusedLayerID == 5 }
        XCTAssertTrue(restored)
        XCTAssertEqual(model.geometryBuildCount, 1)
        XCTAssertEqual(model.layout.isDisplayed(5), true)
        // Layer 5 is inside 4, inside 2, inside 1.
        XCTAssertEqual(model.expandedLayerIDs, [1, 2, 4])
        XCTAssertTrue(model.showsHiddenLayers)
        XCTAssertEqual(model.selectedLayerID, 5)
    }

    /// An archive that does not say which nodes are expanded opens them as a new inspection
    /// does (C-HIER-09), before and after the tree is in; an empty list collapses them all.
    func test_C_ARCH_03_anArchiveWithoutExpandedUsesTheDefaultExpansion() async throws {
        var state = ArchiveState()
        state.selected = 3
        let (model, _) = try inspection(state: state, newLayers: .byRule)
        model.restore(state)
        model.enter()
        let loaded = await eventually { model.loadState == .loaded }
        XCTAssertTrue(loaded)
        XCTAssertEqual([1, 2, 4, 6].map(model.isExpanded), [true, true, false, false])
        XCTAssertEqual(model.selectedLayerID, 3)

        model.expandAll()
        model.restore(state)
        XCTAssertEqual(
            [1, 2, 4, 6].map(model.isExpanded), [true, true, true, true],
            "restored after the tree is in, the expansion stays as it is")
    }

    func test_C_ARCH_03_anEmptyExpandedListCollapsesEverything() async throws {
        var state = ArchiveState()
        state.expanded = []
        let (model, _) = try inspection(state: state, newLayers: .byRule)
        model.restore(state)
        model.enter()
        let loaded = await eventually { model.loadState == .loaded }
        XCTAssertTrue(loaded)
        XCTAssertEqual([1, 2, 4, 6].map(model.isExpanded), [false, false, false, false])
    }

    func test_C_ARCH_03_idsNotInTheTreeAndValuesOutOfRangeFallBack() async throws {
        var cameras = PreviewCameras()
        cameras.twoD.yaw = 1
        cameras.twoD.zoom = 50
        cameras.threeD.pitch = 3
        cameras.threeD.zoom = 0.01
        cameras.threeD.layerSpacing = 900
        let state = ArchiveState(
            expanded: [1, 2, 77], selected: 88, focused: 99, previewMode: .twoD,
            cameras: cameras, showsHiddenLayers: false, borders: BorderOptions())
        let (model, _) = try inspection()
        model.enter()
        let loaded = await eventually { model.loadState == .loaded }
        XCTAssertTrue(loaded)

        // Restored after the tree is in, it applies at once.
        model.restore(state)
        XCTAssertEqual(model.expandedLayerIDs, [1, 2])
        XCTAssertNil(model.selectedLayerID)
        XCTAssertNil(model.focusedLayerID)
        XCTAssertEqual(model.cameras.twoD.yaw, 0, "the 2D view does not turn")
        XCTAssertEqual(model.cameras.twoD.zoom, Camera.zoomRange.upperBound)
        XCTAssertEqual(model.cameras.threeD.pitch, Camera.pitchRange.upperBound)
        XCTAssertEqual(model.cameras.threeD.zoom, Camera.zoomRange.lowerBound)
        XCTAssertEqual(model.cameras.threeD.layerSpacing, Camera.spacingRange.upperBound)

        // A selection inside a collapsed node lands on that node.
        var inside = ArchiveState()
        inside.expanded = [1, 2]
        inside.selected = 5
        model.restore(inside)
        XCTAssertEqual(model.selectedLayerID, 4)
    }
}
