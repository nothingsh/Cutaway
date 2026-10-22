import AppKit
import CutawayModel
import CutawayScene
import UniformTypeIdentifiers

/// The panels and sheets of an inspector window's files: where to save an archive (C-ARCH-02),
/// where to export a screenshot (C-ARCH-06), and the app's project folder (C-SRC-01). Each
/// panel can be replaced: tests answer it themselves.
@MainActor
final class InspectorFileActions {
    /// A panel that asks on a window where to save, suggesting a name without the extension,
    /// and calls back with the place chosen; not at all when the user cancels.
    typealias Destination = @MainActor (NSWindow, String, @escaping (URL) -> Void) -> Void

    /// Where to save an archive: a save panel on the window by default.
    var chooseArchiveDestination: Destination = { window, name, save in
        InspectorFileActions.runSavePanel(types: [.cutawayArchive], on: window, suggesting: name, then: save)
    }

    /// Where to export a screenshot: a save panel for PNG on the window by default.
    var chooseScreenshotDestination: Destination = { window, name, save in
        InspectorFileActions.runSavePanel(types: [.png], on: window, suggesting: name, then: save)
    }

    /// Asks for the app's project folder, starting at the one linked now, and calls back with
    /// the folder chosen; not at all when the user cancels. A folder panel on the window by
    /// default.
    var chooseProjectFolder: @MainActor (NSWindow, String, URL?, @escaping (URL) -> Void) -> Void =
        ProjectFolderPanel.choose

    /// Says that the app's folder is gone, offering to choose it again. A sheet on the window
    /// by default.
    var tellOfMissingFolder: @MainActor (NSWindow, String, String, @escaping () -> Void) -> Void =
        ProjectFolderPanel.tellOfMissingFolder

    private let store: InspectionStore
    private let project: ProjectLookup
    private let appName: String

    init(store: InspectionStore, project: ProjectLookup, appName: String) {
        self.store = store
        self.project = project
        self.appName = appName
    }

    /// Asks where to save, then captures the app into an archive there, if it still can be
    /// saved once the place is chosen.
    func saveArchive(on window: NSWindow, while canSave: @escaping @MainActor () -> Bool) {
        let version = AppVersion.current.version
        chooseArchiveDestination(
            window, InspectorWindowTitle.archiveName(appName: appName, at: Date())
        ) { [weak store] url in
            guard let store, canSave() else { return }
            store.saveArchive(to: url, cutawayVersion: version)
        }
    }

    /// Asks where to export the screenshot of a layer, then writes it there as PNG.
    func exportScreenshot(of id: UInt64, kind: TextureKey.Kind, on window: NSWindow) {
        let name = InspectorWindowTitle.screenshotName(
            title: store.tree.fileTitle(of: id), layerID: id, kind: kind)
        chooseScreenshotDestination(window, name) { [weak store] url in
            store?.exportScreenshot(of: id, kind: kind, to: url) { $0.pngData() }
        }
    }

    /// Asks for the folder of the window's app, by its bundle ID, and links it.
    func linkProjectFolder(on window: NSWindow) {
        guard project.canLink else { return }
        chooseProjectFolder(window, appName, project.linkedFolder) { [weak project] folder in
            project?.link(folder)
        }
    }

    /// Brings the project folder's index up to date (C-SRC-02); a folder that is gone is told
    /// of the first time since Cutaway opened, offering to choose it again.
    func updateProject(on window: NSWindow?) {
        guard case .missing(let path) = project.update(), let bundleID = project.bundleID,
              project.sources?.shouldTellOfMissingFolder(bundleID: bundleID) == true, let window
        else { return }
        tellOfMissingFolder(window, appName, path) { [weak self, weak window] in
            guard let window else { return }
            self?.linkProjectFolder(on: window)
        }
    }

    static func runSavePanel(
        types: [UTType], on window: NSWindow, suggesting name: String, then save: @escaping (URL) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = name
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            save(url)
        }
    }
}
