import Combine
import Foundation

/// Each app's project folder and the latest index of it (C-SRC-01, C-SRC-02): one for the
/// whole of Cutaway, shared by the windows of an app, its archives and the settings.
///
/// An index is built when asked: after a folder is linked, when a window of the app opens and
/// on ⌘R. One build of a folder at a time; asked again meanwhile, it builds once more after.
/// Indexes are kept in memory only, and not for ever: once no window follows an app's index,
/// it is one of the apps put aside, and past the most of those kept, the one put aside
/// longest ago is forgotten, its index and what its indexer read. Asked again, it is built
/// again from the start.
@MainActor
public final class ProjectSources: ObservableObject {
    /// What asking for an app's index found.
    public enum Status: Equatable, Sendable {
        case notLinked
        /// The folder is gone (`ProjectFolders.Location.missing`): no index.
        case missing(path: String)
        /// The index is being built, or built again.
        case updating
    }

    /// The apps whose index is kept while nothing follows it.
    public static let standardKeptAside = 2

    public let folders: ProjectFolders
    /// The latest index of each linked app, by bundle ID.
    @Published public private(set) var indexes: [String: ProjectIndex] = [:]
    /// What the latest build of each app's index did.
    public private(set) var reports: [String: ProjectIndexReport] = [:]

    private struct Indexing {
        let indexer: ProjectIndexer
        var build: Task<Void, Never>?
        var isAskedAgain = false
    }

    private var indexings: [String: Indexing] = [:]
    /// The apps whose missing folder has been told of since Cutaway opened.
    private var toldOfMissing: Set<String> = []
    /// How many follow each app's index (`index(for:)`).
    private var followers: [String: Int] = [:]
    /// The apps with an index that nothing follows, the one put aside longest ago first.
    private var asideOrder: [String] = []
    private let keptAside: Int

    /// `keptAside`: how many apps' indexes are kept while nothing follows them.
    public init(folders: ProjectFolders, keptAside: Int = ProjectSources.standardKeptAside) {
        self.folders = folders
        self.keptAside = keptAside
    }

    /// The app's index as it changes; nil while there is none. A new index is told of by its
    /// generation, never by comparing what two indexes hold.
    public func index(for bundleID: String) -> AnyPublisher<ProjectIndex?, Never> {
        $indexes
            .map { $0[bundleID] }
            .removeDuplicates { $0?.generation == $1?.generation }
            .handleEvents(
                receiveSubscription: { @Sendable [weak self] _ in
                    guard let self else { return }
                    Self.onMain { self.follow(bundleID) }
                },
                receiveCancel: { @Sendable [weak self] in
                    guard let self else { return }
                    Self.onMain { self.unfollow(bundleID) }
                })
            .eraseToAnyPublisher()
    }

    /// Links a folder to the app and builds its index.
    public func link(_ folder: URL, bundleID: String, appName: String) {
        folders.link(folder, bundleID: bundleID, appName: appName)
        update(bundleID: bundleID)
    }

    /// Forgets the app's folder and its index.
    public func remove(bundleID: String) {
        folders.remove(bundleID: bundleID)
        forget(bundleID)
    }

    /// Builds the app's index again, reading only what changed.
    @discardableResult
    public func update(bundleID: String) -> Status {
        // A build of the same folder under way: the file system is not looked at here, and
        // the build after it reads what changed meanwhile.
        if let indexing = indexings[bundleID], indexing.build != nil,
           let link = folders.link(for: bundleID), indexing.indexer.root.path == link.path
        {
            indexings[bundleID]?.isAskedAgain = true
            return .updating
        }
        switch folders.locate(bundleID: bundleID) {
        case nil:
            forget(bundleID)
            return .notLinked
        case .missing(let path):
            forget(bundleID)
            return .missing(path: path)
        case .found(let folder):
            if indexings[bundleID]?.indexer.root.standardizedFileURL != folder.standardizedFileURL {
                forget(bundleID)
                indexings[bundleID] = Indexing(indexer: ProjectIndexer(root: folder))
            }
            if indexings[bundleID]?.build == nil {
                build(bundleID)
            } else {
                indexings[bundleID]?.isAskedAgain = true
            }
            return .updating
        }
    }

    /// Whether to tell that the app's folder is gone: the first time since Cutaway opened.
    public func shouldTellOfMissingFolder(bundleID: String) -> Bool {
        toldOfMissing.insert(bundleID).inserted
    }

    /// Returns once no build of the app's index is under way or asked for.
    public func waitForIndex(bundleID: String) async {
        while let build = indexings[bundleID]?.build {
            await build.value
        }
    }

    private func build(_ bundleID: String) {
        guard let indexer = indexings[bundleID]?.indexer else { return }
        // Below the interface's work, whoever asked for it.
        indexings[bundleID]?.build = Task(priority: .utility) { [weak self] in
            let built = try? await indexer.build()
            // Forgotten, or another folder linked, meanwhile.
            guard let self, self.indexings[bundleID]?.indexer === indexer else { return }
            if let (index, report) = built {
                self.reports[bundleID] = report
                // The same generation when no file changed: nothing new to follow.
                if self.indexes[bundleID]?.generation != index.generation { self.indexes[bundleID] = index }
            }
            self.indexings[bundleID]?.build = nil
            if self.indexings[bundleID]?.isAskedAgain == true {
                self.indexings[bundleID]?.isAskedAgain = false
                self.build(bundleID)
            } else if self.followers[bundleID, default: 0] == 0 {
                self.putAside(bundleID)
            }
        }
    }

    /// Forgets the app's index and stops any build of it.
    private func forget(_ bundleID: String) {
        indexings[bundleID]?.build?.cancel()
        indexings[bundleID] = nil
        reports[bundleID] = nil
        asideOrder.removeAll { $0 == bundleID }
        if indexes[bundleID] != nil { indexes[bundleID] = nil }
    }

    // MARK: - Followers

    /// Runs `work` on the main thread: at once when called there, as Combine does for the
    /// windows, and after when not.
    private nonisolated static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in work() }
        }
    }

    private func follow(_ bundleID: String) {
        followers[bundleID, default: 0] += 1
        asideOrder.removeAll { $0 == bundleID }
    }

    private func unfollow(_ bundleID: String) {
        guard let count = followers[bundleID] else { return }
        followers[bundleID] = count > 1 ? count - 1 : nil
        if count == 1 { putAside(bundleID) }
    }

    /// Puts the app's index aside, as the latest, and forgets those past the most kept.
    private func putAside(_ bundleID: String) {
        guard indexings[bundleID] != nil || indexes[bundleID] != nil else { return }
        asideOrder.removeAll { $0 == bundleID }
        asideOrder.append(bundleID)
        while asideOrder.count > keptAside {
            forget(asideOrder.removeFirst())
        }
    }
}
