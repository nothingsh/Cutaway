import AppKit
import CutawayModel

/// Copy LLDB Command (C-SRC-06): for the layer of the row menu it was chosen from, or else the
/// selected one; available while that layer has the address the command needs. An archive's
/// addresses are those of when it was saved, which the items say.
extension InspectorWindowController {
    /// Edit › Copy LLDB Command › Print Object.
    @objc func copyLLDBPrintCommand(_ sender: Any?) {
        copyCommand(lldbCommands(sender)?.printObject)
    }

    /// Edit › Copy LLDB Command › Stop When the Frame Changes.
    @objc func copyLLDBFrameBreakpoints(_ sender: Any?) {
        copyCommand(lldbCommands(sender)?.breakOnFrameChanges)
    }

    /// Whether an item can copy its command; in an archive's window it says whose addresses
    /// they are.
    func validateLLDBItem(_ item: NSMenuItem) -> Bool {
        let note = isArchive ? localized("menu.edit.lldb.archivedAddresses") : nil
        if #available(macOS 14.4, *) { item.subtitle = note } else { item.toolTip = note }
        let commands = lldbCommands(item)
        return switch item.action {
        case #selector(copyLLDBPrintCommand(_:)): commands?.printObject != nil
        default: commands?.breakOnFrameChanges != nil
        }
    }

    private func lldbCommands(_ sender: Any?) -> LLDBCommands? {
        let id = (sender as? NSMenuItem)?.representedObject as? UInt64 ?? store.selectedLayerID
        return id.flatMap(store.tree.node).map(LLDBCommands.init)
    }

    private func copyCommand(_ text: String?) {
        guard let text else { return }
        AttributesViewController.copy(text, to: pasteboard)
    }
}

/// The Copy LLDB Command submenu (C-SRC-06), the same in the Edit menu and in a layer's
/// context menu. Its items go to the window's controller, which checks them.
enum LLDBMenu {
    static let identifier = NSUserInterfaceItemIdentifier("menu.copyLLDBCommand")

    /// For the layer `id`, or for the selected one when nil.
    @MainActor
    static func item(for id: UInt64?) -> NSMenuItem {
        let item = NSMenuItem(title: localized("menu.edit.copyLLDBCommand"), action: nil, keyEquivalent: "")
        item.identifier = identifier
        let submenu = NSMenu(title: item.title)
        for (title, action) in [
            (localized("menu.edit.lldb.printObject"), #selector(InspectorWindowController.copyLLDBPrintCommand(_:))),
            (localized("menu.edit.lldb.breakOnFrameChanges"),
             #selector(InspectorWindowController.copyLLDBFrameBreakpoints(_:))),
        ] {
            let command = NSMenuItem(title: title, action: action, keyEquivalent: "")
            command.representedObject = id
            submenu.addItem(command)
        }
        item.submenu = submenu
        return item
    }
}
