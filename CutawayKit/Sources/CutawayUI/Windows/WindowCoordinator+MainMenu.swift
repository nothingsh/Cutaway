import AppKit
import UniformTypeIdentifiers

extension WindowCoordinator {
    // MARK: - The menu

    /// The menu bar (C-MENU-01), with this coordinator as the target of its own commands.
    public func makeMainMenu() -> NSMenu {
        MainMenuBuilder(coordinator: self).makeMainMenu()
    }

    /// File › Open…: archives only, several at a time.
    @objc func openArchivePanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.cutawayArchive]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated { self?.openArchives(panel.urls) }
        }
    }

    @objc func openRecentArchive(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openArchives([url])
    }

    @objc func clearRecentArchives(_ sender: Any?) {
        recents.clear()
    }
}

extension WindowCoordinator: NSMenuDelegate {
    /// File › Open Recent: the recent archives by name, then Clear Menu (C-ARCH-04).
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in recents.urls {
            let item = NSMenuItem(
                title: url.lastPathComponent, action: #selector(openRecentArchive(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        if !recents.urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(
            title: localized("menu.file.clearRecent"), action: #selector(clearRecentArchives(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !recents.urls.isEmpty
        menu.addItem(clear)
    }
}
