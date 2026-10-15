import AppKit
import Combine
import CutawayModel
import DeclarativeAppKit
import DeclarativeCombine

// `modeControl`, `appCapsule`, `appIcon`, `windowTitle` and `followStatus()` are internal
// only so that this file can set and read them.
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

    /// "Archive", as a tag beside the capsule (C-ARCH-05). The word sits in the middle of
    /// its border: a label draws its text at the top of its frame, so the border is a view of
    /// its own around it.
    private func makeArchiveTag() -> NSView {
        SeparatorOutlineView().configure {
            $0.layer?.cornerRadius = 4
            $0.layer?.borderWidth = 1
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

    /// The app's capsule (C-WIN-06): its name shows the app list, its buttons refresh and
    /// save, and it shows the screenshots' and the save's progress.
    private func makeAppCapsule() -> AppCapsuleView {
        let capsule = AppCapsuleView(
            title: windowTitle.title, subtitle: windowTitle.subtitle, icon: appIcon, isArchive: isArchive)
        capsule.onShowApps = { [weak self] in self?.showApps(nil) }
        capsule.onRefresh = { [weak self] in self?.refresh(nil) }
        capsule.onSave = { [weak self] in self?.saveArchive(nil) }
        capsule.onCancelSave = { [weak self] in self?.store.cancelArchiveSave() }
        capsule.onReveal = { [weak self] url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
            self?.store.dismissArchiveSave()
        }
        capsule.show(AppCapsuleState(
            subtitle: windowTitle.subtitle, detailProgress: .none, notice: nil, archiveSave: .idle,
            isDisconnected: false))
        appCapsule = capsule
        followStatus()
        return capsule
    }
}

extension InspectorWindowController: NSToolbarDelegate {
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // The capsule on the left, the mode alone on the right (C-WIN-06); an archive's
        // capsule has its tag beside it.
        [.toggleSidebar, .sidebarTrackingSeparator, Self.capsuleItem]
            + (isArchive ? [Self.archiveTagItem] : [])
            + [.flexibleSpace, Self.modeItem, .inspectorTrackingSeparator, .flexibleSpace, .toggleInspector]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.capsuleItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = makeAppCapsule()
            item.label = localized("toolbar.app.label")
            item.isNavigational = true
            // In the toolbar's glass, as the 2D / 3D switch is (C-WIN-06).
            item.isBordered = true
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
        default:
            return nil
        }
    }
}

/// A view outlined in the separator colour, taken again when the appearance changes
/// (C-PREF-03).
final class SeparatorOutlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}
