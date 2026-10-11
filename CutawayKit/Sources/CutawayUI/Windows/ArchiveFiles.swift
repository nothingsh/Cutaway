import AppKit
import CutawayModel
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A Cutaway archive, the type the app's Info.plist exports (C-ARCH-02, C-ARCH-04).
    static var cutawayArchive: UTType { UTType(exportedAs: "dev.cutaway.archive") }
}

/// The archives opened or saved lately, newest first, for File › Open Recent (C-ARCH-04).
@MainActor
public protocol RecentArchives: AnyObject {
    var urls: [URL] { get }
    func note(_ url: URL)
    func clear()
}

/// The system's list of recent documents, which the Dock's menu shows too.
final class SystemRecentArchives: RecentArchives {
    var urls: [URL] { NSDocumentController.shared.recentDocumentURLs }

    func note(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}

/// A list kept in memory, for tests: they must not touch the system's.
public final class MemoryRecentArchives: RecentArchives {
    public private(set) var urls: [URL] = []

    public init() {}

    public func note(_ url: URL) {
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
    }

    public func clear() {
        urls = []
    }
}

extension ArchiveOpenError {
    /// The title of the alert for an archive that cannot be opened (C-ARCH-04).
    static func openFailureTitle(_ url: URL) -> String {
        localized("archiveOpen.title", url.lastPathComponent)
    }

    /// Why it cannot (C-ARCH-04).
    var openFailureText: String {
        switch self {
        case .unreadable(let reason): reason
        case .notAnArchive: localized("archiveOpen.notAnArchive")
        case .incomplete: localized("archiveOpen.incomplete")
        case .damaged: localized("archiveOpen.damaged")
        case .newer: localized("archiveOpen.newer")
        case .otherMajor: localized("archiveOpen.otherMajor")
        }
    }
}
