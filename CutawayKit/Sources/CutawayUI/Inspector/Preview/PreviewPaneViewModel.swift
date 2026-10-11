import Combine
import CutawayModel
import Foundation

/// What the panels over the preview show, derived from the inspection: the notice
/// (C-DET-04), the screenshots' progress (C-DET-02), "Loading layers…", the layer under the
/// pointer, whether the controls can be used (C-PREV-07), saving an archive and why it was
/// not saved (C-ARCH-02), why a screenshot was not exported (C-ARCH-06), and the notice of a
/// lost connection (C-WIN-03, C-WIN-04). It also takes "Saved" away after a while.
///
/// It only builds publishers when asked; the container subscribes to them where it lays its
/// panels out.
@MainActor
final class PreviewPaneViewModel {
    /// The notice's symbol: the app is not active, or something could not be loaded.
    enum NoticeSymbol: Equatable {
        case notActive
        case failed

        var name: String {
            switch self {
            case .notActive: Theme.Symbol.notActive
            case .failed: Theme.Symbol.screenshotsFailed
            }
        }
    }

    let store: InspectionStore
    let appName: String
    /// How long "Saved" stays before it fades.
    let savedNoticeDuration: Duration
    private var savedDismissal: Task<Void, Never>?

    /// Whether the connection is gone (C-WIN-03).
    var isDisconnected: AnyPublisher<Bool, Never> {
        store.$connection.map(\.isLost).removeDuplicates().eraseToAnyPublisher()
    }

    /// Whether the window waits for the lost app to come back (C-WIN-04).
    var isWaiting: AnyPublisher<Bool, Never> {
        store.$connection
            .map { connection in
                if case .lost(let waiting) = connection { return waiting }
                return false
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    init(store: InspectionStore, appName: String, savedNoticeDuration: Duration = .seconds(4)) {
        self.store = store
        self.appName = appName
        self.savedNoticeDuration = savedNoticeDuration
    }

    // MARK: - The notice and the screenshots' progress

    var notice: AnyPublisher<String?, Never> {
        Publishers.CombineLatest(store.$notice, isDisconnected)
            .map { [appName] notice, isDisconnected in
                isDisconnected ? nil : PreviewPaneText.noticeText(
                    notice, appName: appName)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var noticeSymbol: AnyPublisher<NoticeSymbol, Never> {
        store.$notice
            .map { notice -> NoticeSymbol in
                switch notice {
                case .appNotActive: return .notActive
                case .screenshotsFailed, .layersFailed, .layerGone, nil: return .failed
                }
            }
            .eraseToAnyPublisher()
    }

    var progress: AnyPublisher<String?, Never> {
        Publishers.CombineLatest3(
            store.$notice, store.$detailProgress, isDisconnected
        )
        .map { notice, progress, isDisconnected in
            // A notice says why loading stopped; the progress would only repeat it.
            notice == nil && !isDisconnected
                ? PreviewPaneText.progressText(progress) : nil
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    var fraction: AnyPublisher<Double, Never> {
        store.$detailProgress
            .map { $0.total > 0 ? Double($0.completed) / Double($0.total) : 0 }
            .eraseToAnyPublisher()
    }

    /// Whether the progress's panel shows, and whether a notice or a lost connection took its
    /// place, in which case it goes at once instead of fading out.
    var progressShown: AnyPublisher<(Bool, Bool), Never> {
        Publishers.CombineLatest(
            progress.map { $0 != nil },
            Publishers.CombineLatest(store.$notice, isDisconnected)
                .map { notice, disconnected in notice != nil || disconnected })
            .eraseToAnyPublisher()
    }

    var isLoading: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest3(store.$loadState, store.$tree, isDisconnected)
            .map { state, tree, isDisconnected in
                state == .loading && tree.isEmpty && !isDisconnected
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - The readout and the controls

    /// The layer under the pointer, or the selected one when the pointer is over none.
    var readout: AnyPublisher<LayerSummary?, Never> {
        Publishers.CombineLatest4(
            store.$hoveredLayerID, store.$selectedLayerID, store.$tree, isDisconnected
        )
        .map { hovered, selected, tree, isDisconnected in
            isDisconnected ? nil : LayerSummary(tree, hovered) ?? LayerSummary(tree, selected)
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    var isConnected: AnyPublisher<Bool, Never> {
        isDisconnected.map { !$0 }.eraseToAnyPublisher()
    }

    var spacingIsEnabled: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest(store.$previewMode, isDisconnected)
            .map { mode, disconnected in mode == .threeD && !disconnected }
            .eraseToAnyPublisher()
    }

    // MARK: - The lost connection

    var disconnectedText: AnyPublisher<String, Never> {
        isWaiting
            .map { [appName] waiting in
                PreviewPaneText.disconnectedText(appName: appName, waiting: waiting)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Saving an archive and exporting a screenshot

    /// How far the save is, while saving.
    var saving: AnyPublisher<(completed: Int, total: Int)?, Never> {
        store.$archiveSave.removeDuplicates()
            .map { state -> (completed: Int, total: Int)? in
                if case .saving(let completed, let total) = state { return (completed, total) }
                return nil
            }
            .eraseToAnyPublisher()
    }

    var archiveFraction: AnyPublisher<Double, Never> {
        saving.compactMap { $0 }.map {
            $0.total > 0 ? Double($0.completed) / Double($0.total) : 0
        }
        .eraseToAnyPublisher()
    }

    var archiveCount: AnyPublisher<String, Never> {
        saving.compactMap { $0 }.map {
            $0.total > 0 ? PreviewPaneText.countText($0.completed, of: $0.total) : ""
        }
        .eraseToAnyPublisher()
    }

    /// Where the archive was saved, once it is.
    var savedURL: AnyPublisher<URL?, Never> {
        store.$archiveSave.removeDuplicates()
            .map { state -> URL? in
                if case .saved(let url) = state { return url }
                return nil
            }
            .eraseToAnyPublisher()
    }

    /// "Saved …"; the last name stays while the panel fades out.
    var savedText: AnyPublisher<String, Never> {
        savedURL.compactMap { $0 }.map(PreviewPaneText.savedText).eraseToAnyPublisher()
    }

    /// Why the archive was not saved, or nil.
    var failure: AnyPublisher<String?, Never> {
        store.$archiveSave.removeDuplicates()
            .map { [appName] state -> String? in
                guard case .failed(let failure) = state else { return nil }
                return PreviewPaneText.archiveFailureText(failure, appName: appName)
            }
            .eraseToAnyPublisher()
    }

    /// Why the screenshot was not exported, or nil.
    var screenshotFailure: AnyPublisher<String?, Never> {
        store.$screenshotExport.removeDuplicates()
            .map { [appName] state -> String? in
                guard case .failed(let failure) = state else { return nil }
                return PreviewPaneText.screenshotFailureText(
                    failure, appName: appName)
            }
            .eraseToAnyPublisher()
    }

    /// "Saved" goes after a few seconds, unless another save took its place meanwhile.
    func dismissSaved(after url: URL?) {
        savedDismissal?.cancel()
        guard let url else { return }
        savedDismissal = Task { [weak self, savedNoticeDuration] in
            guard (try? await Task.sleep(for: savedNoticeDuration)) != nil,
                  let store = self?.store, store.archiveSave == .saved(url)
            else { return }
            store.dismissArchiveSave()
        }
    }
}
