import CutawayModel
import Foundation

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
