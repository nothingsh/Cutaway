import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The two windows: the launcher lists the apps, choosing one opens its inspector window, and
/// closing that brings the launcher back (C-WIN-01); the inspector's panes are in place before
/// it is shown (C-WIN-02); a lost app leaves its window with a notice (C-WIN-03).
final class WindowCoordinatorTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")

    private static let simulator = AppLocation.simulator(port: 48160)
    private static let second = AppLocation.simulator(port: 48161)

    private func session() -> Session {
        Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
    }

    /// A started coordinator over a model that lists Demo and Other. Its windows are closed
    /// when the test ends.
    @MainActor
    private func started() -> (WindowCoordinator, AppListStore) {
        let model = AppListStore()
        var other = Self.demo
        other.name = "Other"
        model.apply(.found(Self.simulator, Self.demo, session()))
        model.apply(.found(Self.second, other, session()))
        let coordinator = WindowCoordinator(store: model, discoversDevices: false)
        coordinator.start()
        addTeardownBlock { @MainActor in
            coordinator.inspector?.close()
            coordinator.launcher.close()
        }
        return (coordinator, model)
    }

    /// Chooses the app at `index` in the launcher, as a click on its row does.
    @MainActor
    private func choose(_ index: Int, in coordinator: WindowCoordinator) throws {
        let list = coordinator.launcher.listController
        list.choose(row: try XCTUnwrap(list.tableRow(ofApp: index)))
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

    // MARK: - C-WIN-01

    @MainActor
    func test_C_WIN_01_choosingAnotherAppReplacesTheWindow() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let first = try XCTUnwrap(coordinator.inspector)
        let firstWindow = try XCTUnwrap(first.window)

        coordinator.showAppList(nil)
        try choose(1, in: coordinator)

        XCTAssertEqual(model.inspectedApp, Self.second)
        let second = try XCTUnwrap(coordinator.inspector)
        XCTAssertFalse(second === first)
        XCTAssertEqual(second.window?.title, "Other")
        XCTAssertFalse(firstWindow.isVisible, "the first window is still open")
        let open = NSApplication.shared.windows.filter {
            $0.isVisible && $0.windowController is InspectorWindowController
        }
        XCTAssertEqual(open.count, 1)
    }

    @MainActor
    func test_C_WIN_01_choosingTheInspectedAppOnlyBringsItsWindowForward() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        XCTAssertEqual(inspection.loadState, .loaded)

        coordinator.showAppList(nil)
        try choose(0, in: coordinator)

        XCTAssertTrue(coordinator.inspector === inspector)
        XCTAssertTrue(try XCTUnwrap(inspector.window).isVisible)
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)
        // Not entered again: entering asks for the layers anew and starts by loading.
        XCTAssertEqual(inspection.loadState, .loaded)
    }

    // MARK: - C-WIN-02

    @MainActor
    func test_C_WIN_02_thePanesHaveTheirWidthsBeforeTheWindowIsShown() throws {
        let model = InspectionStore(session: session())
        let inspector = InspectorWindowController(
            location: Self.simulator, entry: nil, store: model)
        let window = try XCTUnwrap(inspector.window)
        XCTAssertFalse(window.isVisible)
        let panes = inspector.splitController.splitView.arrangedSubviews
        XCTAssertEqual(panes.count, 3)

        func widths() -> [CGFloat] { panes.map(\.frame.width) }
        let first = widths()
        XCTAssertEqual(first[0], InspectorSplitViewController.sidebarWidth)
        XCTAssertEqual(first[2], InspectorSplitViewController.inspectorWidth)
        XCTAssertLessThanOrEqual(
            first.reduce(0, +), window.contentView?.bounds.width ?? 0)
        XCTAssertEqual(
            panes[2].frame.maxX, window.contentView?.bounds.width ?? 0, accuracy: 0.5)
        // Already within the screen: showing it does not shrink it, and the panes with it.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            XCTAssertLessThanOrEqual(window.frame.width, visible.width)
            XCTAssertLessThanOrEqual(window.frame.height, visible.height)
        }

        // Laid out again, and shown: nothing moves.
        window.layoutIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(widths(), first)
        inspector.showWindow(nil)
        window.layoutIfNeeded()
        XCTAssertEqual(widths(), first)
        model.apply(try Fixtures.hierarchy())
        window.layoutIfNeeded()
        XCTAssertEqual(widths(), first)
        inspector.close()
    }

    @MainActor
    func test_C_WIN_02_aWindowLargerThanTheScreenIsMadeToFitIt() {
        // A 1024 by 768 display, under the menu bar and above the Dock.
        let visible = NSRect(x: 0, y: 63, width: 1024, height: 674)
        let minimum = NSSize(width: 820, height: 460)
        let fitted = InspectorWindowController.frame(
            NSRect(x: 0, y: 0, width: 1200, height: 760), fitting: visible, minimum: minimum)
        XCTAssertEqual(fitted.size, NSSize(width: 1024, height: 674))

        let small = NSRect(x: 10, y: 20, width: 900, height: 600)
        XCTAssertEqual(
            InspectorWindowController.frame(small, fitting: visible, minimum: minimum), small)

        // Never below the smallest window, which has room for every pane.
        let tiny = NSRect(x: 0, y: 0, width: 800, height: 400)
        XCTAssertEqual(
            InspectorWindowController.frame(
                NSRect(x: 0, y: 0, width: 1200, height: 760), fitting: tiny, minimum: minimum)
                .size,
            minimum)
    }

    // MARK: - C-WIN-03

    @MainActor
    func test_C_WIN_03_aLostAppLeavesItsWindowWithANotice() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let split = inspector.splitController
        try XCTUnwrap(model.inspection(at: Self.simulator)).apply(try Fixtures.hierarchy())
        let container = split.containerController.view
        let panel = try XCTUnwrap(AppListViewTests.descendant(
            of: container, identifier: PreviewPaneViewController.disconnectedIdentifier))
        XCTAssertFalse(isShown(panel))

        model.apply(.lost(Self.simulator))

        XCTAssertNil(model.inspectedApp)
        XCTAssertTrue(coordinator.inspector === inspector, "the window was replaced")
        XCTAssertTrue(inspector.isDisconnected)
        XCTAssertTrue(try XCTUnwrap(inspector.window).isVisible)
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)
        XCTAssertTrue(isShown(panel))
        // What it last showed stays, faded, and takes no clicks on layers.
        XCTAssertEqual(split.hierarchyController.outlineView.numberOfRows, 7)
        XCTAssertFalse(split.hierarchyController.outlineView.isEnabled)
        XCTAssertLessThan(split.hierarchyController.view.alphaValue, 1)
        let shield = try XCTUnwrap(AppListViewTests.descendant(
            of: container, identifier: PreviewPaneViewController.shieldIdentifier))
        XCTAssertTrue(isShown(shield))
        inspector.window?.layoutIfNeeded()
        // `hitTest` takes a point in the coordinates of the view's superview.
        let middle = container.convert(
            NSPoint(x: container.bounds.midX, y: container.bounds.midY), to: container.superview)
        XCTAssertTrue(container.hitTest(middle) === shield)

        // The button closes the window and brings back the launcher.
        let button = try XCTUnwrap(AppListViewTests.descendant(
            of: panel, identifier: PreviewPaneViewController.showAppsIdentifier) as? NSButton)
        button.performClick(nil)
        XCTAssertNil(coordinator.inspector)
        XCTAssertFalse(try XCTUnwrap(inspector.window).isVisible)
        XCTAssertTrue(try XCTUnwrap(coordinator.launcher.window).isVisible)
    }

    @MainActor
    func test_C_WIN_03_anAppThatTurnsIncompatibleLeavesItsWindowToo() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)

        model.apply(.incompatible(
            Self.simulator, Self.demo, local: Version(major: 0, minor: 1),
            remote: Version(major: 1, minor: 0)))

        XCTAssertTrue(coordinator.inspector === inspector)
        XCTAssertTrue(inspector.isDisconnected)
        XCTAssertEqual(inspector.modeControl?.isEnabled, false)

        // Closing it brings back the launcher; nothing is left inspected.
        inspector.window?.performClose(nil)
        XCTAssertNil(coordinator.inspector)
        XCTAssertNil(model.inspectedApp)
        XCTAssertTrue(try XCTUnwrap(coordinator.launcher.window).isVisible)
    }

    @MainActor
    func test_C_WIN_03_choosingAnAppAfterALostOneOpensANewWindow() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let lost = try XCTUnwrap(coordinator.inspector)
        model.apply(.lost(Self.simulator))

        coordinator.showAppList(nil)
        // Demo is gone; Other is now the first app.
        try choose(0, in: coordinator)

        XCTAssertEqual(model.inspectedApp, Self.second)
        XCTAssertFalse(coordinator.inspector === lost)
        XCTAssertFalse(try XCTUnwrap(lost.window).isVisible)
        XCTAssertEqual(coordinator.inspector?.isDisconnected, false)
    }

    // MARK: - C-HIER-04 to 06: the list's commands

    @MainActor
    func test_C_HIER_05_theMenusCommandsReachTheWindowNotTheList() throws {
        // A view controller in the responder chain that answers one of these selectors would
        // take the command, and AppKit would enable the item without asking the window.
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        try XCTUnwrap(model.inspection(at: Self.simulator)).apply(try Fixtures.hierarchy())
        let selectors = [
            #selector(InspectorWindowController.findLayer(_:)),
            #selector(InspectorWindowController.focusOnSelectedLayer(_:)),
            #selector(InspectorWindowController.showAllLayers(_:)),
            #selector(InspectorWindowController.expandAllLayers(_:)),
            #selector(InspectorWindowController.collapseAllLayers(_:)),
            #selector(InspectorWindowController.refresh(_:)),
            #selector(InspectorWindowController.refreshSelectedSubtree(_:)),
        ]
        let outline = inspector.splitController.hierarchyController.outlineView
        var responder: NSResponder? = outline
        while let current = responder, !(current is NSWindow) {
            for selector in selectors {
                XCTAssertFalse(current.responds(to: selector), "\(current) answers \(selector)")
            }
            responder = current.nextResponder
        }
    }

    // MARK: - C-ATTR-08: undo

    @MainActor
    func test_C_ATTR_08_theEditMenuUndoesTheInspectorsAttributeChanges() throws {
        let (coordinator, model) = started()
        let edit = try XCTUnwrap(
            coordinator.makeMainMenu().items.first { $0.submenu?.title == "Edit" }?.submenu)
        let undo = try XCTUnwrap(edit.items.first { $0.title == "Undo" })
        let redo = try XCTUnwrap(edit.items.first { $0.title == "Redo" })
        XCTAssertEqual(undo.action, Selector(("undo:")))
        XCTAssertEqual(undo.keyEquivalent, "z")
        XCTAssertEqual(undo.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(redo.action, Selector(("redo:")))
        XCTAssertEqual(redo.keyEquivalent, "z")
        XCTAssertEqual(redo.keyEquivalentModifierMask, [.command, .shift])

        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        let window = try XCTUnwrap(inspector.window)
        let attributes = inspection.attributes.undoManager
        // Nothing can be changed yet: these sessions never told their version.
        XCTAssertFalse(window.undoManager === attributes, "no undo while nothing can be changed")
        XCTAssertEqual(window.undoManager?.canUndo, false)
        inspection.attributes.setEditingSupported(true)
        XCTAssertTrue(window.undoManager === attributes)
        inspection.attributes.appStateDidChange(.background)
        XCTAssertFalse(window.undoManager === attributes, "the app is not active")
        inspection.attributes.appStateDidChange(.active)
        inspector.store.connectionLost()
        XCTAssertFalse(window.undoManager === attributes, "the connection is gone")
    }

    // MARK: - C-DET-07: refreshing a subtree

    @MainActor
    func test_C_DET_07_theViewMenuRefreshesTheSelectedSubtree() throws {
        let (coordinator, model) = started()
        let items = coordinator.makeMainMenu().items.flatMap { MainMenuTests.allItems($0.submenu ?? NSMenu()) }
        let item = try XCTUnwrap(items.first { $0.title == "Refresh Selected Subtree" })
        XCTAssertEqual(
            item.action, #selector(InspectorWindowController.refreshSelectedSubtree(_:)))

        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        let validation = NSMenuItem(title: "", action: item.action, keyEquivalent: "")
        inspection.select(4)
        XCTAssertFalse(inspector.validateMenuItem(validation), "a source that sends no subtrees")
        inspection.canRefreshSubtrees = true
        XCTAssertTrue(inspector.validateMenuItem(validation))
        inspection.select(nil)
        XCTAssertFalse(inspector.validateMenuItem(validation), "nothing selected")

        inspection.select(4)
        inspector.refreshSelectedSubtree(nil)
        XCTAssertTrue(inspection.loadingSubtree == 4 || inspection.queuedSubtrees == [4])

        inspector.store.connectionLost()
        XCTAssertFalse(inspector.validateMenuItem(validation), "disconnected")
    }

    // MARK: - C-PREV-07 to 09: the preview's commands

    @MainActor
    func test_C_PREV_07_thePreviewsCommandsReachTheWindow() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        try XCTUnwrap(model.inspection(at: Self.simulator)).apply(try Fixtures.hierarchy())
        let selectors = [
            #selector(InspectorWindowController.toggleHiddenLayers(_:)),
            #selector(InspectorWindowController.toggleBorders(_:)),
            #selector(InspectorWindowController.resetView(_:)),
        ]
        let starts: [NSResponder] = [
            try XCTUnwrap(inspector.splitController.previewController.preview),
            inspector.splitController.hierarchyController.outlineView,
        ]
        for start in starts {
            var responder: NSResponder? = start
            while let current = responder, !(current is NSWindow) {
                for selector in selectors {
                    XCTAssertFalse(
                        current.responds(to: selector), "\(current) answers \(selector)")
                }
                responder = current.nextResponder
            }
        }
    }

    // MARK: - C-DET-05: refreshing

    @MainActor
    func test_C_DET_05_theToolbarAndTheMenuRefresh() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        let refreshButton = try XCTUnwrap(inspector.appCapsule).refreshButton
        XCTAssertEqual(refreshButton.toolTip, "Refresh")
        XCTAssertTrue(refreshButton.isEnabled)

        let items = coordinator.makeMainMenu().items.flatMap { MainMenuTests.allItems($0.submenu ?? NSMenu()) }
        let refresh = try XCTUnwrap(items.first { $0.title == "Refresh" })
        XCTAssertEqual(refresh.keyEquivalent, "r")
        XCTAssertEqual(refresh.action, #selector(InspectorWindowController.refresh(_:)))
        XCTAssertTrue(inspector.validateMenuItem(refresh))

        // The first load is still under way over the silent connection: the refresh is
        // queued behind it.
        XCTAssertTrue(inspection.isLoading)
        XCTAssertFalse(inspection.reloadAgain)
        // The button's action, without the run loop a click turns while the button is down:
        // in it the connection, which ends at once, ends the first load.
        let action = try XCTUnwrap(refreshButton.action)
        XCTAssertTrue(NSApp.sendAction(action, to: refreshButton.target, from: refreshButton))
        XCTAssertTrue(inspection.reloadAgain)
    }

    @MainActor
    func test_C_DET_05_refreshIsUnavailableOnceDisconnected() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        model.apply(.lost(Self.simulator))
        XCTAssertTrue(inspector.isDisconnected)
        let capsule = try XCTUnwrap(inspector.appCapsule)
        XCTAssertFalse(capsule.refreshButton.isEnabled, "greyed out now, not at the next event")
        XCTAssertFalse(capsule.saveButton.isEnabled)
        XCTAssertTrue(capsule.nameButton.isEnabled, "the app list is still there")
        let menuItem = NSMenuItem(
            title: "", action: #selector(InspectorWindowController.refresh(_:)), keyEquivalent: "")
        XCTAssertFalse(inspector.validateMenuItem(menuItem))
    }

    // MARK: - C-WIN-04: coming back

    private static let later = AppLocation.simulator(port: 48163)

    @MainActor
    func test_C_WIN_04_theWindowComesBackWhereItWas() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let old = try XCTUnwrap(coordinator.inspector)
        // Within a 1024 by 768 display, which would move a window that is not.
        let frame = NSRect(x: 81, y: 92, width: 900, height: 560)
        old.window?.setFrame(frame, display: false)

        model.apply(.lost(Self.simulator))
        XCTAssertTrue(old.isDisconnected)
        model.apply(.found(Self.later, Self.demo, session()))

        let new = try XCTUnwrap(coordinator.inspector)
        XCTAssertFalse(new === old, "a window for the new connection")
        XCTAssertEqual(new.location, Self.later)
        XCTAssertFalse(new.isDisconnected)
        XCTAssertEqual(new.window?.frame, frame)
        XCTAssertTrue(try XCTUnwrap(new.window).isVisible)
        XCTAssertFalse(try XCTUnwrap(old.window).isVisible)
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)
    }

    @MainActor
    func test_C_WIN_04_aClosedWindowDoesNotComeBack() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        model.apply(.lost(Self.simulator))
        coordinator.inspector?.close()
        XCTAssertNil(coordinator.inspector)
        model.apply(.found(Self.later, Self.demo, session()))
        XCTAssertNil(coordinator.inspector)
        XCTAssertNil(model.inspectedApp)
    }

    @MainActor
    func test_C_WIN_04_anotherAppComingBackLeavesTheWindowWaiting() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let old = try XCTUnwrap(coordinator.inspector)
        model.apply(.lost(Self.simulator))
        var stranger = Self.demo
        stranger.bundleID = "dev.cutaway.stranger"
        model.apply(.found(Self.later, stranger, session()))
        XCTAssertTrue(coordinator.inspector === old)
        XCTAssertTrue(old.isDisconnected)
    }

    @MainActor
    func test_C_WIN_01_choosingTheWaitedForAppByHandPutsTheLauncherAway() throws {
        let (coordinator, model) = started()
        let twin = AppLocation.simulator(port: 48162)
        model.apply(.found(twin, Self.demo, session()))
        try choose(0, in: coordinator)
        model.apply(.lost(Self.simulator))
        coordinator.showAppList(nil)
        let index = try XCTUnwrap(model.entries.firstIndex { $0.id == twin })
        try choose(index, in: coordinator)
        XCTAssertEqual(coordinator.inspector?.location, twin)
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)
    }

    // MARK: - Keyboard focus and minimized windows

    @MainActor
    func test_C_WIN_04_aMinimizedWindowComesBackMinimized() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let old = try XCTUnwrap(coordinator.inspector)
        old.window?.miniaturize(nil)
        try XCTSkipUnless(old.window?.isMiniaturized == true, "no window server to minimize")
        let frame = try XCTUnwrap(old.window?.frame)
        model.apply(.lost(Self.simulator))
        model.apply(.found(AppLocation.simulator(port: 48163), Self.demo, session()))
        let new = try XCTUnwrap(coordinator.inspector)
        XCTAssertFalse(new === old)
        XCTAssertEqual(new.window?.isMiniaturized, true)
        XCTAssertNotEqual(
            new.window?.frame, frame, "a minimized window's frame is not where it was")
    }

    // MARK: - Pane widths are remembered

    /// A defaults suite of its own, removed when the test ends.
    private func defaults() throws -> UserDefaults {
        let name = "dev.cutaway.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    @MainActor
    private func inspector(remembering defaults: UserDefaults) throws -> InspectorWindowController {
        InspectorWindowController(
            location: Self.simulator, entry: nil, store: InspectionStore(session: session()),
            paneWidths: PaneWidths(key: "Inspector", defaults: defaults))
    }

    @MainActor
    func test_C_WIN_02_rememberedWidthsStayWithinTheirRanges() throws {
        let defaults = try defaults()
        PaneWidths(key: "Inspector", defaults: defaults).save(sidebar: 900, inspector: 10)
        let inspector = try inspector(remembering: defaults)
        let panes = inspector.splitController.splitView.arrangedSubviews
        XCTAssertEqual(panes[0].frame.width, InspectorSplitViewController.maximumSidebarWidth)
        XCTAssertEqual(panes[2].frame.width, InspectorSplitViewController.minimumInspectorWidth)
        inspector.close()
    }

    // MARK: - Lost apps, clicks, reconnections and widths

    @MainActor
    func test_C_WIN_03_nothingIsAskedForOnceTheAppIsLost() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        inspection.select(3)
        model.apply(.lost(Self.simulator))
        let batches = inspection.batchesStarted
        let attributes = inspection.attributes.requestsStarted

        // What a user can still do in the window: move the preview, expand, refresh.
        let preview = try XCTUnwrap(inspector.splitController.previewController.preview)
        preview.scroll(dx: 10, dy: 0, command: false, at: NSPoint(x: 20, y: 20))
        inspection.setExpanded(2, false)
        inspection.setExpanded(2, true)
        inspector.refresh(nil)
        inspection.setVisibleLayers([1, 2, 3])

        XCTAssertEqual(inspection.batchesStarted, batches)
        XCTAssertEqual(inspection.attributes.requestsStarted, attributes)
        XCTAssertFalse(inspection.reloadAgain, "the refresh queued no request for the layers")
    }

    @MainActor
    func test_C_WIN_02_aNarrowerWindowDoesNotChangeTheRememberedWidths() throws {
        let defaults = try defaults()
        let widths = PaneWidths(key: "Inspector", defaults: defaults)
        widths.save(sidebar: 330, inspector: 300)
        let inspector = try inspector(remembering: defaults)
        let window = try XCTUnwrap(inspector.window)
        // As narrow as the window goes: the side panes are squeezed, not moved by the user.
        window.setContentSize(InspectorWindowController.minimumSize)
        window.layoutIfNeeded()
        XCTAssertLessThan(
            inspector.splitController.splitView.arrangedSubviews[0].frame.width, 330)
        XCTAssertEqual(widths.load()?.sidebar, 330)
        XCTAssertEqual(widths.load()?.inspector, 300)
        inspector.close()
    }
}
