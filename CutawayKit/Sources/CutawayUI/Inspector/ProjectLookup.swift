import AppKit
import Combine
import CutawayModel

/// An inspector window's way to its app's project folder (C-SRC-01 to C-SRC-03): the index of
/// the folder linked to the app's bundle ID, where a layer's classes are declared, and opening
/// one in Xcode. An app's window and its archives' windows find the same folder.
@MainActor
final class ProjectLookup: NSObject {
    /// The app's bundle ID; nil when the app has none, and nothing can be linked.
    let bundleID: String?
    let appName: String
    let sources: ProjectSources?
    var opener = XcodeOpener()
    /// Offers the choice among several places: a menu below a view, or at the pointer when
    /// there is none. Tests record it.
    lazy var presentChoices: @MainActor ([SourceLocation], NSView?) -> Void = { [weak self] in
        self?.popUpChoices($0, from: $1)
    }

    init(bundleID: String?, appName: String, sources: ProjectSources?) {
        self.bundleID = bundleID.flatMap { $0.isEmpty ? nil : $0 }
        self.appName = appName
        self.sources = sources
    }

    /// Whether a folder can be linked to the app.
    var canLink: Bool { bundleID != nil && sources != nil }

    /// The folder linked now, or nil.
    var linkedFolder: URL? {
        guard let bundleID, let link = sources?.folders.link(for: bundleID) else { return nil }
        return URL(fileURLWithPath: link.path, isDirectory: true)
    }

    /// The app's index as it changes; nil while there is none.
    var index: AnyPublisher<ProjectIndex?, Never> {
        guard let bundleID, let sources else { return Just(nil).eraseToAnyPublisher() }
        return sources.index(for: bundleID)
    }

    var currentIndex: ProjectIndex? {
        bundleID.flatMap { sources?.indexes[$0] }
    }

    /// Links a folder to the app and builds its index.
    func link(_ folder: URL) {
        guard let bundleID else { return }
        sources?.link(folder, bundleID: bundleID, appName: appName)
    }

    /// Builds the app's index again, reading only what changed.
    @discardableResult
    func update() -> ProjectSources.Status {
        guard let bundleID, let sources else { return .notLinked }
        return sources.update(bundleID: bundleID)
    }

    /// Where the classes of a layer are declared.
    func openable(_ id: UInt64?, in tree: LayerTree) -> OpenableClasses {
        OpenableClasses(id.flatMap(tree.node), in: currentIndex)
    }

    /// Opens the one place, or offers the choice among several.
    func open(_ locations: [SourceLocation], from view: NSView? = nil) {
        switch locations.count {
        case 0: return
        case 1: opener.open(locations[0])
        default: presentChoices(locations, view)
        }
    }

    /// One of the choices, from a menu item made by `DeclarationChoices`.
    @objc func openChosenPlace(_ sender: NSMenuItem) {
        guard let location = sender.representedObject as? SourceLocation else { return }
        opener.open(location)
    }

    private func popUpChoices(_ locations: [SourceLocation], from view: NSView?) {
        let menu = NSMenu()
        for item in DeclarationChoices.items(for: locations, target: self, action: #selector(openChosenPlace(_:))) {
            menu.addItem(item)
        }
        if let view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 4 : -4), in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
}
