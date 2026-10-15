import Combine
import CutawayModel
import Foundation

/// What the toolbar's app capsule shows (C-WIN-06): its subtitle and how it reads, the
/// hairline of progress along its bottom edge, and its two buttons. Worked out from the
/// inspection alone, so that it can be tested without a window.
struct AppCapsuleState: Equatable {
    /// How the subtitle reads.
    enum Tone: Equatable {
        /// The device and system, or the archive's details.
        case plain
        /// Something under way: the screenshots, or a save.
        case progress
        /// The archive was saved.
        case done
    }

    /// What the save button does.
    enum SaveAction: Equatable {
        case save
        /// Stops the save under way; the button looks pressed and shows a stop square.
        case cancel
        /// Shows the saved archive in the Finder; the button shows a tick.
        case reveal(URL)
    }

    var subtitle: String
    var tone: Tone
    /// How far the hairline is filled, from 0 to 1; nil hides it.
    var progress: Double?
    /// Whether the refresh button is tinted, while the screenshots load.
    var isRefreshing: Bool
    var canRefresh: Bool
    var saveAction: SaveAction
    var canSave: Bool

    /// The capsule of an app's window. `subtitle` is its device and system. A save under
    /// way, or just done, speaks over the screenshots' progress; a notice or a lost
    /// connection silences that progress, as it did the panel's (C-DET-02).
    init(
        subtitle: String, detailProgress: DetailProgress, notice: InspectionStore.Notice?,
        archiveSave: ArchiveSaveState, isDisconnected: Bool, locale: Locale = .current
    ) {
        self.subtitle = subtitle
        tone = .plain
        progress = nil
        isRefreshing = false
        canRefresh = !isDisconnected
        saveAction = .save
        canSave = !isDisconnected

        let screenshots = notice == nil && !isDisconnected
            ? PreviewPaneText.progressText(detailProgress, locale: locale) : nil
        if let screenshots {
            self.subtitle = localized("capsule.screenshots", screenshots)
            tone = .progress
            progress = Double(detailProgress.completed) / Double(detailProgress.total)
            isRefreshing = true
        }
        switch archiveSave {
        case .saving(let completed, let total):
            self.subtitle = total > 0
                ? localized("capsule.saving", PreviewPaneText.countText(completed, of: total, locale: locale))
                : localized("capsule.savingStarted")
            tone = .progress
            progress = total > 0 ? Double(completed) / Double(total) : 0
            // Nothing else asks the app while it is captured (C-DET-05).
            canRefresh = false
            saveAction = .cancel
            canSave = true
        case .saved(let url):
            self.subtitle = localized("capsule.saved")
            tone = .done
            saveAction = .reveal(url)
            canSave = true
        case .idle, .failed:
            break
        }
    }

    /// What the capsule shows as the inspection goes.
    @MainActor
    static func publisher(for store: InspectionStore, subtitle: String) -> AnyPublisher<Self, Never> {
        Publishers.CombineLatest4(
            store.$detailProgress, store.$notice, store.$archiveSave,
            store.$connection.map(\.isLost).removeDuplicates()
        )
        .map { progress, notice, save, disconnected in
            Self(
                subtitle: subtitle, detailProgress: progress, notice: notice, archiveSave: save,
                isDisconnected: disconnected)
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}
