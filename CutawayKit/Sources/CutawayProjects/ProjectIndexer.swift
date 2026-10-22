import Foundation
import os

/// Builds the index of one project folder (C-SRC-02), away from the main thread, and builds
/// it again reading only the files that changed since: by their modification date and size.
///
/// It walks the folder without following symbolic links, and leaves out hidden folders, those
/// of builds and third-party code, and frameworks and bundles. A file it cannot read, or one
/// too large to be the app's own, is skipped and counted; past the most files it takes, the
/// walk stops and says so. It only reads: nothing is written into the folder.
///
/// The walk, the reading and putting the index together block on the file system or take the
/// processor a while, so they run on a queue of their own, not on the threads Swift's tasks
/// share: as many files at a time as there are processors, but only a few large ones. A build
/// can be cancelled; one cancelled keeps what the last build read. A folder that cannot be
/// listed gives no index at all, not an empty one.
actor ProjectIndexer {
    /// How much of a folder is taken.
    struct Limits: Sendable {
        /// A source file or asset catalog file larger than this is skipped: most likely
        /// generated.
        var largestSourceFile: Int
        /// A string table larger than this is skipped. Far larger than a source file: a String
        /// Catalog of thousands of keys in 40 languages is tens of megabytes.
        var largestStringTable: Int
        /// The most files to index the walk takes; it stops at the next.
        var mostFiles: Int

        init(largestSourceFile: Int, largestStringTable: Int, mostFiles: Int) {
            self.largestSourceFile = largestSourceFile
            self.largestStringTable = largestStringTable
            self.mostFiles = mostFiles
        }

        static let standard = Limits(
            largestSourceFile: 4 * 1024 * 1024, largestStringTable: 64 * 1024 * 1024, mostFiles: 200_000)
    }

    /// Folders left out by name, wherever they are.
    static let skippedFolders: Set<String> = [
        "DerivedData", "build", ".build", "SourcePackages", "Pods", "Carthage", "node_modules",
    ]
    /// Folders left out by their extension: built code and resources, not the app's sources.
    static let skippedPackages: Set<String> = ["framework", "xcframework", "bundle"]

    /// The folder itself could not be listed: gone, or no longer readable.
    struct FolderUnreadable: Error {}

    /// A file larger than this is read only while fewer than `largeFilesAtOnce` others are:
    /// a string table may take several times its size in memory while it is read.
    static let largeFile = 4 * 1024 * 1024
    static let largeFilesAtOnce = 2

    nonisolated let root: URL
    nonisolated let limits: Limits
    private var cache: [String: Cached] = [:]
    /// The index the last build gave, given again while no file changed.
    private var last: ProjectIndex?

    init(root: URL, limits: Limits = .standard) {
        self.root = root
        self.limits = limits
    }

    /// Reads what changed since the last build and gives the whole index: the one given before,
    /// the same generation, when no file changed. Throws `CancellationError` once cancelled, and
    /// `FolderUnreadable` when the folder cannot be listed, keeping what the last build read.
    func build() async throws -> (ProjectIndex, ProjectIndexReport) {
        let (root, limits) = (root, limits)
        let walked = try await Self.offThePool { Self.walk(root, limits: limits, $0) }
        guard case .files(let candidates, let reachedFileLimit) = walked else { throw FolderUnreadable() }
        var report = ProjectIndexReport(reachedFileLimit: reachedFileLimit)
        var kept: [String: Cached] = [:]
        var toRead: [Candidate] = []
        for candidate in candidates {
            guard candidate.size <= Self.largest(candidate.kind, in: limits) else {
                report.tooLarge += 1
                continue
            }
            if let cached = cache[candidate.path], cached.modified == candidate.modified,
               cached.size == candidate.size
            {
                kept[candidate.path] = cached
                report.reused += 1
            } else {
                toRead.append(candidate)
            }
        }
        // No file to read, and as many kept as there were: the same files as last time, so
        // the same index.
        if toRead.isEmpty, kept.count == cache.count, let last { return (last, report) }

        let contents = try await Self.offThePool { [toRead] cancellation in
            Self.read(
                toRead, processors: ProcessInfo.processInfo.activeProcessorCount,
                isLarge: { $0.size > Self.largeFile }, cancellation, content: Self.content(of:))
        }
        for (candidate, content) in zip(toRead, contents) {
            guard let content else {
                report.unreadable += 1
                continue
            }
            kept[candidate.path] = Cached(modified: candidate.modified, size: candidate.size, content: content)
            report.read += 1
        }
        try Task.checkCancellation()
        // Only files that still cannot be read were tried again: the same index too.
        if report.read == 0, kept.count == cache.count, let last { return (last, report) }
        let index = try await Self.offThePool { [kept] _ in Self.index(of: kept, root: root) }
        cache = kept
        last = index
        return (index, report)
    }

    /// The values of the string tables last read, in the order of their files' paths.
    func strings() -> [LocalizedString] {
        cache.keys.sorted().flatMap { path -> [LocalizedString] in
            // swiftlint:disable:next force_unwrapping
            guard case .strings(let values) = cache[path]!.content else { return [] }
            return values
        }
    }

    // MARK: - Off the shared threads

    /// Where the walk and the reading run: they block on the file system.
    private static let queue = DispatchQueue(label: "CutawayProjects.indexing", qos: .utility)

    /// Whether the build a piece of work is for was cancelled, for work outside any task.
    final class Cancellation: Sendable {
        private let flag = OSAllocatedUnfairLock(initialState: false)

        var isCancelled: Bool { flag.withLock { $0 } }

        func cancel() {
            flag.withLock { $0 = true }
        }
    }

    /// Runs `work` on the indexing queue and waits for it, telling it once the task waiting is
    /// cancelled; `work` gives nil when it stopped for that.
    private static func offThePool<T: Sendable>(
        _ work: @escaping @Sendable (Cancellation) -> T?
    ) async throws -> T {
        let cancellation = Cancellation()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: work(cancellation)) }
            }
        } onCancel: {
            cancellation.cancel()
        }
        guard let result else { throw CancellationError() }
        try Task.checkCancellation()
        return result
    }

    // MARK: - Walking

    private enum Kind {
        case swift, objectiveC, colorSet, namespace, catalog
        case strings(language: String?)
    }

    /// What a folder is, for what the files in it are.
    private enum Place {
        case sources, assetCatalog, colorSet
    }

    private struct Candidate {
        var path: String
        var url: URL
        var kind: Kind
        var modified: Date
        var size: Int
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
    ]

    private enum Walked {
        /// The files to index, and whether there were more than the limits take.
        case files([Candidate], reachedFileLimit: Bool)
        /// The folder itself could not be listed.
        case folderUnreadable
    }

    /// The files to index under `root`, with their paths relative to it; nil once cancelled.
    /// A folder inside it that cannot be listed is left out.
    private static func walk(_ root: URL, limits: Limits, _ cancellation: Cancellation) -> Walked? {
        let manager = FileManager.default
        let keySet = Set(keys)
        var candidates: [Candidate] = []
        var folders: [(url: URL, path: String, place: Place)] = [(root, "", .sources)]
        while let folder = folders.popLast() {
            guard !cancellation.isCancelled else { return nil }
            guard let entries = try? manager.contentsOfDirectory(
                at: folder.url, includingPropertiesForKeys: keys)
            else {
                if folder.path.isEmpty { return .folderUnreadable }
                continue
            }
            for url in entries {
                let name = url.lastPathComponent
                guard let values = try? url.resourceValues(forKeys: keySet), values.isSymbolicLink != true
                else { continue }
                let path = folder.path.isEmpty ? name : folder.path + "/" + name
                if values.isDirectory == true {
                    if let place = place(ofFolder: name, extension: url.pathExtension, in: folder.place) {
                        folders.append((url, path, place))
                    }
                } else if values.isRegularFile == true,
                          let kind = kind(of: name, extension: url.pathExtension, in: folder)
                {
                    guard candidates.count < limits.mostFiles else {
                        return .files(candidates, reachedFileLimit: true)
                    }
                    candidates.append(Candidate(
                        path: path, url: url, kind: kind,
                        modified: values.contentModificationDate ?? .distantPast, size: values.fileSize ?? 0))
                }
            }
        }
        return .files(candidates, reachedFileLimit: false)
    }

    /// The largest file of a kind that is read.
    private static func largest(_ kind: Kind, in limits: Limits) -> Int {
        switch kind {
        case .catalog, .strings: limits.largestStringTable
        case .swift, .objectiveC, .colorSet, .namespace: limits.largestSourceFile
        }
    }

    /// What a folder inside `place` is, or nil when it is left out.
    private static func place(ofFolder name: String, extension: String, in place: Place) -> Place? {
        guard !name.hasPrefix("."), !skippedFolders.contains(name) else { return nil }
        switch place {
        case .sources:
            guard !skippedPackages.contains(`extension`) else { return nil }
            return `extension` == "xcassets" ? .assetCatalog : .sources
        case .assetCatalog:
            // A group may provide a namespace; image sets and the like hold no colours.
            if `extension` == "colorset" { return .colorSet }
            return `extension`.isEmpty ? .assetCatalog : nil
        case .colorSet:
            return nil
        }
    }

    private static func kind(
        of name: String, extension: String, in folder: (url: URL, path: String, place: Place)
    ) -> Kind? {
        switch folder.place {
        case .sources:
            switch `extension` {
            case "swift": return .swift
            case "h", "m", "mm": return .objectiveC
            case "xcstrings": return .catalog
            case "strings":
                let parent = folder.url.lastPathComponent
                return .strings(language: parent.hasSuffix(".lproj") ? String(parent.dropLast(6)) : nil)
            default: return nil
            }
        case .assetCatalog:
            return name == "Contents.json" ? .namespace : nil
        case .colorSet:
            return name == "Contents.json" ? .colorSet : nil
        }
    }

    // MARK: - Reading

    private enum Content {
        case swift([SwiftDeclarationScanner.Found])
        case objectiveC([ObjectiveCDeclarationScanner.Found])
        case colorSet([ColorSet.Entry])
        case namespace(Bool)
        case strings([LocalizedString])
    }

    private struct Cached {
        var modified: Date
        var size: Int
        var content: Content
    }

    /// Reads the items, as many at a time as there are processors, but at most
    /// `largeFilesAtOnce` of those `isLarge` tells; nil for one that cannot be read, and nil for
    /// all once cancelled.
    static func read<Item, Value>(
        _ items: [Item], processors: Int, isLarge: (Item) -> Bool, _ cancellation: Cancellation,
        content: (Item) -> Value?
    ) -> [Value?]? {
        let shares = shares(of: items.count, processors: processors)
        let large = DispatchSemaphore(value: largeFilesAtOnce)
        var contents = [Value?](repeating: nil, count: items.count)
        contents.withUnsafeMutableBufferPointer { buffer in
            // Each share writes only its own slots.
            nonisolated(unsafe) let buffer = buffer
            DispatchQueue.concurrentPerform(iterations: shares.count) { share in
                for position in shares[share] {
                    guard !cancellation.isCancelled else { return }
                    let item = items[position]
                    guard isLarge(item) else {
                        buffer[position] = content(item)
                        continue
                    }
                    large.wait()
                    buffer[position] = content(item)
                    large.signal()
                }
            }
        }
        return cancellation.isCancelled ? nil : contents
    }

    /// The consecutive, non-empty ranges `count` items are read in, together all of them once:
    /// more than there are processors, so that one with large files does not hold up the end.
    static func shares(of count: Int, processors: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let most = max(processors, 1) * 4
        let size = (count + most - 1) / most
        return stride(from: 0, to: count, by: size).map { $0..<min($0 + size, count) }
    }

    private static func content(of candidate: Candidate) -> Content? {
        guard let data = try? Data(contentsOf: candidate.url) else { return nil }
        let table = (candidate.url.lastPathComponent as NSString).deletingPathExtension
        switch candidate.kind {
        case .swift:
            return .swift(SwiftDeclarationScanner.declarations(in: data))
        case .objectiveC:
            return .objectiveC(ObjectiveCDeclarationScanner.declarations(in: data))
        case .colorSet:
            return (try? AssetCatalogReader.colorEntries(in: data)).map(Content.colorSet)
        case .namespace:
            return (try? AssetCatalogReader.providesNamespace(data)).map(Content.namespace)
        case .catalog:
            return (try? StringTableReader.catalog(data, table: table, file: candidate.path))
                .map(Content.strings)
        case .strings(let language):
            return (try? StringTableReader.strings(data, table: table, language: language, file: candidate.path))
                .map(Content.strings)
        }
    }

    // MARK: - The index

    private static func index(of files: [String: Cached], root: URL) -> ProjectIndex {
        var declarations: [String: [TypeDeclaration]] = [:]
        var colorSets: [ColorSet] = []
        var strings: [LocalizedString] = []
        for path in files.keys.sorted() {
            // Read in order of the paths: the index is the same however the files were read.
            // swiftlint:disable:next force_unwrapping
            switch files[path]!.content {
            case .swift(let found):
                for declaration in found {
                    declarations[declaration.name, default: []].append(TypeDeclaration(
                        name: declaration.name, enclosingTypes: declaration.enclosingTypes, kind: .swift,
                        file: path, line: declaration.line))
                }
            case .objectiveC(let found):
                for declaration in found {
                    declarations[declaration.name, default: []].append(TypeDeclaration(
                        name: declaration.name,
                        kind: declaration.isInterface ? .objectiveCInterface : .objectiveCImplementation,
                        file: path, line: declaration.line))
                }
            case .colorSet(let entries):
                colorSets.append(ColorSet(name: colorSetName(path, files), file: path, entries: entries))
            case .namespace:
                continue
            case .strings(let values):
                strings += values
            }
        }
        colorSets.sort { $0.name < $1.name }
        return ProjectIndex(root: root, declarations: declarations, colorSets: colorSets, strings: strings)
    }

    /// A color set's name: the set's own, after each folder between it and its catalog that
    /// provides a namespace. `path` is the set's `Contents.json`.
    private static func colorSetName(_ path: String, _ files: [String: Cached]) -> String {
        let parts = path.split(separator: "/").map(String.init)
        // ".../X.xcassets/Group/Name.colorset/Contents.json"
        let set = parts[parts.count - 2]
        let name = String(set.dropLast(".colorset".count))
        guard let catalog = parts.lastIndex(where: { $0.hasSuffix(".xcassets") }) else { return name }
        var spaces: [String] = []
        for folder in (catalog + 1)..<(parts.count - 2) {
            let contents = (parts[...folder] + ["Contents.json"]).joined(separator: "/")
            if case .namespace(true) = files[contents]?.content { spaces.append(parts[folder]) }
        }
        return (spaces + [name]).joined(separator: "/")
    }
}
