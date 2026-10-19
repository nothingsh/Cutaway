import Foundation

/// Builds the index of one project folder (C-SRC-02), away from the main thread, and builds
/// it again reading only the files that changed since: by their modification date and size.
///
/// It walks the folder without following symbolic links, and leaves out hidden folders and
/// those of builds and third-party code. A file it cannot read, or one too large to be the
/// app's own, is skipped and counted. It only reads: nothing is written into the folder.
public actor ProjectIndexer {
    /// Folders left out by name, wherever they are.
    public static let skippedFolders: Set<String> = [
        "DerivedData", "build", ".build", "SourcePackages", "Pods", "Carthage",
    ]
    /// A source file larger than this is skipped: most likely generated.
    public static let largestFile = 4 * 1024 * 1024

    public nonisolated let root: URL
    private var cache: [String: Cached] = [:]

    public init(root: URL) {
        self.root = root
    }

    /// Reads what changed since the last build and gives the whole index.
    public func build() async -> (ProjectIndex, ProjectIndexReport) {
        var report = ProjectIndexReport()
        var kept: [String: Cached] = [:]
        var toRead: [Candidate] = []
        for candidate in Self.walk(root) {
            guard candidate.size <= Self.largestFile else {
                report.skipped += 1
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
        for (candidate, content) in await Self.read(toRead) {
            guard let content else {
                report.skipped += 1
                continue
            }
            kept[candidate.path] = Cached(modified: candidate.modified, size: candidate.size, content: content)
            report.read += 1
        }
        cache = kept
        return (Self.index(of: kept, root: root), report)
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

    /// The files to index under `root`, with their paths relative to it.
    private static func walk(_ root: URL) -> [Candidate] {
        let manager = FileManager.default
        let keySet = Set(keys)
        var candidates: [Candidate] = []
        var folders: [(url: URL, path: String, place: Place)] = [(root, "", .sources)]
        while let folder = folders.popLast() {
            guard let entries = try? manager.contentsOfDirectory(
                at: folder.url, includingPropertiesForKeys: keys)
            else { continue }
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
                    candidates.append(Candidate(
                        path: path, url: url, kind: kind,
                        modified: values.contentModificationDate ?? .distantPast, size: values.fileSize ?? 0))
                }
            }
        }
        return candidates
    }

    /// What a folder inside `place` is, or nil when it is left out.
    private static func place(ofFolder name: String, extension: String, in place: Place) -> Place? {
        guard !name.hasPrefix("."), !skippedFolders.contains(name) else { return nil }
        switch place {
        case .sources:
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

    /// Reads the files in parallel, a share of them in each task; nil for one that cannot be
    /// read.
    private static func read(_ candidates: [Candidate]) async -> [(Candidate, Content?)] {
        guard !candidates.isEmpty else { return [] }
        let shares = ProcessInfo.processInfo.activeProcessorCount * 4
        let size = max(1, (candidates.count + shares - 1) / shares)
        return await withTaskGroup(of: [(Candidate, Content?)].self) { group in
            for start in stride(from: 0, to: candidates.count, by: size) {
                let share = Array(candidates[start..<min(start + size, candidates.count)])
                group.addTask { share.map { ($0, content(of: $0)) } }
            }
            var all: [(Candidate, Content?)] = []
            all.reserveCapacity(candidates.count)
            for await part in group {
                all += part
            }
            return all
        }
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
