import AppKit

/// The sheets of the project folder (C-SRC-01): choosing a folder for an app, and saying that
/// the folder linked to it is gone.
@MainActor
enum ProjectFolderPanel {
    /// Asks for a folder on `window`, starting at `folder`, and calls back with the one
    /// chosen; not at all when the user cancels.
    static func choose(
        on window: NSWindow, appName: String, startingAt folder: URL?, then link: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = localized("source.link.message", appName)
        panel.prompt = localized("source.link.prompt")
        panel.directoryURL = folder
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            link(url)
        }
    }

    /// Says on `window` that the app's folder is gone, offering to choose it again.
    static func tellOfMissingFolder(
        on window: NSWindow, appName: String, path: String, chooseAgain: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localized("source.missing.title", appName)
        alert.informativeText = localized("source.missing.text", (path as NSString).abbreviatingWithTildeInPath)
        alert.addButton(withTitle: localized("source.missing.chooseAgain"))
        alert.addButton(withTitle: localized("source.missing.later"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { chooseAgain() }
        }
    }
}
