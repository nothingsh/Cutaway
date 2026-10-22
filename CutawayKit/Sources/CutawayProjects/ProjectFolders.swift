import Combine
import Foundation

/// The project folder linked to each app, by its bundle ID (C-SRC-01), kept in the user
/// defaults: the app's name for the Projects page, the folder's path and a bookmark that finds
/// it again once moved or renamed.
///
/// Reading is forgiving one app at a time: a link that cannot be read reads as none and is
/// left as it is kept.
@MainActor
public final class ProjectFolders: ObservableObject {
    public enum Key {
        public static let folders = "Projects.folders"
    }

    public struct Link: Equatable, Sendable {
        public var bundleID: String
        /// The app's name when the folder was linked.
        public var appName: String
        public var path: String
        public var bookmark: Data

        public init(bundleID: String, appName: String, path: String, bookmark: Data) {
            self.bundleID = bundleID
            self.appName = appName
            self.path = path
            self.bookmark = bookmark
        }
    }

    /// Where a linked folder is now.
    public enum Location: Equatable, Sendable {
        case found(URL)
        /// Gone from its path, and its bookmark finds nothing: moved, deleted, in the Trash or
        /// on a disk not connected. Read as not linked; the link is kept.
        case missing(path: String)
    }

    /// The links, by the apps' names.
    @Published public private(set) var links: [Link] = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        links = readLinks()
    }

    public func link(for bundleID: String) -> Link? {
        links.first { $0.bundleID == bundleID }
    }

    /// Links `folder` to the app, in place of any folder linked before.
    public func link(_ folder: URL, bundleID: String, appName: String) {
        let bookmark = (try? folder.bookmarkData()) ?? Data()
        store(Link(bundleID: bundleID, appName: appName, path: folder.path, bookmark: bookmark))
    }

    /// Forgets the app's folder.
    public func remove(bundleID: String) {
        var kept = keptLinks()
        kept.removeValue(forKey: bundleID)
        defaults.set(kept, forKey: Key.folders)
        links = readLinks()
    }

    /// Where the app's folder is now, or nil when none is linked. Found by its bookmark once
    /// gone from its path, and then kept at its new path.
    ///
    /// A folder still at its path costs one look at the file system; the bookmark is only
    /// resolved once it is gone. A bookmark that has gone stale is made again in the
    /// background, and kept once made.
    public func locate(bundleID: String) -> Location? {
        guard var link = link(for: bundleID) else { return nil }
        let (location, isStale) = Self.location(of: link)
        if case .found(let url) = location, url.path != link.path || isStale {
            if url.path != link.path {
                link.path = url.path
                store(link)
            }
            if isStale { renewBookmark(of: url, bundleID: bundleID) }
        }
        return location
    }

    /// Makes a new bookmark of the folder away from the main thread, and keeps it unless the app
    /// was linked to another folder meanwhile.
    private func renewBookmark(of folder: URL, bundleID: String) {
        Task.detached(priority: .utility) { [weak self] in
            guard let fresh = try? folder.bookmarkData() else { return }
            await self?.keepBookmark(fresh, bundleID: bundleID, path: folder.path)
        }
    }

    private func keepBookmark(_ bookmark: Data, bundleID: String, path: String) {
        guard var link = link(for: bundleID), link.path == path else { return }
        link.bookmark = bookmark
        store(link)
    }

    /// Where a link's folder is now, as `locate(bundleID:)` finds it, without keeping
    /// anything.
    public func location(of link: Link) -> Location {
        Self.location(of: link).location
    }

    private static func location(of link: Link) -> (location: Location, isStale: Bool) {
        if isFolder(link.path) { return (.found(URL(fileURLWithPath: link.path, isDirectory: true)), false) }
        var isStale = false
        guard !link.bookmark.isEmpty,
              let url = try? URL(
                  resolvingBookmarkData: link.bookmark, options: [.withoutUI, .withoutMounting],
                  bookmarkDataIsStale: &isStale),
              isFolder(url.path), !url.pathComponents.contains(".Trash")
        else { return (.missing(path: link.path), false) }
        return (.found(url), isStale)
    }

    private static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - Keeping

    /// What is kept, every app's as it is, read or not.
    private func keptLinks() -> [String: Any] {
        defaults.dictionary(forKey: Key.folders) ?? [:]
    }

    private func store(_ link: Link) {
        var kept = keptLinks()
        kept[link.bundleID] = ["name": link.appName, "path": link.path, "bookmark": link.bookmark]
        defaults.set(kept, forKey: Key.folders)
        links = readLinks()
    }

    private func readLinks() -> [Link] {
        keptLinks().compactMap { bundleID, value in
            guard !bundleID.isEmpty, let fields = value as? [String: Any],
                  let path = fields["path"] as? String, !path.isEmpty
            else { return nil }
            return Link(
                bundleID: bundleID, appName: fields["name"] as? String ?? bundleID, path: path,
                bookmark: fields["bookmark"] as? Data ?? Data())
        }
        .sorted { first, second in
            let order = first.appName.localizedStandardCompare(second.appName)
            return order == .orderedSame ? first.bundleID < second.bundleID : order == .orderedAscending
        }
    }
}
