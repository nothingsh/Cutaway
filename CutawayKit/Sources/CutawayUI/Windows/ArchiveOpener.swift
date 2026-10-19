import AppKit
import CutawayModel

/// Opens archives, each in a window of its own (C-ARCH-04, C-WIN-05), and keeps those
/// windows: one per file, cascaded, listed in File › Open Recent.
@MainActor
final class ArchiveOpener {
    /// What File › Open Recent lists. The system's by default; tests keep their own.
    var recents: any RecentArchives = SystemRecentArchives()
    /// Says why an archive could not be opened. An alert by default; tests record it.
    var presentOpenFailure: @MainActor (URL, ArchiveOpenError) -> Void = ArchiveOpener.alert
    /// The archives' windows, in the order they opened (C-WIN-05).
    private(set) var windows: [InspectorWindowController] = []
    /// Called after one of the windows closed.
    var didCloseWindow: () -> Void = {}

    private let settings: AppSettings
    /// The apps' project folders: an archive's is found by the bundle ID it was saved from
    /// (C-SRC-01).
    private let projects: ProjectSources?
    private let maxTextureDimension: UInt32
    /// Where the side panes' widths are remembered; nil to start at the defaults every time.
    private let paneWidths: PaneWidths?
    /// Where the next archive's window goes: each one a little below and right of the last.
    private var cascadePoint = NSPoint.zero

    init(settings: AppSettings, projects: ProjectSources? = nil, maxTextureDimension: UInt32, paneWidths: PaneWidths?) {
        self.settings = settings
        self.projects = projects
        self.maxTextureDimension = maxTextureDimension
        self.paneWidths = paneWidths
    }

    /// Opens an archive in a window of its own, or brings its window to the front when it is
    /// open already. Returns the window, or nil after saying why the archive could not be
    /// opened.
    @discardableResult
    func open(_ url: URL) async -> InspectorWindowController? {
        if let open = window(showing: url) {
            open.showWindow(nil)
            return open
        }
        let archive: OpenedArchive
        do {
            archive = try await ArchiveFile.open(url, start: settings.inspectionStart)
        } catch {
            presentOpenFailure(url, error)
            return nil
        }
        // Opened twice at once: the first to finish has the window.
        if let open = window(showing: url) {
            open.showWindow(nil)
            return open
        }
        let inspection = InspectionStore(
            source: archive.source, maxTextureDimension: maxTextureDimension,
            start: settings.inspectionStart, text: .interface)
        let controller = InspectorWindowController(
            archive: archive, store: inspection, paneWidths: paneWidths, projects: projects)
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.windowWillClose(controller)
        }
        if let window = controller.window {
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        }
        windows.append(controller)
        inspection.restore(archive.state)
        inspection.enter()
        recents.note(url)
        controller.showWindow(nil)
        return controller
    }

    /// Opens archives one after another, without waiting for them.
    func open(_ urls: [URL]) {
        Task {
            for url in urls { await open(url) }
        }
    }

    private func window(showing url: URL) -> InspectorWindowController? {
        windows.first { $0.archiveURL.map { Self.isSameFile($0, url) } == true }
    }

    private func windowWillClose(_ controller: InspectorWindowController) {
        windows.removeAll { $0 === controller }
        controller.store.leave()
        didCloseWindow()
    }

    /// Whether two locations are one file: by the file system's identifier, or by the path
    /// when there is none.
    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let first = try? a.resourceValues(forKeys: key).fileResourceIdentifier,
           let second = try? b.resourceValues(forKeys: key).fileResourceIdentifier
        {
            return first.isEqual(second)
        }
        return a.standardizedFileURL.resolvingSymlinksInPath()
            == b.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func alert(_ url: URL, _ error: ArchiveOpenError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ArchiveOpenError.openFailureTitle(url)
        alert.informativeText = error.openFailureText
        alert.runModal()
    }
}
