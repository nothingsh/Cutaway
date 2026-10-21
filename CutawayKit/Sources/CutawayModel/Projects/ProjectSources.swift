import Combine
import Foundation

/// Each app's project folder and the latest index of it (C-SRC-01, C-SRC-02): one for the
/// whole of Cutaway, shared by the windows of an app, its archives and the settings.
///
/// An index is built when asked: after a folder is linked, when a window of the app opens and
/// on ⌘R. One build of a folder at a time; asked again meanwhile, it builds once more after.
/// Indexes are kept in memory only.
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

    public let folders: ProjectFolders
    /// The latest index of each linked app, by bundle ID.
    @Published public private(set) var indexes: [String: ProjectIndex] = [:]
    /// What the latest build of each app's index did.
    public private(set) var reports: [String: ProjectIndexReport] = [:]
    /// Counts the indexes each app was given, so that what follows an app's index tells a new
    /// one by its number: comparing two indexes reads every declaration and string of both,
    /// which for a large app holds the main thread for a second (C-SRC-02).
    private var indexNumbers: [String: Int] = [:]

    private struct Indexing {
        let indexer: ProjectIndexer
        var build: Task<Void, Never>?
        var isAskedAgain = false
    }

    private var indexings: [String: Indexing] = [:]
    /// The apps whose missing folder has been told of since Cutaway opened.
    private var toldOfMissing: Set<String> = []

    public init(folders: ProjectFolders) {
        self.folders = folders
    }

    /// The app's index as it changes; nil while there is none.
    public func index(for bundleID: String) -> AnyPublisher<ProjectIndex?, Never> {
        // Published before it is set: the number is set first.
        $indexes
            .map { [weak self] in (number: self?.indexNumbers[bundleID], index: $0[bundleID]) }
            .removeDuplicates { $0.number == $1.number }
            .map(\.index)
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
        indexings[bundleID]?.build = Task { [weak self] in
            let (index, report) = await indexer.build()
            // Forgotten, or another folder linked, meanwhile.
            guard let self, self.indexings[bundleID]?.indexer === indexer else { return }
            let last = self.reports[bundleID]
            self.reports[bundleID] = report
            // No file read, and as many kept as there were: the same files as last time, so
            // the same index, and nothing new to follow.
            let isUnchanged = last.map { report.read == 0 && report.reused == $0.read + $0.reused } ?? false
            if !isUnchanged || self.indexes[bundleID] == nil { self.setIndex(index, for: bundleID) }
            self.indexings[bundleID]?.build = nil
            if self.indexings[bundleID]?.isAskedAgain == true {
                self.indexings[bundleID]?.isAskedAgain = false
                self.build(bundleID)
            }
        }
    }

    private func forget(_ bundleID: String) {
        indexings[bundleID] = nil
        reports[bundleID] = nil
        if indexes[bundleID] != nil { setIndex(nil, for: bundleID) }
    }

    private func setIndex(_ index: ProjectIndex?, for bundleID: String) {
        indexNumbers[bundleID, default: 0] += 1
        indexes[bundleID] = index
    }
}
