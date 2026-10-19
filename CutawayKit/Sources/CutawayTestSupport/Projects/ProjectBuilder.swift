import Foundation

/// A project folder made for a test in the temporary folder (C-SRC-01 to C-SRC-03), removed
/// with `remove()`. Nothing outside it is touched.
public final class ProjectBuilder {
    public let root: URL

    /// A new, empty folder.
    public init(name: String = "Project") throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutawayProjects-\(UUID().uuidString)", isDirectory: true)
        root = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Writes a file at `path`, relative to the root, making the folders on the way.
    @discardableResult
    public func write(_ path: String, _ text: String) throws -> URL {
        try write(path, Data(text.utf8))
    }

    @discardableResult
    public func write(_ path: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    public func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    /// A color set's `Contents.json` with one entry per appearance given (nil for any), sRGB
    /// with the red, green and blue components as written.
    public static func colorSet(_ entries: [(appearance: String?, rgb: [String])]) -> String {
        let colors = entries.map { entry in
            let appearances = entry.appearance.map {
                #","appearances":[{"appearance":"luminosity","value":"\#($0)"}]"#
            } ?? ""
            let components = zip(["red", "green", "blue"], entry.rgb).map { #""\#($0)":"\#($1)""# }
                + [#""alpha":"1.000""#]
            let color = #"{"color-space":"srgb","components":{\#(components.joined(separator: ","))}}"#
            return #"{"idiom":"universal"\#(appearances),"color":\#(color)}"#
        }
        return #"{"info":{"author":"xcode","version":1},"colors":[\#(colors.joined(separator: ","))]}"#
    }

    /// Removes the folder and the one made around it.
    public func remove() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }
}

/// Every file under a folder, hidden ones included, with its size and modification date
/// (C-SRC-01): two snapshots are equal when nothing was written in between.
public struct FolderSnapshot: Equatable {
    public struct File: Equatable {
        public var path: String
        public var size: Int
        public var modified: Date
    }

    public let files: [File]

    public init(_ root: URL) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        var files: [File] = []
        while let enumerator, let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            // The last components, as many as the entry is deep: the same however the
            // temporary folder's path is written (`/var` or `/private/var`).
            let path = url.pathComponents.suffix(enumerator.level).joined(separator: "/")
            files.append(File(
                path: path + (values?.isDirectory == true ? "/" : ""), size: values?.fileSize ?? 0,
                modified: values?.contentModificationDate ?? .distantPast))
        }
        self.files = files.sorted { $0.path < $1.path }
    }
}
