import CutawayWire
import Foundation

/// Why an archive cannot be opened (C-ARCH-04), as the person opening it needs to know.
public enum ArchiveOpenError: Error, Equatable, Sendable {
    /// The file cannot be read at all. The text is the system's reason.
    case unreadable(String)
    case notAnArchive
    /// The file ends early: it may not have finished copying or downloading.
    case incomplete
    case damaged
    /// Saved by a newer Cutaway: a newer format, or a newer minor protocol version.
    case newer
    /// Saved under another major protocol version.
    case otherMajor
}

/// An archive that opened: what its window shows, and the source to inspect it from.
public struct OpenedArchive: Sendable {
    public let url: URL
    public let source: ArchiveSource
    public let manifest: ArchiveManifest
    public let app: AppInfo
    /// Nil when the app had no icon, or it cannot be decoded.
    public let icon: Bitmap?
    /// The interface state to restore (C-ARCH-03).
    public let state: ArchiveState
}

public enum ArchiveFile {
    /// Opens an archive away from the main thread: maps the file, checks every frame
    /// (Resources/ARCHIVE.md) and indexes its layers. What the archive's interface state lacks is
    /// taken from `start` (C-PREF-02).
    public static func open(
        _ url: URL, start: InspectionStart = InspectionStart()
    ) async throws(ArchiveOpenError) -> OpenedArchive {
        try await Task.detached { load(url, start: start) }.value.get()
    }

    private static func load(
        _ url: URL, start: InspectionStart
    ) -> Result<OpenedArchive, ArchiveOpenError> {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .alwaysMapped)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        let decoder: ArchiveDecoder
        do {
            decoder = try ArchiveDecoder(data)
        } catch {
            return .failure(openError(for: error))
        }
        // The decoder checked that the Hello is the server's and has the app.
        guard let app = decoder.hello.app else { return .failure(.damaged) }
        return .success(OpenedArchive(
            url: url, source: ArchiveSource(decoder: decoder), manifest: decoder.manifest,
            app: app, icon: try? decoder.appIcon.image?.decoded(),
            state: ArchiveState(decoding: decoder.state, start: start)))
    }

    private static func openError(for error: ArchiveError) -> ArchiveOpenError {
        switch error {
        case .notAnArchive: .notAnArchive
        case .newerFormat, .newerProtocolMinor: .newer
        case .incomplete: .incomplete
        case .damaged, .noSuchChunk: .damaged
        case .differentProtocolMajor: .otherMajor
        }
    }
}
