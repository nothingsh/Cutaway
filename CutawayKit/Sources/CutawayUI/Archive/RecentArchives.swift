import AppKit

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
