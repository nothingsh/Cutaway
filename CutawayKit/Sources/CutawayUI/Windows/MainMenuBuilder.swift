import AppKit

/// Builds the menu bar (C-MENU-01). The coordinator's own commands are sent to it; the standard items have
/// no target: AppKit sends them along the responder chain and enables them as it does in
/// every app.
@MainActor
struct MainMenuBuilder {
    let coordinator: WindowCoordinator

    func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        add(makeAppMenu(), to: main)
        add(makeFileMenu(), to: main)
        add(makeEditMenu(), to: main)
        add(makeViewMenu(), to: main)
        let window = makeWindowMenu()
        add(window, to: main)
        let help = makeHelpMenu()
        add(help, to: main)
        // AppKit keeps the window list and the help menu's search field.
        NSApplication.shared.windowsMenu = window
        NSApplication.shared.helpMenu = help
        return main
    }

    private func makeAppMenu() -> NSMenu {
        let app = NSMenu(title: "Cutaway")
        add(localized("menu.app.about"), #selector(WindowCoordinator.showAbout(_:)), to: app).target =
            coordinator
        add(localized("menu.app.checkForUpdates"), #selector(WindowCoordinator.checkForUpdates(_:)), to: app).target =
            coordinator
        app.addItem(.separator())
        add(
            localized("menu.app.settings"), #selector(WindowCoordinator.showSettings(_:)), key: ",",
            to: app
        ).target = coordinator
        app.addItem(.separator())
        let services = NSMenu(title: localized("menu.app.services"))
        add(localized("menu.app.services"), nil, to: app).submenu = services
        NSApplication.shared.servicesMenu = services
        app.addItem(.separator())
        add(localized("menu.app.hide"), #selector(NSApplication.hide(_:)), key: "h", to: app)
        add(
            localized("menu.app.hideOthers"), #selector(NSApplication.hideOtherApplications(_:)), key: "h",
            modifiers: [.command, .option], to: app)
        add(localized("menu.app.showAll"), #selector(NSApplication.unhideAllApplications(_:)), to: app)
        app.addItem(.separator())
        add(localized("menu.app.quit"), #selector(NSApplication.terminate(_:)), key: "q", to: app)
        return app
    }

    private func makeFileMenu() -> NSMenu {
        let file = NSMenu(title: localized("menu.file.title"))
        add(
            localized("menu.file.open"), #selector(WindowCoordinator.openArchivePanel(_:)), key: "o",
            to: file
        ).target = coordinator
        let recent = NSMenu(title: localized("menu.file.openRecent"))
        recent.delegate = coordinator
        add(localized("menu.file.openRecent"), nil, to: file).submenu = recent
        file.addItem(.separator())
        // The window's app's project folder, and its classes there (C-SRC-01, C-SRC-03).
        add(
            localized("menu.file.linkProjectFolder"), #selector(InspectorWindowController.linkProjectFolder(_:)),
            to: file)
        add(
            localized("source.openInXcode"), #selector(InspectorWindowController.openInXcode(_:)), key: "o",
            modifiers: [.command, .option], to: file)
        file.addItem(.separator())
        add(
            localized("menu.file.saveArchive"), #selector(InspectorWindowController.saveArchive(_:)), key: "s",
            to: file)
        add(
            localized("menu.file.exportLayerScreenshot"),
            #selector(InspectorWindowController.exportLayerScreenshot(_:)), key: "e",
            modifiers: [.command, .shift], to: file)
        add(
            localized("menu.file.exportScreenshotWithSublayers"),
            #selector(InspectorWindowController.exportScreenshotWithSublayers(_:)), key: "e",
            modifiers: [.command, .shift, .option], to: file)
        file.addItem(.separator())
        add(localized("menu.file.closeWindow"), #selector(NSWindow.performClose(_:)), key: "w", to: file)
        return file
    }

    private func makeEditMenu() -> NSMenu {
        // Undo and Redo go to the window, which asks its undo manager: the inspector's is the
        // attribute changes (C-ATTR-08). The rest go to the text being edited.
        let edit = NSMenu(title: localized("menu.edit.title"))
        add(localized("menu.edit.undo"), Selector(("undo:")), key: "z", to: edit)
        add(localized("menu.edit.redo"), Selector(("redo:")), key: "z", modifiers: [.command, .shift], to: edit)
        edit.addItem(.separator())
        add(localized("menu.edit.cut"), #selector(NSText.cut(_:)), key: "x", to: edit)
        add(localized("menu.edit.copy"), #selector(NSText.copy(_:)), key: "c", to: edit)
        add(localized("menu.edit.paste"), #selector(NSText.paste(_:)), key: "v", to: edit)
        add(localized("menu.edit.delete"), #selector(NSText.delete(_:)), to: edit)
        add(localized("menu.edit.selectAll"), #selector(NSText.selectAll(_:)), key: "a", to: edit)
        edit.addItem(.separator())
        add(localized("menu.edit.find"), #selector(InspectorWindowController.findLayer(_:)), key: "f", to: edit)
        return edit
    }

    private func makeViewMenu() -> NSMenu {
        let view = NSMenu(title: localized("menu.view.title"))
        add(localized("menu.view.refresh"), #selector(InspectorWindowController.refresh(_:)), key: "r", to: view)
        add(
            localized("menu.view.refreshSelectedSubtree"),
            #selector(InspectorWindowController.refreshSelectedSubtree(_:)), key: "r",
            modifiers: [.command, .shift], to: view)
        view.addItem(.separator())
        addPreviewItems(to: view)
        view.addItem(.separator())
        addListItems(to: view)
        view.addItem(.separator())
        add(
            localized("menu.view.showSidebar"), #selector(NSSplitViewController.toggleSidebar(_:)), key: "s",
            modifiers: [.command, .control], to: view)
        add(
            localized("menu.view.showInspector"), #selector(NSSplitViewController.toggleInspector(_:)), key: "i",
            modifiers: [.command, .option], to: view)
        // AppKit shows an Enter Full Screen of its own with the system's shortcut and hides
        // this one, which still answers ⌃⌘F.
        add(
            localized("menu.view.enterFullScreen"), #selector(NSWindow.toggleFullScreen(_:)), key: "f",
            modifiers: [.command, .control], to: view)
        return view
    }

    /// The mode, the zoom and what the preview shows (C-PREV-02, C-PREV-05, C-PREV-07 to
    /// C-PREV-09, C-PREV-17).
    private func addPreviewItems(to view: NSMenu) {
        add("2D", #selector(InspectorWindowController.showTwoD(_:)), key: "1", to: view)
        add("3D", #selector(InspectorWindowController.showThreeD(_:)), key: "2", to: view)
        view.addItem(.separator())
        add(localized("menu.view.zoomIn"), #selector(InspectorWindowController.zoomIn(_:)), key: "=", to: view)
        add(localized("menu.view.zoomOut"), #selector(InspectorWindowController.zoomOut(_:)), key: "-", to: view)
        add(localized("menu.view.resetView"), #selector(InspectorWindowController.resetView(_:)), key: "0", to: view)
        view.addItem(.separator())
        add(
            localized("menu.view.showHiddenLayers"), #selector(InspectorWindowController.toggleHiddenLayers(_:)),
            key: "h", modifiers: [.command, .shift], to: view)
        add(localized("menu.view.borders"), nil, to: view).submenu = makeBordersMenu()
        add(
            localized("menu.view.showConstraintEnds"),
            #selector(InspectorWindowController.toggleConstraintEnds(_:)), key: "k",
            modifiers: [.command, .shift], to: view)
    }

    /// The borders' style (C-PREV-17). A submenu's own item takes no shortcut, so ⇧⌘B is on
    /// Show Borders, which turns them off and back to the style they had.
    private func makeBordersMenu() -> NSMenu {
        let borders = NSMenu(title: localized("menu.view.borders"))
        add(
            localized("menu.view.showBorders"), #selector(InspectorWindowController.toggleBorders(_:)), key: "b",
            modifiers: [.command, .shift], to: borders)
        borders.addItem(.separator())
        add(localized("menu.view.borders.plain"), #selector(InspectorWindowController.showPlainBorders(_:)),
            to: borders)
        add(localized("menu.view.borders.byKind"), #selector(InspectorWindowController.showBordersByKind(_:)),
            to: borders)
        borders.addItem(.separator())
        add(
            localized("menu.view.borders.onlyAppClasses"),
            #selector(InspectorWindowController.toggleOnlyAppClasses(_:)), to: borders)
        return borders
    }

    /// The list's commands (C-ATTR-16, C-HIER-05, C-HIER-06).
    private func addListItems(to view: NSMenu) {
        add(
            localized("menu.view.selectParent"), #selector(InspectorWindowController.selectParentLayer(_:)),
            key: Self.key(NSUpArrowFunctionKey), modifiers: [.command], to: view)
        add(
            localized("menu.view.selectFirstChild"),
            #selector(InspectorWindowController.selectFirstChildLayer(_:)),
            key: Self.key(NSDownArrowFunctionKey), modifiers: [.command], to: view)
        add(
            localized("menu.view.focusOnSelectedLayer"),
            #selector(InspectorWindowController.focusOnSelectedLayer(_:)),
            key: Self.key(NSDownArrowFunctionKey), modifiers: [.command, .option], to: view)
        add(
            localized("menu.view.showAllLayers"), #selector(InspectorWindowController.showAllLayers(_:)),
            key: Self.key(NSUpArrowFunctionKey), modifiers: [.command, .option], to: view)
        add(
            localized("menu.view.expandAll"), #selector(InspectorWindowController.expandAllLayers(_:)),
            key: Self.key(NSRightArrowFunctionKey), modifiers: [.command, .option], to: view)
        add(
            localized("menu.view.collapseAll"), #selector(InspectorWindowController.collapseAllLayers(_:)),
            key: Self.key(NSLeftArrowFunctionKey), modifiers: [.command, .option], to: view)
    }

    private func makeWindowMenu() -> NSMenu {
        let window = NSMenu(title: localized("menu.window.title"))
        add(localized("menu.window.minimize"), #selector(NSWindow.performMiniaturize(_:)), key: "m", to: window)
        add(localized("menu.window.zoom"), #selector(NSWindow.performZoom(_:)), to: window)
        window.addItem(.separator())
        add(
            localized("menu.window.showAppList"), #selector(WindowCoordinator.showAppList(_:)), key: "0",
            modifiers: [.command, .shift], to: window
        ).target = coordinator
        window.addItem(.separator())
        add(localized("menu.window.bringAllToFront"), #selector(NSApplication.arrangeInFront(_:)), to: window)
        return window
    }

    /// Two pages on the web (C-MENU-04); AppKit puts its search field above them.
    private func makeHelpMenu() -> NSMenu {
        let help = NSMenu(title: localized("menu.help.title"))
        add(localized("menu.help.cutawayHelp"), #selector(WindowCoordinator.openHelp(_:)), to: help).target =
            coordinator
        add(
            localized("menu.help.integratingServer"), #selector(WindowCoordinator.openIntegrationGuide(_:)),
            to: help
        ).target = coordinator
        return help
    }

    // MARK: - Building

    /// The key equivalent of one of AppKit's function keys, such as an arrow.
    static func key(_ functionKey: Int) -> String {
        String(Character(UnicodeScalar(UInt32(functionKey)) ?? " "))
    }

    @discardableResult
    private func add(
        _ title: String, _ action: Selector?, key: String = "",
        modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}
