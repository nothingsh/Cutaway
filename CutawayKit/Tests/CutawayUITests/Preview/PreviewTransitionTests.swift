import AppKit
import CutawayModel
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// A clock the test moves on by hand; each move is one frame.
@MainActor
final class ManualClock: PreviewClock {
    var now = 0.0
    private(set) var isRunning = false
    private var tick: (@MainActor () -> Void)?

    func start(_ tick: @escaping @MainActor () -> Void) {
        isRunning = true
        self.tick = tick
    }

    func stop() {
        isRunning = false
        tick = nil
    }

    /// Moves on by `seconds` and draws a frame if the preview asked for frames.
    func advance(by seconds: Double) {
        now += seconds
        tick?()
    }
}

/// The preview goes over to another mode, or another expansion, in a short transition
/// (C-PREV-11, C-PREV-12).
final class PreviewTransitionTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")
    private static let half = PreviewMotion.duration / 2

    /// A model with the `hierarchy` fixture and the `layer-details` images.
    @MainActor
    private func model() throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        try Wait.running { await model.applyDetails(details) }
        return model
    }

    /// A preview controller in a window that is never shown, laid out at 480 × 900.
    @MainActor
    private func previewInWindow(
        _ model: InspectionStore, motion: PreviewMotion
    ) throws -> (PreviewViewController, PreviewView, NSWindow) {
        let controller = PreviewViewController(store: model, motion: motion)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 900), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 480, height: 900))
        window.layoutIfNeeded()
        // Images the model held before the preview was made are uploaded once decompressed.
        try Wait.running { await controller.texturesSettled() }
        return (controller, try XCTUnwrap(controller.preview), window)
    }

    /// The still picture of the model's state.
    @MainActor
    private func still(_ model: InspectionStore, _ preview: PreviewView, measuring: UInt64? = nil)
        -> DrawList
    {
        model.layout.project(
            camera: model.camera,
            viewport: preview.viewport,
            selected: model.selectedLayerID, hovered: model.hoveredLayerID, measuring: measuring)
    }

    private func center(_ id: UInt64, _ list: DrawList) throws -> ScenePoint {
        try XCTUnwrap(list.items.first { $0.layerID == id }?.center, "layer \(id) is drawn")
    }

    private func distance(_ a: ScenePoint, _ b: ScenePoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - C-PREV-11

    @MainActor
    func test_C_PREV_11_switchingModesTurnsTheViewOverAShortTime() throws {
        let model = try model()
        let clock = ManualClock()
        let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        let flat = still(model, preview)
        XCTAssertEqual(preview.drawList, flat)
        XCTAssertFalse(clock.isRunning)

        model.setPreviewMode(.threeD)
        XCTAssertTrue(controller.isInTransition)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(preview.drawList, flat, "it starts from what is on screen")
        let threeD = still(model, preview)

        clock.advance(by: Self.half)
        let halfway = preview.drawList
        let start = try center(3, flat), middle = try center(3, halfway), end = try center(3, threeD)
        XCTAssertGreaterThan(distance(start, middle), 1)
        XCTAssertGreaterThan(distance(middle, end), 1)
        XCTAssertLessThan(distance(start, middle), distance(start, end))

        clock.advance(by: Self.half)
        XCTAssertEqual(preview.drawList, threeD)
        XCTAssertFalse(controller.isInTransition)
        XCTAssertFalse(clock.isRunning, "no more frames (C-REND-04)")

        // Nothing is drawn once it is over.
        XCTAssertTrue(PreviewViewTests.waitForFrames(preview, atLeast: 1))
        PreviewViewTests.settle()
        let frames = preview.frameCount
        PreviewViewTests.settle()
        XCTAssertEqual(preview.frameCount, frames)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_11_switchingBackOnTheWayStartsFromTheFrameOnScreen() throws {
        let model = try model()
        let clock = ManualClock()
        let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        let flat = still(model, preview)
        model.setPreviewMode(.threeD)
        clock.advance(by: Self.half)
        let onScreen = preview.drawList

        model.setPreviewMode(.twoD)
        XCTAssertEqual(preview.drawList, onScreen)
        clock.advance(by: Self.half)
        XCTAssertNotEqual(preview.drawList, onScreen)
        XCTAssertNotEqual(preview.drawList, flat)
        clock.advance(by: Self.half)
        XCTAssertEqual(preview.drawList, flat)
        XCTAssertFalse(controller.isInTransition)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_11_movingTheCameraOnTheWayEndsTheTurn() throws {
        let moves: [(String, @MainActor (InspectionStore) -> Void)] = [
            ("a turn", { $0.rotate(byDragOf: 20, 10) }),
            ("a pan", { $0.pan(by: 15, -5) }),
            ("a zoom", { $0.zoom(by: 1.5, about: ScenePoint(x: 100, y: 100), in: Viewport(width: 480, height: 900)) }),
            ("the spacing", { $0.setLayerSpacing(90) }),
            ("a reset", { $0.resetCamera() }),
        ]
        for (name, move) in moves {
            let model = try model()
            // A 3D camera away from where it starts, so that a reset moves it.
            model.setPreviewMode(.threeD)
            model.setLayerSpacing(120)
            model.setPreviewMode(.twoD)
            let clock = ManualClock()
            let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
            model.setPreviewMode(.threeD)
            clock.advance(by: Self.half / 2)
            XCTAssertTrue(controller.isInTransition, name)

            move(model)
            XCTAssertFalse(controller.isInTransition, name)
            XCTAssertEqual(preview.drawList, still(model, preview), name)
            clock.advance(by: Self.half)
            XCTAssertFalse(clock.isRunning, name)
            withExtendedLifetime(window) {}
        }
    }

    @MainActor
    func test_C_PREV_11_distancesShowOnlyOnceTheTurnEnds() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        model.select(3)
        let clock = ManualClock()
        let (_, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        model.hover(2)
        preview.onMeasuringChange?(true)
        XCTAssertEqual(preview.drawList, still(model, preview, measuring: 2), "in 3D")
        XCTAssertNotNil(preview.drawList.measurement)

        for mode in [PreviewMode.twoD, .threeD] {
            model.setPreviewMode(mode)
            XCTAssertNil(preview.drawList.measurement, "\(mode)")
            clock.advance(by: Self.half)
            XCTAssertNil(preview.drawList.measurement, "\(mode) on the way")
            clock.advance(by: Self.half)
            XCTAssertEqual(preview.drawList, still(model, preview, measuring: 2), "\(mode)")
            XCTAssertEqual(
                preview.drawList.measurement?.labels.map(\.value), [96.5, 96.5, 108, 720],
                "\(mode)")
        }
        withExtendedLifetime(window) {}
    }

    /// In 3D the levels go through fractions while the expansion changes: the distances show
    /// once the change is over (C-PREV-14). In 2D they stay on the way (C-PREV-10).
    @MainActor
    func test_C_PREV_14_distancesShowOnceAChangeOfTheExpansionEndsIn3D() throws {
        for mode in [PreviewMode.threeD, .twoD] {
            let model = try model()
            model.setPreviewMode(mode)
            model.select(3)
            let clock = ManualClock()
            let (controller, preview, window) = try previewInWindow(
                model, motion: .paced(by: clock))
            model.hover(2)
            preview.onMeasuringChange?(true)
            XCTAssertNotNil(preview.drawList.measurement, "\(mode)")

            model.setExpanded(6, false)
            XCTAssertTrue(controller.isInTransition, "\(mode)")
            XCTAssertEqual(preview.drawList.measurement == nil, mode == .threeD, "\(mode)")
            clock.advance(by: Self.half)
            XCTAssertEqual(
                preview.drawList.measurement == nil, mode == .threeD, "\(mode) on the way")
            clock.advance(by: Self.half)
            XCTAssertFalse(controller.isInTransition, "\(mode)")
            XCTAssertEqual(preview.drawList, still(model, preview, measuring: 2), "\(mode)")
            XCTAssertEqual(
                preview.drawList.measurement?.labels.map(\.value), [96.5, 96.5, 108, 720],
                "\(mode)")
            withExtendedLifetime(window) {}
        }
    }

    /// The window is not on screen: nobody would see a transition, and the display would not
    /// pace it.
    @MainActor
    func test_C_PREV_11_aPreviewOffScreenShowsTheModeAtOnce() throws {
        let model = try model()
        let (controller, preview, window) = try previewInWindow(model, motion: .system)
        XCTAssertFalse(window.isVisible)
        model.setPreviewMode(.threeD)
        XCTAssertFalse(controller.isInTransition)
        XCTAssertEqual(preview.drawList, still(model, preview))
        withExtendedLifetime(window) {}
    }

    // MARK: - C-PREV-12

    @MainActor
    func test_C_PREV_12_everyChangeOfTheExpansionGoesOver() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        let clock = ManualClock()
        let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        let changes: [(String, @MainActor () throws -> Void)] = [
            ("collapsing a row", { model.setExpanded(2, false) }),
            ("expanding everything", { model.expandAll() }),
            ("collapsing with ⌥", { model.setExpanded([2, 6], false) }),
            ("expanding a row", { model.setExpanded(2, true) }),
            ("expanding to a depth", { model.expand(toDepth: 1) }),
            ("collapsing everything", { model.collapseAll() }),
            ("expanding everything again", { model.expandAll() }),
        ]
        for (name, change) in changes {
            let before = preview.drawList
            try change()
            XCTAssertTrue(controller.isInTransition, name)
            // Layers on screen stay where they are; layers that appear start inside their node.
            for item in before.items {
                let first = try XCTUnwrap(preview.drawList.items.first { $0.layerID == item.layerID })
                for (p, q) in zip(first.points, item.points) {
                    XCTAssertEqual(distance(p, q), 0, accuracy: 1e-9, "\(name): layer \(item.layerID)")
                }
            }
            let after = still(model, preview)
            XCTAssertNotEqual(after, before, name)

            clock.advance(by: Self.half)
            XCTAssertNotEqual(preview.drawList, before, name)
            XCTAssertNotEqual(preview.drawList, after, name)
            clock.advance(by: Self.half)
            XCTAssertEqual(preview.drawList, after, name)
            XCTAssertFalse(controller.isInTransition, name)
            XCTAssertFalse(clock.isRunning, "\(name): no more frames (C-REND-04)")
        }
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_12_otherChangesOfTheLayoutShowAtOnceAndEndTheTransition() throws {
        let changes: [(String, @MainActor (InspectionStore) throws -> Void)] = [
            ("a focus", { $0.focus(on: 2) }),
            ("hidden layers shown or not", { $0.setShowsHiddenLayers(!$0.showsHiddenLayers) }),
            ("another tree", { model in
                // Without layer 9, or with it again.
                var hierarchy = try Fixtures.hierarchy()
                if model.tree.contains(9) { hierarchy.nodes.removeAll { $0.id == 9 } }
                model.apply(hierarchy)
            }),
        ]
        for (name, change) in changes {
            let model = try model()
            model.setPreviewMode(.threeD)
            let clock = ManualClock()
            let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
            try change(model)
            XCTAssertFalse(controller.isInTransition, "\(name) alone")
            XCTAssertEqual(preview.drawList, still(model, preview), name)

            model.setExpanded(6, false)
            clock.advance(by: Self.half / 2)
            XCTAssertTrue(controller.isInTransition, name)
            if name == "a focus" { model.focus(on: nil) } else { try change(model) }
            XCTAssertFalse(controller.isInTransition, "\(name) on the way")
            XCTAssertFalse(clock.isRunning, "\(name): the clock stops at once")
            XCTAssertEqual(preview.drawList, still(model, preview), name)
            clock.advance(by: Self.half)
            XCTAssertFalse(clock.isRunning, name)
            withExtendedLifetime(window) {}
        }
    }

    /// An equal tree is not laid out again (C-HIER-02): there is nothing new to show, and the
    /// transition goes on.
    @MainActor
    func test_C_PREV_12_anEqualTreeOnTheWayLeavesTheTransitionGoing() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        let clock = ManualClock()
        let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        model.setExpanded(6, false)
        clock.advance(by: Self.half / 2)
        model.apply(try Fixtures.hierarchy())
        XCTAssertTrue(controller.isInTransition)
        clock.advance(by: PreviewMotion.duration)
        XCTAssertEqual(preview.drawList, still(model, preview))
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_12_imagesArrivingOnTheWayAreUsedWithoutStartingAgain() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        let clock = ManualClock()
        let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        model.setExpanded(2, false)
        clock.advance(by: Self.half)
        let halfway = preview.drawList

        var red = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 3 })
        red.layerID = 2
        try Wait.running { await model.applyDetails([red]) }
        XCTAssertTrue(controller.isInTransition)
        let group = try XCTUnwrap(model.images[2]?.textures(layerID: 2).group)
        XCTAssertEqual(
            preview.drawList.items.map(\.points), halfway.items.map(\.points), "where it was")
        clock.advance(by: Self.half)
        XCTAssertEqual(preview.drawList, still(model, preview))
        XCTAssertEqual(preview.drawList.items.first { $0.layerID == 2 }?.texture, group)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_12_aChangeOnTheWayStartsFromTheFrameOnScreen() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        let clock = ManualClock()
        let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        model.setExpanded(2, false)
        clock.advance(by: Self.half)
        let onScreen = preview.drawList

        model.setExpanded(2, true)
        XCTAssertEqual(preview.drawList, onScreen)
        XCTAssertTrue(controller.isInTransition)
        clock.advance(by: PreviewMotion.duration)
        XCTAssertEqual(preview.drawList, still(model, preview))
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_12_theSelectionMovesWithItsLayer() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        model.setExpanded(6, false)
        let clock = ManualClock()
        let (_, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        let node = try center(6, preview.drawList)
        model.setExpanded(6, true)
        model.select(7)
        let end = try center(7, still(model, preview))
        clock.advance(by: Self.half)
        let item = try XCTUnwrap(preview.drawList.items.first { $0.layerID == 7 })
        XCTAssertEqual(item.highlight, .selected)
        XCTAssertGreaterThan(distance(item.center, node), 1, "rising out of layer 6")
        XCTAssertGreaterThan(distance(item.center, end), 1, "not there yet")
        withExtendedLifetime(window) {}
    }
}
