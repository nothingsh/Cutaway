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
    func test_C_WIN_01_theAppStartsWithTheLauncherAlone() throws {
        let model = AppListStore()
        let coordinator = WindowCoordinator(store: model, discoversDevices: false)
        coordinator.start()
        addTeardownBlock { @MainActor in coordinator.launcher.close() }

        let launcher = try XCTUnwrap(coordinator.launcher.window)
        XCTAssertTrue(launcher.isVisible)
        XCTAssertEqual(launcher.title, "Cutaway")
        XCTAssertNil(coordinator.inspector)
        let content = try XCTUnwrap(launcher.contentView)
        let empty = try XCTUnwrap(AppListViewTests.descendant(
            of: content, identifier: AppListViewController.emptyStateIdentifier))
        XCTAssertTrue(isShown(empty))
    }

    @MainActor
    func test_C_WIN_01_choosingAnAppOpensItsWindowAndPutsTheLauncherAway() throws {
        let (coordinator, model) = started()

        try choose(0, in: coordinator)

        XCTAssertEqual(model.inspectedApp, Self.simulator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        XCTAssertEqual(inspector.location, Self.simulator)
        let window = try XCTUnwrap(inspector.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.title, "Demo")
        XCTAssertEqual(window.subtitle, "iPhone 16 · iOS 18.0")
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)
    }

    @MainActor
    func test_C_WIN_01_closingTheInspectorLeavesAndBringsBackTheLauncher() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let window = try XCTUnwrap(coordinator.inspector?.window)

        window.performClose(nil)

        XCTAssertFalse(window.isVisible)
        XCTAssertNil(coordinator.inspector)
        XCTAssertNil(model.inspectedApp)
        XCTAssertTrue(try XCTUnwrap(coordinator.launcher.window).isVisible)
        // Back in the list, no row is selected.
        XCTAssertEqual(coordinator.launcher.listController.tableView.selectedRow, -1)
    }

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

    @MainActor
    func test_C_WIN_01_theAppsButtonAndTheMenuShowTheLauncher() throws {
        let (coordinator, _) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let launcher = try XCTUnwrap(coordinator.launcher.window)
        XCTAssertFalse(launcher.isVisible)

        // The toolbar's button.
        let toolbar = try XCTUnwrap(inspector.window?.toolbar)
        let apps = try XCTUnwrap(
            toolbar.items.first { $0.itemIdentifier == InspectorWindowController.appsItem })
        XCTAssertEqual(apps.label, "Apps")
        XCTAssertNotNil(apps.image)
        NSApplication.shared.sendAction(try XCTUnwrap(apps.action), to: apps.target, from: apps)
        XCTAssertTrue(launcher.isVisible)
        XCTAssertTrue(try XCTUnwrap(inspector.window).isVisible, "the inspector stays")

        // The menu's item.
        launcher.orderOut(nil)
        let menu = coordinator.makeMainMenu()
        let item = try XCTUnwrap(menu.items.compactMap(\.submenu).flatMap(\.items).first {
            $0.title == "Show App List"
        })
        XCTAssertEqual(item.keyEquivalent, "0")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .shift])
        NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        XCTAssertTrue(launcher.isVisible)
    }

    @MainActor
    func test_C_WIN_01_theMenuHasTheLeastTwoWindowsNeed() throws {
        let (coordinator, _) = started()
        let menu = coordinator.makeMainMenu()
        let items = menu.items.compactMap(\.submenu).flatMap(\.items)
        func item(_ title: String) throws -> NSMenuItem {
            try XCTUnwrap(items.first { $0.title == title }, title)
        }
        // The two windows' own commands; the rest of the menu bar is C-MENU-01's.
        XCTAssertEqual(try item("Close Window").action, #selector(NSWindow.performClose(_:)))
        XCTAssertTrue(try item("Show App List").target === coordinator)
    }

    @MainActor
    func test_C_PREV_02_theMenuSwitchesTheMode() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))

        inspector.showThreeD(nil)
        XCTAssertEqual(inspection.previewMode, .threeD)
        XCTAssertEqual(inspector.modeControl?.selectedSegment, 1)
        let item = NSMenuItem(
            title: "2D", action: #selector(InspectorWindowController.showTwoD(_:)),
            keyEquivalent: "1")
        XCTAssertTrue(inspector.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
        inspector.showTwoD(nil)
        XCTAssertEqual(inspection.previewMode, .twoD)
        XCTAssertTrue(inspector.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
    }

    @MainActor
    func test_C_WIN_01_switchingAppsKeepsTheRememberedFrame() throws {
        let model = AppListStore()
        var other = Self.demo
        other.name = "Other"
        model.apply(.found(Self.simulator, Self.demo, session()))
        model.apply(.found(Self.second, other, session()))
        let coordinator = WindowCoordinator(
            store: model, discoversDevices: false, remembersWindowFrames: true)
        coordinator.start()
        addTeardownBlock { @MainActor in
            coordinator.inspector?.close()
            coordinator.launcher.close()
        }

        try choose(0, in: coordinator)
        XCTAssertEqual(coordinator.inspector?.window?.frameAutosaveName, "Inspector")
        coordinator.showAppList(nil)
        try choose(1, in: coordinator)
        XCTAssertEqual(coordinator.inspector?.window?.frameAutosaveName, "Inspector")
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

    @MainActor
    func test_C_WIN_01_theLauncherHasNoFullScreen() throws {
        let (coordinator, _) = started()
        let window = try XCTUnwrap(coordinator.launcher.window)
        // Shown after a full-screen inspector closes, it would otherwise take its place.
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenPrimary))
        let item = NSMenuItem(
            title: "", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        XCTAssertFalse(window.validateUserInterfaceItem(item))
        // The inspector still has it.
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector?.window)
        XCTAssertTrue(inspector.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertTrue(inspector.validateUserInterfaceItem(item))
    }

    @MainActor
    func test_C_WIN_02_openingAnInspectorLeavesTheLauncherAsItIs() throws {
        let (coordinator, _) = started()
        let launcher = try XCTUnwrap(coordinator.launcher.window)
        let content = launcher.contentViewController
        let list = coordinator.launcher.listController.view
        let frame = launcher.frame

        try choose(0, in: coordinator)

        XCTAssertTrue(launcher.contentViewController === content)
        XCTAssertTrue(isShown(list))
        XCTAssertEqual(coordinator.launcher.listController.appCount, 2)
        XCTAssertEqual(launcher.frame, frame)
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

    // MARK: - The inspection's panes

    @MainActor
    func test_C_HIER_01_theInspectorShowsTheLayersBesideThePreview() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let split = try XCTUnwrap(coordinator.inspector?.splitController)
        let items = split.splitViewItems
        XCTAssertEqual(items.map(\.behavior), [.sidebar, .default, .inspector])
        XCTAssertTrue(items[0].viewController === split.hierarchyController)
        XCTAssertTrue(items[1].viewController === split.containerController)
        XCTAssertTrue(items[2].viewController === split.attributesController)
        let preview = try XCTUnwrap(split.previewController.preview)
        XCTAssertTrue(preview.isDescendant(of: split.containerController.view))

        try XCTUnwrap(model.inspection(at: Self.simulator)).apply(try Fixtures.hierarchy())
        let outline = split.hierarchyController.outlineView
        // The tree opens down to its view controller (C-HIER-09): layers 5 and 7 are inside
        // the collapsed layers 4 and 6.
        XCTAssertEqual(outline.numberOfRows, 7)
        XCTAssertTrue(isShown(outline))
        coordinator.inspector?.window?.layoutIfNeeded()
        for row in 0..<7 {
            XCTAssertTrue(
                outline.visibleRect.contains(outline.rect(ofRow: row)),
                "row \(row) is not in view: \(outline.rect(ofRow: row)) in \(outline.visibleRect)")
        }

        // The sidebar cannot be made narrower than its minimum.
        split.splitView.setPosition(50, ofDividerAt: 0)
        coordinator.inspector?.window?.layoutIfNeeded()
        XCTAssertGreaterThanOrEqual(
            split.splitView.arrangedSubviews[0].frame.width,
            InspectorSplitViewController.minimumSidebarWidth)
    }

    @MainActor
    func test_C_HIER_02_comingBackToAnAppShowsItsLayersAsTheyWereLeft() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        // Layers 4 and 6 start collapsed (C-HIER-09); the user opens 6.
        inspection.setExpanded(6, true)
        inspection.select(7)

        coordinator.inspector?.close()
        XCTAssertNil(coordinator.inspector)
        try choose(0, in: coordinator)

        // A new outline over the same state: layer 5 is folded away inside layer 4, layer 6
        // is open, and layer 7, in row 5, is selected.
        let outline = try XCTUnwrap(coordinator.inspector?.splitController.hierarchyController)
            .outlineView
        XCTAssertEqual(outline.numberOfRows, 8)
        XCTAssertEqual(outline.selectedRow, 5)
    }

    @MainActor
    func test_C_ATTR_01_resizingTheWindowResizesOnlyThePreview() throws {
        let (coordinator, _) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let window = try XCTUnwrap(inspector.window)
        let panes = inspector.splitController.splitView.arrangedSubviews
        let previewWidth = panes[1].frame.width
        // Narrower than the default on a small screen.
        let width = try XCTUnwrap(window.contentView).bounds.width

        window.setContentSize(NSSize(width: 1440, height: 760))
        window.layoutIfNeeded()
        XCTAssertEqual(panes[0].frame.width, InspectorSplitViewController.sidebarWidth)
        XCTAssertEqual(panes[2].frame.width, InspectorSplitViewController.inspectorWidth)
        XCTAssertEqual(panes[1].frame.width, previewWidth + 1440 - width, accuracy: 1)
    }

    @MainActor
    func test_C_ATTR_01_theSmallestWindowHasRoomForEveryPane() throws {
        let (coordinator, _) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let window = try XCTUnwrap(inspector.window)
        let items = inspector.splitController.splitViewItems
        let panes = inspector.splitController.splitView.arrangedSubviews
        XCTAssertEqual(window.contentMinSize, InspectorWindowController.minimumSize)

        window.setContentSize(window.contentMinSize)
        window.layoutIfNeeded()
        XCTAssertEqual(window.contentView?.bounds.width, InspectorWindowController.minimumSize.width)
        XCTAssertGreaterThanOrEqual(
            panes[0].frame.width, InspectorSplitViewController.minimumSidebarWidth)
        XCTAssertGreaterThanOrEqual(
            panes[1].frame.width, InspectorSplitViewController.minimumPreviewWidth)
        XCTAssertGreaterThanOrEqual(
            panes[2].frame.width, InspectorSplitViewController.minimumInspectorWidth)
        XCTAssertFalse(items.contains { $0.isCollapsed })
    }

    // MARK: - Symbols

    @MainActor
    func test_C_LIST_01_everySymbolTheInterfaceUsesExists() {
        for name in Theme.Symbol.all {
            XCTAssertNotNil(Theme.symbol(name), name)
        }
    }

    // MARK: - C-HIER-04 to 06: the list's commands

    @MainActor
    func test_C_HIER_04_theMenuHasTheListsCommands() throws {
        let (coordinator, _) = started()
        let items = coordinator.makeMainMenu().items.compactMap(\.submenu).flatMap(\.items)
        func item(_ title: String) throws -> NSMenuItem {
            try XCTUnwrap(items.first { $0.title == title }, title)
        }
        XCTAssertEqual(try item("Find…").keyEquivalent, "f")
        XCTAssertEqual(
            try item("Find…").action, #selector(InspectorWindowController.findLayer(_:)))
        XCTAssertEqual(
            try item("Focus on Selected Layer").action,
            #selector(InspectorWindowController.focusOnSelectedLayer(_:)))
        XCTAssertEqual(
            try item("Show All Layers").action,
            #selector(InspectorWindowController.showAllLayers(_:)))
        XCTAssertEqual(
            try item("Expand All").action, #selector(InspectorWindowController.expandAllLayers(_:)))
        XCTAssertEqual(
            try item("Collapse All").action,
            #selector(InspectorWindowController.collapseAllLayers(_:)))
        // Their shortcuts are C-MENU-01's.
    }

    @MainActor
    func test_C_HIER_05_theViewMenuFocusesAndShowsAll() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        func valid(_ action: Selector) -> Bool {
            inspector.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        let focus = #selector(InspectorWindowController.focusOnSelectedLayer(_:))
        let showAll = #selector(InspectorWindowController.showAllLayers(_:))

        XCTAssertFalse(valid(focus), "nothing selected")
        XCTAssertFalse(valid(showAll), "no focus")
        inspection.select(4)
        XCTAssertTrue(valid(focus))
        inspector.focusOnSelectedLayer(nil)
        XCTAssertEqual(inspection.focusedLayerID, 4)
        XCTAssertFalse(valid(focus), "focused on it already")
        XCTAssertTrue(valid(showAll))
        inspector.showAllLayers(nil)
        XCTAssertNil(inspection.focusedLayerID)
    }

    @MainActor
    func test_C_HIER_06_theViewMenuExpandsAndCollapsesAll() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        inspector.collapseAllLayers(nil)
        XCTAssertEqual(inspection.tree.ids.filter(inspection.isExpanded), [])
        inspector.expandAllLayers(nil)
        XCTAssertEqual(inspection.tree.ids.filter(inspection.isExpanded).count, 9)
        inspection.setSearchText("label")
        let item = NSMenuItem(
            title: "", action: #selector(InspectorWindowController.expandAllLayers(_:)),
            keyEquivalent: "")
        XCTAssertFalse(inspector.validateMenuItem(item), "not during a search")
    }

    @MainActor
    func test_C_HIER_04_findPutsTheFocusInTheSearchField() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        try XCTUnwrap(model.inspection(at: Self.simulator)).apply(try Fixtures.hierarchy())
        inspector.findLayer(nil)
        let field = inspector.splitController.hierarchyController.searchField
        let editor = try XCTUnwrap(inspector.window?.firstResponder as? NSTextView)
        XCTAssertTrue(editor.delegate === field, "the field is being edited")
    }

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

    @MainActor
    func test_C_HIER_05_theListsCommandsAreUnavailableOnceDisconnected() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        inspection.select(4)
        inspection.focus(on: 2)
        inspector.store.connectionLost()
        for action in [
            #selector(InspectorWindowController.findLayer(_:)),
            #selector(InspectorWindowController.focusOnSelectedLayer(_:)),
            #selector(InspectorWindowController.showAllLayers(_:)),
            #selector(InspectorWindowController.expandAllLayers(_:)),
            #selector(InspectorWindowController.collapseAllLayers(_:)),
        ] {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            XCTAssertFalse(inspector.validateMenuItem(item), "\(action)")
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

    /// The Edit menu's item reads as the change it undoes.
    @MainActor
    func test_C_ATTR_08_theUndoItemNamesTheChange() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.attributes.setEditingSupported(true)
        let window = try XCTUnwrap(inspector.window)
        let undo = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        XCTAssertFalse(window.validateMenuItem(undo), "nothing to undo yet")

        // A change that succeeded is recorded as a group with its name (AttributesStore).
        let manager = inspection.attributes.undoManager
        let target = NSObject()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: target) { _ in }
        manager.setActionName("Change Opacity")
        manager.endUndoGrouping()
        XCTAssertTrue(window.validateMenuItem(undo))
        XCTAssertEqual(undo.title, "Undo Change Opacity")
        withExtendedLifetime(target) {}
    }

    // MARK: - C-DET-07: refreshing a subtree

    @MainActor
    func test_C_DET_07_theViewMenuRefreshesTheSelectedSubtree() throws {
        let (coordinator, model) = started()
        let items = coordinator.makeMainMenu().items.compactMap(\.submenu).flatMap(\.items)
        let item = try XCTUnwrap(items.first { $0.title == "Refresh Selected Subtree" })
        XCTAssertEqual(
            item.action, #selector(InspectorWindowController.refreshSelectedSubtree(_:)))

        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        let validation = NSMenuItem(title: "", action: item.action, keyEquivalent: "")
        inspection.select(4)
        XCTAssertFalse(inspector.validateMenuItem(validation), "a server below 0.3")
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
    func test_C_PREV_07_theMenuHasThePreviewsCommands() throws {
        let (coordinator, _) = started()
        let items = coordinator.makeMainMenu().items.compactMap(\.submenu).flatMap(\.items)
        func item(_ title: String) throws -> NSMenuItem {
            try XCTUnwrap(items.first { $0.title == title }, title)
        }
        XCTAssertEqual(
            try item("Show Hidden Layers").action,
            #selector(InspectorWindowController.toggleHiddenLayers(_:)))
        XCTAssertEqual(
            try item("Show Borders").action,
            #selector(InspectorWindowController.toggleBorders(_:)))
        let reset = try item("Reset View")
        XCTAssertEqual(reset.action, #selector(InspectorWindowController.resetView(_:)))
        XCTAssertEqual(reset.keyEquivalent, "0")
        XCTAssertEqual(reset.keyEquivalentModifierMask, .command)
    }

    @MainActor
    func test_C_PREV_08_theViewMenuSwitchesWhatThePreviewShows() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(model.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        let hidden = NSMenuItem(
            title: "", action: #selector(InspectorWindowController.toggleHiddenLayers(_:)),
            keyEquivalent: "")
        let borders = NSMenuItem(
            title: "", action: #selector(InspectorWindowController.toggleBorders(_:)),
            keyEquivalent: "")
        XCTAssertTrue(inspector.validateMenuItem(hidden))
        XCTAssertEqual(hidden.state, .off)
        XCTAssertTrue(inspector.validateMenuItem(borders))
        XCTAssertEqual(borders.state, .on)

        inspector.toggleHiddenLayers(nil)
        inspector.toggleBorders(nil)
        XCTAssertTrue(inspection.showsHiddenLayers)
        XCTAssertFalse(inspection.showsBorders)
        XCTAssertTrue(inspector.validateMenuItem(hidden))
        XCTAssertEqual(hidden.state, .on)
        XCTAssertTrue(inspector.validateMenuItem(borders))
        XCTAssertEqual(borders.state, .off)

        inspection.pan(by: 20, 0)
        inspector.resetView(nil)
        XCTAssertEqual(inspection.camera, .flat)
    }

    @MainActor
    func test_C_PREV_07_thePreviewsCommandsAreUnavailableOnceDisconnected() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        try XCTUnwrap(model.inspection(at: Self.simulator)).apply(try Fixtures.hierarchy())
        inspector.store.connectionLost()
        for action in [
            #selector(InspectorWindowController.toggleHiddenLayers(_:)),
            #selector(InspectorWindowController.toggleBorders(_:)),
            #selector(InspectorWindowController.resetView(_:)),
        ] {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            XCTAssertFalse(inspector.validateMenuItem(item), "\(action)")
        }
    }

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
        let toolbar = try XCTUnwrap(inspector.window?.toolbar)
        let item = try XCTUnwrap(
            toolbar.items.first { $0.itemIdentifier == InspectorWindowController.refreshItem })
        XCTAssertEqual(item.action, #selector(InspectorWindowController.refresh(_:)))
        XCTAssertTrue(item.target === inspector)
        XCTAssertEqual(item.toolTip, "Refresh")
        XCTAssertTrue(inspector.validateToolbarItem(item))

        let items = coordinator.makeMainMenu().items.compactMap(\.submenu).flatMap(\.items)
        let refresh = try XCTUnwrap(items.first { $0.title == "Refresh" })
        XCTAssertEqual(refresh.keyEquivalent, "r")
        XCTAssertEqual(refresh.action, #selector(InspectorWindowController.refresh(_:)))
        XCTAssertTrue(inspector.validateMenuItem(refresh))

        // The first load is still under way over the silent connection: the refresh is
        // queued behind it.
        XCTAssertTrue(inspection.isLoading)
        XCTAssertFalse(inspection.reloadAgain)
        inspector.refresh(nil)
        XCTAssertTrue(inspection.reloadAgain)
    }

    @MainActor
    func test_C_DET_05_refreshIsUnavailableOnceDisconnected() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        model.apply(.lost(Self.simulator))
        XCTAssertTrue(inspector.isDisconnected)
        let toolbar = try XCTUnwrap(inspector.window?.toolbar)
        let item = try XCTUnwrap(
            toolbar.items.first { $0.itemIdentifier == InspectorWindowController.refreshItem })
        XCTAssertFalse(inspector.validateToolbarItem(item))
        XCTAssertFalse(item.isEnabled, "greyed out now, not at the next event")
        let menuItem = NSMenuItem(
            title: "", action: #selector(InspectorWindowController.refresh(_:)), keyEquivalent: "")
        XCTAssertFalse(inspector.validateMenuItem(menuItem))
    }

    @MainActor
    func test_C_WIN_04_aLostAppThatCanComeBackSaysTheWindowWaits() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        model.apply(.lost(Self.simulator))
        let text = try XCTUnwrap(AppListViewTests.descendant(
            of: inspector.splitController.containerController.view,
            identifier: PreviewPaneViewController.disconnectedTextIdentifier) as? NSTextField)
        XCTAssertEqual(
            text.stringValue, "Lost the connection to Demo. Waiting for it to come back\u{2026}")
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
    func test_C_WIN_04_theLauncherStaysAsTheUserLeftIt() throws {
        let (coordinator, model) = started()
        try choose(0, in: coordinator)
        model.apply(.lost(Self.simulator))
        coordinator.showAppList(nil)
        model.apply(.found(Self.later, Self.demo, session()))
        XCTAssertEqual(coordinator.inspector?.location, Self.later)
        XCTAssertTrue(try XCTUnwrap(coordinator.launcher.window).isVisible)
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
    func test_C_HIER_01_theListHasTheKeyboardWhenTheWindowOpens() throws {
        let (coordinator, _) = started()
        try choose(0, in: coordinator)
        let inspector = try XCTUnwrap(coordinator.inspector)
        XCTAssertTrue(
            inspector.window?.initialFirstResponder
                === inspector.splitController.hierarchyController.outlineView)
    }

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
    func test_C_WIN_02_rememberedWidthsAreInPlaceBeforeTheWindowIsShown() throws {
        let defaults = try defaults()
        PaneWidths(key: "Inspector", defaults: defaults).save(sidebar: 330, inspector: 270)
        let inspector = try inspector(remembering: defaults)
        let window = try XCTUnwrap(inspector.window)
        XCTAssertFalse(window.isVisible)
        let panes = inspector.splitController.splitView.arrangedSubviews
        XCTAssertEqual(panes[0].frame.width, 330)
        XCTAssertEqual(panes[2].frame.width, 270)
        inspector.showWindow(nil)
        window.layoutIfNeeded()
        XCTAssertEqual(panes[0].frame.width, 330, "nothing moves once shown")
        XCTAssertEqual(panes[2].frame.width, 270)
        inspector.close()
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

    @MainActor
    func test_C_WIN_02_movingADividerIsRemembered() throws {
        let defaults = try defaults()
        let inspector = try inspector(remembering: defaults)
        let split = inspector.splitController.splitView
        XCTAssertEqual(
            split.arrangedSubviews[0].frame.width, InspectorSplitViewController.sidebarWidth)
        split.setPosition(350, ofDividerAt: 0)
        inspector.window?.layoutIfNeeded()
        let saved = PaneWidths(key: "Inspector", defaults: defaults).load()
        XCTAssertEqual(saved?.sidebar, 350)
        XCTAssertEqual(saved?.inspector, InspectorSplitViewController.inspectorWidth)
        inspector.close()
    }

    /// The app's icon in the toolbar stands on its own, without the shared glass capsule. How
    /// it looks is for a person to see.
    @MainActor
    func test_C_WIN_01_theAppIconHasNoCapsule() throws {
        let inspector = InspectorWindowController(
            location: Self.simulator, entry: nil, store: InspectionStore(session: session()))
        let toolbar = try XCTUnwrap(inspector.window?.toolbar)
        let icon = try XCTUnwrap(toolbar.items.first {
            $0.itemIdentifier == InspectorWindowController.appIconItem
        })
        XCTAssertFalse(icon.isBordered)
        inspector.close()
    }

    @MainActor
    func test_C_WIN_02_withoutAKeyNothingIsRemembered() {
        let inspector = InspectorWindowController(
            location: Self.simulator, entry: nil, store: InspectionStore(session: session()))
        XCTAssertNil(inspector.splitController.paneWidths)
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
    func test_C_LIST_01_aClickOpensTheClickedRowNotTheSelectedOne() throws {
        let (coordinator, model) = started()
        let list = coordinator.launcher.listController
        let table = list.tableView
        let row = try XCTUnwrap(list.tableRow(ofApp: 0))
        table.selectRowIndexes([row], byExtendingSelection: false)
        // The table's own action, with no row clicked: a selected row is not a click.
        XCTAssertEqual(table.clickedRow, -1)
        XCTAssertTrue(table.sendAction(table.action, to: table.target))
        XCTAssertNil(model.inspectedApp)
    }

    @MainActor
    func test_C_WIN_04_aReconnectionKeepsTheRememberedFramesName() throws {
        let model = AppListStore()
        model.apply(.found(Self.simulator, Self.demo, session()))
        let coordinator = WindowCoordinator(
            store: model, discoversDevices: false, remembersWindowFrames: true)
        coordinator.start()
        addTeardownBlock { @MainActor in
            coordinator.inspector?.close()
            coordinator.launcher.close()
            for key in ["NSWindow Frame Inspector", "NSWindow Frame Launcher",
                        "Inspector pane widths"]
            {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try choose(0, in: coordinator)
        let old = try XCTUnwrap(coordinator.inspector)
        // Within a 1024 by 768 display, which would move a window that is not.
        let frame = NSRect(x: 70, y: 104, width: 900, height: 560)
        old.window?.setFrame(frame, display: false)
        model.apply(.lost(Self.simulator))
        model.apply(.found(AppLocation.simulator(port: 48163), Self.demo, session()))
        let new = try XCTUnwrap(coordinator.inspector)
        XCTAssertFalse(new === old)
        XCTAssertEqual(new.window?.frame, frame, "the old window's place, not a remembered one")
        XCTAssertEqual(new.windowFrameAutosaveName, "Inspector")
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
