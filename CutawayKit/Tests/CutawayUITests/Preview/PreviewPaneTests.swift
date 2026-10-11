import AppKit
import CutawayModel
import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The panels over the preview: the notice (C-DET-04), the screenshots' progress (C-DET-02),
/// the loading panel, and the notice of a lost connection (C-WIN-03).
final class PreviewPaneTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func session(
        to server: MockServer, requestTimeout: Duration = .seconds(10)
    ) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, requestTimeout: requestTimeout)
        _ = try await session.handshake()
        return session
    }

    /// A preview container in a window that is never shown.
    @MainActor
    private func container(
        _ model: InspectionStore, appName: String = "Demo", width: CGFloat = 700
    ) -> (PreviewPaneViewController, NSWindow) {
        let controller = PreviewPaneViewController(store: model, appName: appName)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: width, height: 600))
        window.layoutIfNeeded()
        return (controller, window)
    }

    @MainActor
    private func view(
        _ identifier: String, in controller: PreviewPaneViewController
    ) throws -> NSView {
        try XCTUnwrap(
            AppListViewTests.descendant(of: controller.view, identifier: identifier), identifier)
    }

    @MainActor
    private func label(
        _ identifier: String, in controller: PreviewPaneViewController
    ) throws -> NSTextField {
        try XCTUnwrap(try view(identifier, in: controller) as? NSTextField)
    }

    @MainActor
    private func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    // MARK: - The text

    func test_C_DET_02_progressReadsCompletedOfTotal() {
        XCTAssertEqual(
            PreviewPaneText.progressText(DetailProgress(completed: 12, total: 40)),
            "12 / 40")
    }

    func test_C_DET_02_progressIsHiddenWhenThereIsNothingToLoad() {
        XCTAssertNil(PreviewPaneText.progressText(
            DetailProgress(completed: 0, total: 0)))
        XCTAssertNil(PreviewPaneText.progressText(
            DetailProgress(completed: 7, total: 7)))
    }

    func test_C_DET_04_theNoticesSayWhatHappened() {
        XCTAssertEqual(
            PreviewPaneText.noticeText(.appNotActive, appName: "Demo"),
            "Demo is not active. Loading continues when it comes to the foreground.")
        XCTAssertEqual(
            PreviewPaneText.noticeText(.screenshotsFailed, appName: "Demo"),
            "Some screenshots could not be loaded. Refresh to try again.")
        XCTAssertEqual(
            PreviewPaneText.noticeText(.layersFailed, appName: "Demo"),
            "The layers could not be loaded again. Refresh to try again.")
        XCTAssertNil(PreviewPaneText.noticeText(nil, appName: "Demo"))
    }

    func test_C_DET_07_theNoticeSaysTheLayerIsGone() {
        XCTAssertEqual(
            PreviewPaneText.noticeText(.layerGone, appName: "Demo"),
            "The layer is no longer in Demo. Refresh to load all layers again.")
    }

    // MARK: - The panels

    @MainActor
    func test_C_DET_02_theProgressPanelFollowsTheProgress() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        let progress = try label(PreviewPaneViewController.progressIdentifier, in: controller)
        let bar = try progressBar(controller)
        XCTAssertFalse(isShown(progress), "no tree, nothing to load")

        model.apply(try Fixtures.hierarchy())
        XCTAssertTrue(isShown(progress))
        XCTAssertEqual(progress.stringValue, "0 / 7")
        XCTAssertEqual(bar.fraction, 0)

        let details = try Fixtures.layerDetails(scenario: "layer-details")
        try Wait.running { await model.applyDetails(details) }
        XCTAssertEqual(progress.stringValue, "2 / 7")
        XCTAssertEqual(bar.fraction, 2.0 / 7.0, accuracy: 1e-9)
        withExtendedLifetime(window) {}
    }

    @MainActor
    private func progressBar(_ controller: PreviewPaneViewController) throws
        -> ProgressBarView
    {
        try XCTUnwrap(try view(
            PreviewPaneViewController.progressBarIdentifier, in: controller)
            as? ProgressBarView)
    }

    /// A new round starts the bar empty at once rather than running it back from full, which
    /// read as a countdown.
    @MainActor
    func test_C_DET_02_aNewRoundStartsTheBarEmpty() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        let bar = try progressBar(controller)
        model.apply(try Fixtures.hierarchy())
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        try Wait.running { await model.applyDetails(details) }
        XCTAssertGreaterThan(bar.fraction, 0)
        window.layoutIfNeeded()
        XCTAssertGreaterThan(bar.fillRect.width, 0)

        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(model.detailProgress, DetailProgress(completed: 0, total: 7))
        XCTAssertEqual(bar.fraction, 0)
        XCTAssertEqual(bar.fillRect.width, 0)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_DET_02_theBarFillsFromTheLeft() {
        let bar = ProgressBarView(frame: NSRect(x: 0, y: 0, width: 80, height: 4))
        XCTAssertEqual(bar.fillRect.width, 0)
        bar.fraction = 0.25
        XCTAssertEqual(bar.fillRect, NSRect(x: 0, y: 0, width: 20, height: 4))
        bar.fraction = 1
        XCTAssertEqual(bar.fillRect, bar.bounds)
        bar.fraction = 0
        XCTAssertEqual(bar.fillRect.width, 0)
        bar.fraction = 3
        XCTAssertEqual(bar.fraction, 1)
        bar.fraction = .nan
        XCTAssertEqual(bar.fraction, 0)
        XCTAssertEqual(bar.accessibilityRole(), .progressIndicator)
    }

    /// The progress sits at the top right, below the toolbar, leaving the bottom right to the
    /// controls.
    @MainActor
    func test_C_DET_02_theProgressIsAtTheTopRight() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let (controller, window) = container(model, width: 900)
        window.layoutIfNeeded()
        let progress = try panelFrame(
            PreviewPaneViewController.progressIdentifier, in: controller)
        let bounds = controller.view.bounds
        let safeTop = controller.view.safeAreaRect.maxY
        XCTAssertEqual(progress.maxX, bounds.maxX - PreviewPaneViewController.inset, accuracy: 0.5)
        XCTAssertEqual(progress.maxY, safeTop - PreviewPaneViewController.inset, accuracy: 0.5)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_DET_02_theProgressPanelGoesWhenEveryScreenshotIsSettled() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        let (controller, window) = container(model)
        let progress = try label(PreviewPaneViewController.progressIdentifier, in: controller)

        model.enter()
        let done = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(done)
        // It fades out, then goes.
        XCTAssertTrue(isShown(progress), "still fading")
        XCTAssertFalse(progress.stringValue.isEmpty, "the last count stays while it fades")
        let deadline = Date().addingTimeInterval(1)
        while isShown(progress), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(isShown(progress))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_04_theNoticeExplainsAnAppThatIsNotActive() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details-failed"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        let (controller, window) = container(model)
        let notice = try label(PreviewPaneViewController.noticeIdentifier, in: controller)
        let progress = try label(PreviewPaneViewController.progressIdentifier, in: controller)
        XCTAssertFalse(isShown(notice))

        model.enter()
        let paused = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(paused)
        XCTAssertTrue(isShown(notice))
        XCTAssertEqual(
            notice.stringValue,
            "Demo is not active. Loading continues when it comes to the foreground.")
        // The notice says why loading stopped; the progress does not repeat it.
        XCTAssertFalse(isShown(progress))
        // Nothing pops up.
        XCTAssertNil(window.attachedSheet)
        XCTAssertNil(NSApp.modalWindow)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    /// The panel is as wide as its text: a wrapping label gives way as easily as the stack
    /// holds its content, and the layout once squeezed the text to a few points, out of the
    /// panel's glass (2026-10-07, reported in use).
    @MainActor
    func test_C_DET_04_theNoticesPanelHoldsItsWholeText() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details-failed"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        let (controller, window) = container(model, appName: "Wikipedia")
        let notice = try label(PreviewPaneViewController.noticeIdentifier, in: controller)

        model.enter()
        let paused = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(paused)
        window.layoutIfNeeded()

        var current: NSView? = notice
        while let candidate = current, !(candidate is HUDView) { current = candidate.superview }
        let panel = try XCTUnwrap(current as? HUDView)
        XCTAssertFalse(panel.hasAmbiguousLayout)
        // One line at this width, all of it inside the panel.
        XCTAssertEqual(notice.frame.height, notice.intrinsicContentSize.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(notice.frame.width + 0.5, notice.intrinsicContentSize.width)
        XCTAssertTrue(panel.bounds.insetBy(dx: -0.5, dy: -0.5).contains(
            notice.convert(notice.bounds, to: panel)))

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_04_aLongNoticeWrapsInsteadOfBeingCut() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details-failed"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        let name = String(repeating: "A Very Long App Name ", count: 6)
        let (controller, window) = container(model, appName: name, width: 400)
        let notice = try label(PreviewPaneViewController.noticeIdentifier, in: controller)

        model.enter()
        let paused = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(paused)
        window.layoutIfNeeded()

        // The panel stays inside the preview, and every line of the text is there.
        var current: NSView? = notice
        while let candidate = current, !(candidate is HUDView) { current = candidate.superview }
        let panel = try XCTUnwrap(current as? HUDView)
        XCTAssertTrue(isShown(panel))
        XCTAssertGreaterThanOrEqual(panel.frame.minX, controller.view.bounds.minX)
        XCTAssertLessThanOrEqual(panel.frame.maxX, controller.view.bounds.maxX)
        XCTAssertTrue(notice.stringValue.hasPrefix(name))
        XCTAssertGreaterThan(notice.frame.height, 2 * (notice.font?.pointSize ?? 12))
        XCTAssertGreaterThanOrEqual(notice.frame.height + 0.5, notice.fittingSize.height)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_WIN_03_aLostConnectionStopsTheLoadingPanel() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        let loading = try view(PreviewPaneViewController.loadingIdentifier, in: controller)
        XCTAssertTrue(isShown(loading))

        model.connectionLost()
        XCTAssertFalse(isShown(loading))
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_HIER_01_theLoadingPanelShowsUntilTheFirstTree() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        let loading = try view(PreviewPaneViewController.loadingIdentifier, in: controller)
        XCTAssertTrue(isShown(loading))

        model.apply(try Fixtures.hierarchy())
        XCTAssertFalse(isShown(loading))
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_01_thePanelsLetThePointerThroughToThePreview() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        model.apply(try Fixtures.hierarchy())
        window.layoutIfNeeded()
        let progress = try label(PreviewPaneViewController.progressIdentifier, in: controller)
        XCTAssertTrue(isShown(progress))
        let preview = try XCTUnwrap(controller.previewController.preview)

        // `hitTest` takes a point in the coordinates of the view's superview.
        let root = try XCTUnwrap(controller.view.superview)
        let point = progress.convert(
            NSPoint(x: progress.bounds.midX, y: progress.bounds.midY), to: root)
        XCTAssertTrue(controller.view.hitTest(point) === preview)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_03_theReadoutNamesTheHoveredLayerOrElseTheSelectedOne() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        model.apply(try Fixtures.hierarchy())
        let readout = try view(PreviewPaneViewController.readoutIdentifier, in: controller)
        let title = try label(PreviewPaneViewController.readoutTitleIdentifier, in: controller)
        let size = try label(PreviewPaneViewController.readoutSizeIdentifier, in: controller)
        XCTAssertFalse(isShown(readout), "nothing hovered, nothing selected")

        model.select(3)
        XCTAssertTrue(isShown(readout))
        XCTAssertEqual(title.stringValue, "UILabel")
        XCTAssertEqual(size.stringValue, "200 × 24")

        model.hover(4)
        XCTAssertEqual(title.stringValue, "CardView")

        model.hover(nil)
        XCTAssertEqual(title.stringValue, "UILabel")
        model.select(nil)
        XCTAssertFalse(isShown(readout))
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_WIN_03_theLostConnectionReplacesTheOtherPanels() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        model.apply(try Fixtures.hierarchy())
        let progress = try label(PreviewPaneViewController.progressIdentifier, in: controller)
        let disconnected = try view(
            PreviewPaneViewController.disconnectedIdentifier, in: controller)
        XCTAssertTrue(isShown(progress))
        XCTAssertFalse(isShown(disconnected))
        var asked = 0
        controller.onShowApps = { asked += 1 }

        model.hover(4)
        model.connectionLost()

        XCTAssertNil(model.hoveredLayerID, "the hover is cut off")
        XCTAssertNil(controller.previewController.preview?.onHover)
        XCTAssertTrue(isShown(disconnected))
        XCTAssertFalse(isShown(progress))
        let texts = AppWindowsText.labels(in: disconnected)
        XCTAssertTrue(texts.contains("Lost the connection to Demo."), "\(texts)")
        let button = try XCTUnwrap(AppListViewTests.descendant(
            of: disconnected, identifier: PreviewPaneViewController.showAppsIdentifier)
            as? NSButton)
        // The button takes the pointer, unlike the other panels.
        window.layoutIfNeeded()
        let root = try XCTUnwrap(controller.view.superview)
        let point = button.convert(
            NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: root)
        XCTAssertTrue(controller.view.hitTest(point)?.isDescendant(of: button) ?? false)
        button.performClick(nil)
        XCTAssertEqual(asked, 1)
        withExtendedLifetime(window) {}
    }

    // MARK: - C-PREV-07 to 09: the controls

    @MainActor
    private func button(
        _ identifier: String, in controller: PreviewPaneViewController
    ) throws -> NSButton {
        try XCTUnwrap(try view(identifier, in: controller) as? NSButton)
    }

    @MainActor
    private func spacingSlider(_ controller: PreviewPaneViewController) throws -> NSSlider {
        try XCTUnwrap(
            try view(PreviewPaneViewController.spacingIdentifier, in: controller) as? NSSlider)
    }

    /// The floating panel a view is in, in its container's coordinates.
    @MainActor
    private func panelFrame(
        _ identifier: String, in controller: PreviewPaneViewController
    ) throws -> NSRect {
        var current: NSView? = try view(identifier, in: controller)
        while let candidate = current, !(candidate is HUDView) { current = candidate.superview }
        let panel = try XCTUnwrap(current, "\(identifier) is in no panel")
        return panel.convert(panel.bounds, to: controller.view)
    }

    @MainActor
    func test_C_PREV_08_theHiddenLayersButtonFollowsAndSetsTheModel() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let (controller, window) = container(model)
        let button = try button(PreviewPaneViewController.showHiddenIdentifier, in: controller)
        XCTAssertTrue(isShown(button))
        XCTAssertEqual(button.state, .off)
        button.performClick(nil)
        XCTAssertTrue(model.showsHiddenLayers)
        model.setShowsHiddenLayers(false)
        XCTAssertEqual(button.state, .off)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_09_theBordersButtonFollowsAndSetsTheModel() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        let button = try button(
            PreviewPaneViewController.showBordersIdentifier, in: controller)
        XCTAssertEqual(button.state, .on)
        button.performClick(nil)
        XCTAssertFalse(model.showsBorders)
        model.setShowsBorders(true)
        XCTAssertEqual(button.state, .on)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_07_theSpacingSliderWorksOnlyIn3D() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        let slider = try spacingSlider(controller)
        XCTAssertFalse(slider.isEnabled, "2D has no spacing")
        model.setPreviewMode(.threeD)
        XCTAssertTrue(slider.isEnabled)
        XCTAssertEqual(slider.doubleValue, 50)
        slider.doubleValue = 120
        XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
        XCTAssertEqual(model.camera.layerSpacing, 120)
        model.resetCamera()
        XCTAssertEqual(slider.doubleValue, 50)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_07_theResetButtonResetsTheModesCamera() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        model.pan(by: 30, 0)
        try button(PreviewPaneViewController.resetIdentifier, in: controller).performClick(nil)
        XCTAssertEqual(model.camera, .flat)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_07_theControlsAreUnavailableOnceDisconnected() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        model.setPreviewMode(.threeD)
        let (controller, window) = container(model)
        model.connectionLost()
        for identifier in [
            PreviewPaneViewController.showHiddenIdentifier,
            PreviewPaneViewController.showBordersIdentifier,
            PreviewPaneViewController.resetIdentifier,
        ] {
            XCTAssertFalse(try button(identifier, in: controller).isEnabled, identifier)
        }
        XCTAssertFalse(try spacingSlider(controller).isEnabled)
        let preview = try XCTUnwrap(controller.previewController.preview)
        preview.scroll(dx: 10, dy: 10, command: false, at: NSPoint(x: 50, y: 50))
        XCTAssertEqual(model.camera, .standard3D, "the camera no longer moves")
        withExtendedLifetime(window) {}
    }

    /// The controls sit at the bottom right; the readout at the bottom left beside them when
    /// there is room, on a row above them otherwise.
    @MainActor
    func test_C_PREV_07_theControlsAreAtTheBottomRight() throws {
        for (width, beside) in [(900.0, true), (400.0, false)] {
            let model = InspectionStore(
                session: Session(channel: InertChannel(), client: Self.client),
                newLayers: .expanded)
            model.apply(try Fixtures.hierarchy())  // progress 0 / 7
            model.select(3)  // a readout
            let (controller, window) = container(model, width: width)
            window.layoutIfNeeded()
            let bounds = controller.view.bounds
            let inset = PreviewPaneViewController.inset
            let controls = try panelFrame(
                PreviewPaneViewController.controlsIdentifier, in: controller)
            let readout = try panelFrame(
                PreviewPaneViewController.readoutIdentifier, in: controller)
            XCTAssertEqual(controls.maxX, bounds.maxX - inset, accuracy: 0.5, "\(width)")
            XCTAssertEqual(controls.minY, bounds.minY + inset, accuracy: 0.5, "\(width)")
            XCTAssertEqual(readout.minX, bounds.minX + inset, accuracy: 0.5, "\(width)")
            if beside {
                XCTAssertEqual(readout.minY, controls.minY, accuracy: 0.5, "\(width)")
                XCTAssertLessThanOrEqual(readout.maxX, controls.minX)
            } else {
                XCTAssertGreaterThanOrEqual(readout.minY, controls.maxY, "\(width)")
                XCTAssertLessThanOrEqual(readout.maxX, bounds.maxX - inset)
            }
            withExtendedLifetime(window) {}
        }
    }

    @MainActor
    func test_C_PREV_07_aLongTitleIsCutShortRatherThanSlidUnderTheControls() throws {
        var hierarchy = try Fixtures.hierarchy()
        let three = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 3 })
        hierarchy.nodes[three].viewDisplayClassName = String(repeating: "VeryLongLabel", count: 6)
        for width in [680.0, 1000.0, 400.0] {
            let model = InspectionStore(
                session: Session(channel: InertChannel(), client: Self.client),
                newLayers: .expanded)
            model.apply(hierarchy)
            model.select(3)
            let (controller, window) = container(model, width: width)
            window.layoutIfNeeded()
            let controls = try panelFrame(
                PreviewPaneViewController.controlsIdentifier, in: controller)
            let readout = try panelFrame(
                PreviewPaneViewController.readoutIdentifier, in: controller)
            XCTAssertLessThanOrEqual(
                readout.maxX, controller.view.bounds.maxX - PreviewPaneViewController.inset,
                "\(width)")
            if abs(readout.minY - controls.minY) < 0.5 {
                XCTAssertLessThanOrEqual(readout.maxX, controls.minX, "\(width)")
            } else {
                XCTAssertGreaterThanOrEqual(readout.minY, controls.maxY, "\(width)")
            }
            withExtendedLifetime(window) {}
        }
    }

    /// Reset is a word, not an arrow that reads like the toolbar's refresh.
    @MainActor
    func test_C_PREV_07_theResetButtonSaysReset() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        let reset = try button(PreviewPaneViewController.resetIdentifier, in: controller)
        XCTAssertEqual(reset.title, "Reset")
        XCTAssertNil(reset.image)
        XCTAssertEqual(reset.toolTip, "Reset View (\u{2318}0)")
        withExtendedLifetime(window) {}
    }

    /// The floating panels follow the window's appearance instead of always being dark.
    @MainActor
    func test_C_PREV_03_thePanelsFollowTheAppearance() {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let (controller, window) = container(model)
        var panels: [HUDView] = []
        func collect(_ view: NSView) {
            if let panel = view as? HUDView { panels.append(panel) }
            view.subviews.forEach(collect)
        }
        collect(controller.view)
        // Six, saving an archive's progress, "Saved" and "not saved" (C-ARCH-02), and
        // "not exported" (C-ARCH-06).
        XCTAssertEqual(panels.count, 10)
        for panel in panels {
            XCTAssertNil(panel.appearance)
        }
        withExtendedLifetime(window) {}
    }

    /// The canvas runs up under the toolbar, in the preview's colour, so that the preview and
    /// the strip under the toolbar are one surface.
    @MainActor
    func test_C_PREV_01_theCanvasRunsUnderTheToolbar() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let inspector = InspectorWindowController(
            location: .simulator(port: 48160), entry: nil, store: model)
        let window = try XCTUnwrap(inspector.window)
        window.layoutIfNeeded()
        let controller = inspector.splitController.containerController
        let canvas = try view(PreviewPaneViewController.canvasIdentifier, in: controller)
        XCTAssertEqual(canvas.frame, controller.view.bounds)
        let preview = try XCTUnwrap(controller.previewController.preview)
        let visibleTop = window.contentLayoutRect.maxY
        XCTAssertGreaterThan(canvas.convert(canvas.bounds, to: nil).maxY, visibleTop)
        XCTAssertLessThanOrEqual(preview.convert(preview.bounds, to: nil).maxY, visibleTop)

        for (name, dark) in [(NSAppearance.Name.darkAqua, true), (.aqua, false)] {
            window.appearance = NSAppearance(named: name)
            canvas.layoutSubtreeIfNeeded()
            canvas.displayIfNeeded()
            let color = try XCTUnwrap(canvas.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
                .usingColorSpace(.sRGB)
            let expected = RenderStyle.preview(dark: dark).background
            XCTAssertEqual(Float(color?.redComponent ?? -1), expected.x, accuracy: 0.002, "\(name)")
            XCTAssertEqual(Float(color?.blueComponent ?? -1), expected.z, accuracy: 0.002, "\(name)")
            XCTAssertEqual(preview.style.background, expected, "\(name)")
        }
        inspector.close()
    }

    @MainActor
    func test_C_WIN_04_theDisconnectedNoticeSaysWhetherTheWindowWaits() {
        XCTAssertEqual(
            PreviewPaneText.disconnectedText(appName: "Demo", waiting: true),
            "Lost the connection to Demo. Waiting for it to come back\u{2026}")
        XCTAssertEqual(
            PreviewPaneText.disconnectedText(appName: "Demo", waiting: false),
            "Lost the connection to Demo.")
    }
}

/// The text of every label in a view and below it.
@MainActor
enum AppWindowsText {
    static func labels(in view: NSView) -> [String] {
        var texts = (view as? NSTextField).map { [$0.stringValue] } ?? []
        for subview in view.subviews { texts += labels(in: subview) }
        return texts
    }
}
