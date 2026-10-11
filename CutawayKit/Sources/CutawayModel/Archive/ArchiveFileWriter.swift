import Foundation

/// Why the file could not be written: the system's reason, in the system's language. The
/// model has no text of its own (C-LOC-01), so a failure the system did not report is given
/// the system's text for an unknown write error.
struct ArchiveWriteError: Error {
    var reason: String

    static var unknown: Self {
        Self(reason: CocoaError(.fileWriteUnknown).localizedDescription)
    }
}

/// Writes an archive into a temporary file on the destination's volume and puts it in
/// place at the end. Off the main thread.
actor ArchiveFileWriter {
    private let destination: URL
    /// The folder the system gave for the temporary file; removed at the end.
    private let folder: URL
    private let temporary: URL
    private var handle: FileHandle?

    init(destination: URL) throws {
        self.destination = destination
        let manager = FileManager.default
        folder = try manager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination,
            create: true)
        temporary = folder.appendingPathComponent(destination.lastPathComponent)
        guard manager.createFile(atPath: temporary.path, contents: nil) else {
            try? manager.removeItem(at: folder)
            throw ArchiveWriteError.unknown
        }
        handle = try FileHandle(forWritingTo: temporary)
    }

    func write(_ data: Data) throws {
        guard let handle else { throw ArchiveWriteError.unknown }
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw ArchiveWriteError(reason: error.localizedDescription)
        }
    }

    /// Closes the file and puts it at the destination, replacing what is there.
    func finish() throws {
        let manager = FileManager.default
        do {
            try handle?.close()
            handle = nil
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
        } catch {
            discard()
            throw ArchiveWriteError(reason: error.localizedDescription)
        }
        try? manager.removeItem(at: folder)
    }

    /// Closes and removes the temporary file. The destination is left as it was.
    func discard() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: folder)
    }
}
