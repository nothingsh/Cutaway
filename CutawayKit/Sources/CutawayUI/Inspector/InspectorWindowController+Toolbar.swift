import AppKit
import Combine
import CutawayModel
import DeclarativeAppKit
import DeclarativeCombine

// `modeControl` and `appIcon` are internal only so that this file can set and read them.
extension InspectorWindowController {
    // MARK: - The toolbar's controls

    private func makeModeControl() -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ["2D", "3D"], trackingMode: .selectOne, target: nil, action: nil)
        control.setImage(
            Theme.symbol(Theme.Symbol.twoD, size: 12, description: "2D"), forSegment: 0)
        control.setImage(
            Theme.symbol(Theme.Symbol.threeD, size: 12, description: "3D"), forSegment: 1)
        control.setToolTip(localized("toolbar.mode.twoD.tooltip"), forSegment: 0)
        control.setToolTip(localized("toolbar.mode.threeD.tooltip"), forSegment: 1)
        control
            .accessibilityIdentifier(Self.modeIdentifier)
            .bind(\.selectedSegment, to: store.$previewMode.map { $0 == .twoD ? 0 : 1 })
            .sink(\.selectedSegmentPublisher) { [weak store] segment in
                store?.setPreviewMode(segment == 0 ? .twoD : .threeD)
            }
        modeControl = control
        return control
    }

    /// "Archive", as a tag beside the app's icon (C-ARCH-05). The word sits in the middle of
    /// its border: a label draws its text at the top of its frame, so the border is a view of
    /// its own around it.
    private func makeArchiveTag() -> NSView {
        NSView().configure {
            $0.wantsLayer = true
            $0.layer?.cornerRadius = 4
            $0.layer?.borderWidth = 1
            $0.layer?.borderColor = NSColor.separatorColor.cgColor
            $0.addHStack(alignment: .center, spacing: 0) {
                NSTextField(labelWithString: localized("toolbar.archive.tag"))
                    .font(.systemFont(ofSize: 11, weight: .semibold))
                    .textColor(.secondaryLabelColor)
            }
            .padding(horizontal: 8, vertical: 0)
        }
        .accessibilityIdentifier(Self.archiveTagItem.rawValue)
        .frame(height: 18)
    }

    private func makeAppIconView() -> NSView {
        let view = NSImageView()
        view.image = appIcon ?? Theme.symbol(Theme.Symbol.appPlaceholder, size: 18)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.setAccessibilityLabel(localized("toolbar.app.icon"))
        return view.frame(width: 26, height: 26)
    }
}

extension InspectorWindowController: NSToolbarDelegate {
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // An archive is neither refreshed nor saved again, and has no app list to go back to.
        if isArchive {
            return [
                .toggleSidebar, .sidebarTrackingSeparator, Self.appIconItem, Self.archiveTagItem,
                .flexibleSpace, Self.modeItem, .inspectorTrackingSeparator, .flexibleSpace,
                .toggleInspector,
            ]
        }
        return [
            .toggleSidebar, .sidebarTrackingSeparator, Self.appIconItem, .flexibleSpace,
            Self.modeItem, Self.refreshItem, Self.saveArchiveItem, Self.appsItem,
            .inspectorTrackingSeparator,
            .flexibleSpace,
            .toggleInspector,
        ]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.appIconItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = makeAppIconView()
            item.label = localized("toolbar.app.label")
            item.isNavigational = true
            // On macOS 26 a bordered item sits in the toolbar's shared glass capsule; the icon
            // stands on its own beside the title.
            item.isBordered = false
            return item
        case Self.archiveTagItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = makeArchiveTag()
            item.label = localized("toolbar.archive.label")
            item.isBordered = false
            return item
        case Self.modeItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = makeModeControl()
            item.label = localized("toolbar.mode.label")
            item.toolTip = localized("toolbar.mode.tooltip")
            return item
        case Self.refreshItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            let refresh = localized("toolbar.refresh.label")
            item.image = Theme.symbol(Theme.Symbol.refresh, size: 14, description: refresh)
            item.label = refresh
            item.toolTip = refresh
            item.isBordered = true
            item.target = self
            item.action = #selector(refresh(_:))
            return item
        case Self.saveArchiveItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.image = Theme.symbol(
                Theme.Symbol.saveArchive, size: 14, description: localized("toolbar.saveArchive.label"))
            item.label = localized("toolbar.saveArchive.label")
            item.toolTip = localized("toolbar.saveArchive.tooltip")
            item.isBordered = true
            item.target = self
            item.action = #selector(saveArchive(_:))
            return item
        case Self.appsItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.image = Theme.symbol(
                Theme.Symbol.apps, size: 14, description: localized("toolbar.apps.label"))
            item.label = localized("toolbar.apps.label")
            item.toolTip = localized("toolbar.apps.tooltip")
            item.isBordered = true
            item.target = self
            item.action = #selector(showApps(_:))
            return item
        default:
            return nil
        }
    }
}

extension InspectorWindowController: NSToolbarItemValidation {
    /// Refreshing and saving need the connection (C-DET-05, C-ARCH-02), and neither while an
    /// archive is saved.
    public func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.refreshItem: commands.canRefresh
        case Self.saveArchiveItem: commands.canSaveArchive
        default: true
        }
    }
}
