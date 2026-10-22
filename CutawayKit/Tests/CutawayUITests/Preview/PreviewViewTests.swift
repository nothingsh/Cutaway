import AppKit
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest
@testable import CutawayModel
@testable import CutawayRender

@testable import CutawayUI

/// The preview as it runs: frames counted through AppKit's display cycle, the draw list it
/// shows, pointer events, and its offscreen snapshot (C-REND-04, C-PREV-01 to C-PREV-03).
final class PreviewViewTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    /// A model with the `hierarchy` fixture and the `layer-details` images, every layer
    /// expanded unless asked otherwise.
    @MainActor
    private func model(newLayers: InspectionStore.NewLayers = .expanded) throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: newLayers)
        model.apply(try Fixtures.hierarchy())
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        try Wait.running { await model.applyDetails(details) }
        return model
    }

    /// A preview controller in a window that is never shown, laid out at 480 × 900.
    /// `settlesTextures` waits for the images the model held before, which an async test cannot
    /// do here: it waits with `texturesSettled()` itself.
    @MainActor
    private func previewInWindow(
        _ model: InspectionStore, settlesTextures: Bool = true
    ) throws -> (PreviewViewController, PreviewView, NSWindow) {
        let controller = PreviewViewController(store: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 900), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 480, height: 900))
        window.layoutIfNeeded()
        // Images the model held before the preview was made are uploaded once decompressed.
        if settlesTextures { try Wait.running { await controller.texturesSettled() } }
        let preview = try XCTUnwrap(controller.preview)
        return (controller, preview, window)
    }

    /// Turns the run loop until the preview has drawn `count` frames, or `seconds` pass.
    @MainActor
    static func waitForFrames(
        _ preview: PreviewView, atLeast count: Int, within seconds: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while preview.frameCount < count, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return preview.frameCount >= count
    }

    /// Turns the run loop for a while, long enough for any frame that is due to be drawn.
    @MainActor
    static func settle(_ seconds: TimeInterval = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// A mouse event at a point of `view`.
    @MainActor
    static func mouse(
        _ type: NSEvent.EventType, at point: NSPoint, clickCount: Int = 1, in view: NSView
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: view.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: clickCount, pressure: 1)!
    }

    @MainActor
    static func exit(_ view: NSView) -> NSEvent {
        NSEvent.enterExitEvent(
            with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
            trackingNumber: 0, userData: nil)!
    }

    // MARK: - C-REND-04: drawing on demand

    @MainActor
    func test_C_REND_04_nothingIsRedrawnWhileNothingChanges() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "the first frame")
        Self.settle()
        let settled = preview.frameCount
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled, "idle")

        // The same values again change nothing.
        model.select(nil)
        model.hover(nil)
        model.setPreviewMode(.twoD)
        try Wait.running { await model.applyDetails([]) }
        model.setExpanded(2, true)
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled, "nothing new")

        // Each real change is one frame.
        model.setPreviewMode(.threeD)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: settled + 1), "a frame was drawn")
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled + 1, "a new camera")

        model.select(3)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: settled + 2), "a frame was drawn")
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled + 2, "a new selection")

        try Wait.running { await model.applyDetails(
            try Fixtures.layerDetails(scenario: "layer-details").filter { $0.layerID == 3 }) }
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: settled + 3), "a frame was drawn")
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled + 3, "a new image")
        withExtendedLifetime(window) {}
    }

    /// A new size is drawn at once, in the resize's transaction, and only once: what shows the
    /// window at its new size, the full-screen animation too, has the frame for it.
    @MainActor
    func test_C_REND_04_aNewSizeIsDrawnOnceWithTheResize() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertTrue(preview.presentsWithTransaction)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "the first frame")
        Self.settle()
        let settled = preview.frameCount
        window.setContentSize(NSSize(width: 600, height: 900))
        // Before the run loop turns.
        XCTAssertEqual(preview.frameCount, settled + 1, "drawn with the resize")
        XCTAssertFalse(preview.isDrawingPending)
        XCTAssertEqual(preview.drawableSize.width, 600 * window.backingScaleFactor)
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled + 1, "nothing more")
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_REND_04_thePreviewTellsWhetherWhatItShowsIsDrawnYet() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "the first frame")
        Self.settle()
        XCTAssertFalse(preview.isDrawingPending, "the first list is drawn")

        let frames = preview.frameCount
        model.select(3)
        XCTAssertTrue(preview.isDrawingPending, "a new selection is drawn with the next frame")
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: frames + 1), "a frame was drawn")
        XCTAssertFalse(preview.isDrawingPending, "the selection is drawn")

        // The same list again asks for no frame.
        model.select(3)
        XCTAssertFalse(preview.isDrawingPending)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_REND_04_changesInOneTurnAreDrawnOnce() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "a frame was drawn")
        Self.settle()
        let settled = preview.frameCount

        model.select(3)
        model.select(4)
        model.hover(6)
        model.setPreviewMode(.threeD)
        model.setExpanded(6, false)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: settled + 1), "a frame was drawn")
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled + 1)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_REND_04_resizingRedrawsAtTheNewSize() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "a frame was drawn")
        Self.settle()
        let settled = preview.frameCount
        let before = try XCTUnwrap(preview.imagePoint(ofCenterOf: 3))

        window.setContentSize(NSSize(width: 600, height: 900))
        window.layoutIfNeeded()
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: settled + 1), "a frame at the new size")
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled + 1, "one frame for one resize")
        let after = try XCTUnwrap(preview.imagePoint(ofCenterOf: 3))
        let scale = window.backingScaleFactor
        XCTAssertEqual(after.x - before.x, 60 * scale, accuracy: 0.5, "re-centred in the wider view")
        let image = try preview.snapshot()
        XCTAssertEqual(image.pixelWidth, Int(600 * scale))
        XCTAssertEqual(image.pixelHeight, Int(900 * scale))
    }

    @MainActor
    func test_C_REND_04_aNewPixelDensityRedrawsOnce() throws {
        // Moving the window to a screen of another density changes the drawable, not the
        // draw list, which is in points.
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "a frame was drawn")
        Self.settle()
        let settled = preview.frameCount

        preview.viewDidChangeBackingProperties()
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: settled + 1), "a frame was drawn")
        Self.settle()
        XCTAssertEqual(preview.frameCount, settled + 1)
        withExtendedLifetime(window) {}
    }

    // MARK: - The picture

    @MainActor
    func test_C_REND_01_thePreviewShowsTheImagesWhereTheLayersAre() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "a frame was drawn")
        let image = try preview.snapshot()
        XCTAssertEqual(image.pixelWidth, Int(480 * window.backingScaleFactor))
        let red = try XCTUnwrap(preview.imagePoint(ofCenterOf: 3))
        let green = try XCTUnwrap(preview.imagePoint(ofCenterOf: 4))
        XCTAssertEqual(
            image.pixel(x: Int(red.x), y: Int(red.y)), Pixel(blue: 0, green: 0, red: 255, alpha: 255))
        XCTAssertEqual(
            image.pixel(x: Int(green.x), y: Int(green.y)),
            Pixel(blue: 0, green: 255, red: 0, alpha: 255))
    }

    @MainActor
    func test_C_SCENE_03_collapsingALayerDrawsItsGroupImage() throws {
        // Layer 6 (the scroll view) gets a group image of layer 3's red; while expanded it is
        // drawn without an image (it has a sublayer, and no solo), collapsed with the group.
        let model = try model()
        var red = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 3 })
        red.layerID = 6
        try Wait.running { await model.applyDetails([red]) }
        let (controller, preview, window) = try previewInWindow(model)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "a frame was drawn")
        XCTAssertNotNil(preview.drawList.items.first { $0.layerID == 6 })
        XCTAssertNil(preview.drawList.items.first { $0.layerID == 6 }?.texture)
        // The group image is held, but not drawn, so it has no texture (C-SCALE-02); once
        // collapsed it is drawn, and its texture made.
        let group = try XCTUnwrap(model.images[6]?.textures(layerID: 6).group)
        XCTAssertNil(preview.textures.texture(for: group))

        model.setExpanded(6, false)
        XCTAssertEqual(preview.drawList.items.first { $0.layerID == 6 }?.texture, group)
        try Wait.running { await controller.texturesSettled() }
        XCTAssertNotNil(preview.textures.texture(for: group))
        withExtendedLifetime(window) {}
    }

    // MARK: - C-PREV-03: hover

    @MainActor
    func test_C_PREV_03_pointingAtAnEmptyPreviewHoversNothing() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertEqual(preview.drawList, .empty)
        let middle = NSPoint(x: preview.bounds.midX, y: preview.bounds.midY)
        preview.mouseMoved(with: Self.mouse(.mouseMoved, at: middle, in: preview))
        Self.click(at: middle, in: preview)
        XCTAssertNil(model.hoveredLayerID)
        XCTAssertNil(model.selectedLayerID)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_03_theHoverGoesWhenTheWindowStopsBeingKey() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let center = try XCTUnwrap(preview.viewPoint(ofCenterOf: 3))
        preview.mouseMoved(with: Self.mouse(.mouseMoved, at: center, in: preview))
        XCTAssertEqual(model.hoveredLayerID, 3)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertNil(model.hoveredLayerID)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_03_theHoverGoesWhenThePreviewLeavesItsWindow() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let center = try XCTUnwrap(preview.viewPoint(ofCenterOf: 3))
        preview.mouseMoved(with: Self.mouse(.mouseMoved, at: center, in: preview))
        XCTAssertEqual(model.hoveredLayerID, 3)

        preview.removeFromSuperview()
        XCTAssertNil(model.hoveredLayerID)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_03_aNewProjectionHoversWhatIsUnderTheStillPointer() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let center = try XCTUnwrap(preview.viewPoint(ofCenterOf: 3))
        preview.mouseMoved(with: Self.mouse(.mouseMoved, at: center, in: preview))
        XCTAssertEqual(model.hoveredLayerID, 3)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1))
        Self.settle()
        let settled = preview.frameCount

        model.setPreviewMode(.threeD)
        // The same point of the view, as the draw list counts: from the top left.
        let point = ScenePoint(x: center.x, y: preview.bounds.height - center.y)
        let underPointer = preview.drawList.layer(at: point)
        XCTAssertNotEqual(underPointer, 3, "pick a point that another layer covers in 3D")
        XCTAssertEqual(model.hoveredLayerID, underPointer)

        // Hovering again redraws once more, and then nothing: no loop.
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: settled + 1))
        Self.settle()
        XCTAssertLessThanOrEqual(preview.frameCount, settled + 2)
        withExtendedLifetime(window) {}
    }

    // MARK: - In the inspection

    /// An inspector window that is never shown, at its starting size.
    @MainActor
    private func inspectionInWindow(
        _ model: InspectionStore
    ) throws -> (InspectorSplitViewController, PreviewView, InspectorWindowController) {
        let controller = InspectorWindowController(
            location: .simulator(port: 48160), entry: nil, store: model)
        // Images the model held before the preview was made are uploaded once decompressed.
        let previewController = controller.splitController.previewController
        try Wait.running { await previewController.texturesSettled() }
        let preview = try XCTUnwrap(controller.splitController.previewController.preview)
        return (controller.splitController, preview, controller)
    }

    /// The 2D / 3D control in an inspector window's toolbar.
    @MainActor
    private func modeControl(_ window: InspectorWindowController) throws -> NSSegmentedControl {
        let control = try XCTUnwrap(window.modeControl)
        XCTAssertEqual(
            control.accessibilityIdentifier(), InspectorWindowController.modeIdentifier)
        return control
    }

    /// The list the preview should show for the model's state.
    @MainActor
    private func expectedList(
        _ model: InspectionStore, _ camera: Camera, _ preview: PreviewView
    ) -> DrawList {
        SceneLayout(
            layers: model.tree.sceneLayers(images: model.images), expanded: model.expandedLayerIDs
        ).project(
            camera: camera,
            viewport: preview.viewport,
            selected: model.selectedLayerID, hovered: model.hoveredLayerID)
    }

    @MainActor
    func test_C_PREV_02_comingBackShowsThePreviewAsItWasLeft() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        model.select(4)
        do {
            let (_, preview, window) = try inspectionInWindow(model)
            XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "a frame was drawn")
            withExtendedLifetime(window) {}
        }
        // A new inspection over the same model.
        let (_, preview, window) = try inspectionInWindow(model)
        let control = try modeControl(window)
        XCTAssertEqual(control.selectedSegment, 1)
        XCTAssertEqual(preview.drawList, expectedList(model, .standard3D, preview))
        XCTAssertEqual(preview.drawList.items.first { $0.layerID == 4 }?.highlight, .selected)
        XCTAssertNotNil(preview.textures.texture(
            for: try XCTUnwrap(model.images[4]?.textures(layerID: 4).solo)))
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "a frame was drawn")
        let image = try preview.snapshot()
        let point = try XCTUnwrap(preview.imagePoint(ofCenterOf: 3))
        XCTAssertEqual(image.pixel(x: Int(point.x), y: Int(point.y)).red, 255)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_DET_02_leavingTheInspectionReleasesThePreviewAndItsTextures() throws {
        let model = AppListStore()
        let location = AppLocation.simulator(port: 48160)
        let demo = AppInfo(
            name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
            deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
            screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")
        model.apply(.found(location, demo, Session(channel: InertChannel(), client: Self.client)))
        let coordinator = WindowCoordinator(store: model, discoversDevices: false)
        // What is checked is Cutaway's own references (`ClosingWindow`).
        coordinator.animatesWindows = false

        weak var inspector: InspectorWindowController?
        weak var previewController: PreviewViewController?
        weak var preview: PreviewView?
        weak var textures: TextureCache?
        weak var window: NSWindow?
        try autoreleasepool {
            model.inspect(location)
            let shownInspector = try XCTUnwrap(coordinator.inspector)
            let shownController = shownInspector.splitController.previewController
            let shown = try XCTUnwrap(shownController.preview)
            inspector = shownInspector
            previewController = shownController
            preview = shown
            textures = shown.textures
            window = shownInspector.window
            // Closing the window leaves the inspection.
            shownInspector.close()
        }
        let deadline = Date().addingTimeInterval(8)
        while textures != nil || previewController != nil || preview != nil || inspector != nil,
              Date() < deadline
        {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        // Seen once on a busy machine whose display may have been asleep: the message says
        // whether it is.
        let asleep = (CGDisplayIsAsleep(CGMainDisplayID()) != 0 ? " (the display is asleep)" : "")
            + ClosingWindow.lingeringNote(window)
        XCTAssertNil(model.inspectedApp)
        XCTAssertNil(inspector, "the inspector window's controller outlived it\(asleep)")
        XCTAssertNil(
            previewController, "the preview's controller outlived the inspection\(asleep)")
        XCTAssertNil(preview, "the preview view outlived the inspection\(asleep)")
        XCTAssertNil(textures, "the textures outlived the inspection\(asleep)")

        // Entering again makes a new preview, which draws.
        model.inspect(location)
        let again = try XCTUnwrap(coordinator.inspector?.splitController.previewController.preview)
        coordinator.inspector?.window?.layoutIfNeeded()
        XCTAssertTrue(Self.waitForFrames(again, atLeast: 1), "the new preview did not draw")
        coordinator.inspector?.close()
        coordinator.launcher.close()
    }

    @MainActor
    func test_C_ATTR_01_clickingTheSelectedLayerAgainRetriesItsAttributes() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps.append(.expect(.getLayerDetails, as: 90))  // the attributes, never answered
        steps += try MockScript.fixtures("layer-details").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, requestTimeout: .milliseconds(300))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)
        let (controller, preview, window) = try previewInWindow(model, settlesTextures: false)
        await controller.texturesSettled()
        let center = try XCTUnwrap(preview.viewPoint(ofCenterOf: 3))

        Self.click(at: center, in: preview)
        XCTAssertEqual(model.selectedLayerID, 3)
        let failed = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(failed)

        // The panel says to click the layer again: a click in the preview does, too.
        Self.click(at: center, in: preview)
        let loaded = await Wait.until {
            if case .loaded = await model.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded, "stayed \(model.attributes.state)")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - Images the texture cache refuses

    @MainActor
    func test_C_REND_05_anImageTheCacheRefusesIsNotTriedAgain() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertTrue(Self.waitForFrames(preview, atLeast: 1), "a frame was drawn")
        let refusedBefore = preview.textures.refusedCount

        // One pixel wider than a texture can be.
        let width = Renderer.maxTextureDimension(of: try XCTUnwrap(preview.device)) + 1
        let pixels = Data(repeating: 0, count: width * 4)
        let compressed = try (pixels as NSData).compressed(using: .lzfse) as Data
        let wide = EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: UInt32(width), pixelHeight: 1,
            bytesPerRow: UInt32(width * 4), scale: 1, data: compressed)
        try Wait.running { await model.applyDetails([LayerDetail(
            layerID: 8, status: .ok, solo: nil, group: wide, attributeGroups: [])]) }
        XCTAssertEqual(preview.textures.refusedCount, refusedBefore + 1)

        // Another image arrives; the refused one is not offered to the cache again.
        try Wait.running { await model.applyDetails(
            try Fixtures.layerDetails(scenario: "layer-details").filter { $0.layerID == 3 }) }
        XCTAssertEqual(preview.textures.refusedCount, refusedBefore + 1)
        withExtendedLifetime(window) {}
    }

    // MARK: - C-PREV-04 to 06: clicks and drags

    /// A click as the mouse makes it: down, then up at the same point.
    @MainActor
    static func click(at point: NSPoint, in preview: PreviewView) {
        preview.mouseDown(with: mouse(.leftMouseDown, at: point, in: preview))
        preview.mouseUp(with: mouse(.leftMouseUp, at: point, in: preview))
    }

    /// Down at `from`, dragged through `steps` to `to`, up at `to`.
    @MainActor
    static func drag(
        from: NSPoint, to: NSPoint, steps: Int = 4, option: Bool = false, in preview: PreviewView
    ) {
        let flags: NSEvent.ModifierFlags = option ? [.option] : []
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: preview.convert(point, to: nil), modifierFlags: flags,
                timestamp: 0, windowNumber: preview.window?.windowNumber ?? 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        preview.mouseDown(with: event(.leftMouseDown, from))
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            preview.mouseDragged(with: event(.leftMouseDragged, NSPoint(
                x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)))
        }
        preview.mouseUp(with: event(.leftMouseUp, to))
    }

    /// A double click as the mouse makes it: a click, then a second one that counts two.
    @MainActor
    static func doubleClick(at point: NSPoint, in preview: PreviewView) {
        click(at: point, in: preview)
        preview.mouseDown(with: mouse(.leftMouseDown, at: point, clickCount: 2, in: preview))
        preview.mouseUp(with: mouse(.leftMouseUp, at: point, clickCount: 2, in: preview))
    }

    // MARK: - C-PREV-13: double clicks

    @MainActor
    func test_C_PREV_13_doubleClickingNothingOrDraggingChangesNothing() throws {
        let model = try model(newLayers: .byRule)
        let (_, preview, window) = try previewInWindow(model)
        let collapsed = model.tree.ids.filter { !model.isExpanded($0) }

        Self.doubleClick(at: NSPoint(x: 3, y: 3), in: preview)
        XCTAssertNil(model.selectedLayerID)

        // The second press of a double click turned into a drag.
        let card = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        Self.click(at: card, in: preview)
        let far = NSPoint(x: card.x + 40, y: card.y)
        preview.mouseDown(with: Self.mouse(.leftMouseDown, at: card, clickCount: 2, in: preview))
        preview.mouseDragged(with: Self.mouse(.leftMouseDragged, at: far, in: preview))
        preview.mouseUp(with: Self.mouse(.leftMouseUp, at: far, clickCount: 2, in: preview))

        XCTAssertEqual(model.tree.ids.filter { !model.isExpanded($0) }, collapsed)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_13_aLostConnectionTakesNoDoubleClicks() throws {
        let model = try model(newLayers: .byRule)
        let (_, preview, window) = try previewInWindow(model)
        let card = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        model.connectionLost()

        Self.doubleClick(at: card, in: preview)
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertNil(model.selectedLayerID)
        withExtendedLifetime(window) {}
    }

    // MARK: - C-PREV-15: the context menu

    /// The menu a right click at `point` opens, or nil for none.
    @MainActor
    static func contextMenu(at point: NSPoint, in preview: PreviewView) -> NSMenu? {
        preview.menu(for: mouse(.rightMouseDown, at: point, in: preview))
    }

    @MainActor
    func test_C_PREV_15_aLostConnectionOpensNoMenu() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let card = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        model.connectionLost()
        XCTAssertNil(Self.contextMenu(at: card, in: preview))
        XCTAssertNil(model.selectedLayerID)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_04_losingTheWindowEndsADragWithoutAClick() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let card = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        preview.mouseDown(with: Self.mouse(.leftMouseDown, at: card, in: preview))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        preview.mouseUp(with: Self.mouse(.leftMouseUp, at: card, in: preview))
        XCTAssertNil(model.selectedLayerID)
        withExtendedLifetime(window) {}
    }

    // MARK: - C-PREV-05 to 09: scrolling, pinching, the camera and borders

    /// A scroll as a trackpad makes it: precise points, optionally with ⌘.
    @MainActor
    static func scroll(
        dx: Int32, dy: Int32, at point: NSPoint, command: Bool = false, in preview: PreviewView
    ) -> NSEvent {
        let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx,
            wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // Always set: an event made without a source carries the keys held at that moment, and a
        // ⌘ held then turns the scroll into a zoom (C-PREV-05) that moves nothing.
        event.flags = command ? .maskCommand : []
        let window = preview.window!
        event.location = window.convertPoint(toScreen: preview.convert(point, to: nil))
        // CGEvent locations are from the top left of the main screen.
        if let screen = NSScreen.screens.first {
            event.location.y = screen.frame.height - event.location.y
        }
        return NSEvent(cgEvent: event)!
    }

    @MainActor
    func test_C_PREV_05_zoomingKeepsTheLayerUnderThePointer() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let card = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        // The scroll's own handler: where a synthesized scroll event lands depends on the
        // window's place on a screen, and this window is never shown.
        preview.scroll(dx: 0, dy: 40, command: true, at: card)
        XCTAssertGreaterThan(model.camera.zoom, 1)
        let after = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        XCTAssertEqual(after.x, card.x, accuracy: 0.5)
        XCTAssertEqual(after.y, card.y, accuracy: 0.5)

        preview.magnify(by: -0.5, at: card)
        let pinched = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        XCTAssertEqual(pinched.x, card.x, accuracy: 0.5)
        XCTAssertEqual(pinched.y, card.y, accuracy: 0.5)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_06_nothingMovesOnceDisconnected() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        model.connectionLost()
        Self.drag(from: NSPoint(x: 100, y: 100), to: NSPoint(x: 150, y: 100), in: preview)
        preview.scrollWheel(
            with: Self.scroll(dx: 10, dy: 10, at: NSPoint(x: 50, y: 50), in: preview))
        preview.magnify(by: 1, at: NSPoint(x: 50, y: 50))
        XCTAssertEqual(model.camera, .flat)
        withExtendedLifetime(window) {}
    }

    // MARK: - Found in review

    @MainActor
    func test_C_PREV_03_theHoverFollowsThePointerDuringADrag() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let card = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        preview.mouseMoved(with: Self.mouse(.mouseMoved, at: card, in: preview))
        XCTAssertEqual(model.hoveredLayerID, 4)
        // In 2D a drag pans: the card moves with the pointer and stays under it.
        Self.drag(from: card, to: NSPoint(x: card.x + 120, y: card.y - 150), in: preview)
        XCTAssertEqual(model.hoveredLayerID, 4)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_WIN_03_aClickUnderWayWhenTheConnectionGoesSelectsNothing() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let card = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        preview.mouseDown(with: Self.mouse(.leftMouseDown, at: card, in: preview))
        model.connectionLost()
        preview.mouseUp(with: Self.mouse(.leftMouseUp, at: card, in: preview))
        XCTAssertNil(model.selectedLayerID)
        withExtendedLifetime(window) {}
    }

    // MARK: - The band under the toolbar (C-WIN-06)

    /// The preview filling a window whose content runs up under its title bar, as the
    /// inspector's does, with a point in that band.
    @MainActor
    private func previewUnderTitleBar(
        _ model: InspectionStore
    ) throws -> (PreviewView, NSWindow, band: NSPoint) {
        let controller = PreviewViewController(store: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 900),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 480, height: 900))
        window.layoutIfNeeded()
        try Wait.running { await controller.texturesSettled() }
        let preview = try XCTUnwrap(controller.preview)
        let bandHeight = preview.bounds.height - window.contentLayoutRect.height
        XCTAssertGreaterThan(bandHeight, 10)
        let y = preview.isFlipped ? bandHeight / 2 : preview.bounds.height - bandHeight / 2
        return (preview, window, NSPoint(x: preview.bounds.midX, y: y))
    }

    @MainActor
    func test_C_PREV_04_draggingUnderTheToolbarLeavesTheCamera() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        let (preview, window, band) = try previewUnderTitleBar(model)
        let camera = model.camera
        // The window moves under the pointer while it drags: the points jump about.
        Self.drag(from: band, to: NSPoint(x: band.x + 60, y: band.y), in: preview)
        Self.drag(from: band, to: NSPoint(x: band.x - 40, y: band.y), in: preview)
        XCTAssertEqual(model.camera, camera)
        XCTAssertNil(model.selectedLayerID)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_03_theBandUnderTheToolbarIsNotPointedAt() throws {
        let model = try model()
        let (preview, window, band) = try previewUnderTitleBar(model)
        // Panned down until a layer is under the band.
        preview.scroll(dx: 0, dy: -600, command: false, at: band)
        Self.settle()
        let under = preview.drawList.layer(at: ScenePoint(
            x: band.x, y: preview.isFlipped ? band.y : preview.bounds.height - band.y))
        XCTAssertNotNil(under)
        // Just below the band the same layer is pointed at.
        let below = NSPoint(x: band.x, y: band.y + (preview.isFlipped ? 40 : -40))
        preview.mouseMoved(with: Self.mouse(.mouseMoved, at: below, in: preview))
        XCTAssertEqual(model.hoveredLayerID, under)
        preview.mouseMoved(with: Self.mouse(.mouseMoved, at: band, in: preview))
        XCTAssertNil(model.hoveredLayerID)
        Self.click(at: band, in: preview)
        XCTAssertNil(model.selectedLayerID)
        XCTAssertNil(Self.contextMenu(at: band, in: preview))
        withExtendedLifetime(window) {}
    }

    // MARK: - Resizing and dragging

    @MainActor
    func test_C_PREV_03_resizingForgetsWhereThePointerWas() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        let card = try XCTUnwrap(preview.viewPoint(ofCenterOf: 4))
        preview.mouseMoved(with: Self.mouse(.mouseMoved, at: card, in: preview))
        XCTAssertEqual(model.hoveredLayerID, 4)
        preview.setFrameSize(NSSize(width: 300, height: 500))
        XCTAssertNil(model.hoveredLayerID, "what is under the old point is not under the pointer")
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_04_aDragGoesOnWhenANewHierarchyArrives() throws {
        let model = try model()
        model.setPreviewMode(.threeD)
        let (_, preview, window) = try previewInWindow(model)
        let start = NSPoint(x: 120, y: 300)
        func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
            Self.mouse(type, at: NSPoint(x: start.x + x, y: start.y), in: preview)
        }
        preview.mouseDown(with: event(.leftMouseDown, 0))
        preview.mouseDragged(with: event(.leftMouseDragged, 20))
        model.apply(try Fixtures.hierarchy())  // a new tree, half way through the drag
        preview.mouseDragged(with: event(.leftMouseDragged, 40))
        preview.mouseUp(with: event(.leftMouseUp, 40))
        XCTAssertEqual(
            model.camera.yaw, Camera.standard3D.rotated(byDragOf: 40, 0).yaw, accuracy: 1e-9)
        XCTAssertNil(model.selectedLayerID, "a drag selects nothing")
        withExtendedLifetime(window) {}
    }
}
