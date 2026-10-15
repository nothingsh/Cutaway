import Combine
import CutawayModel
import Foundation

/// What the panels over the preview show, derived from the inspection: the notice
/// (C-DET-04), "Loading layers…", the layers the tags name (C-PREV-16), whether the controls
/// can be used (C-PREV-07), why an archive was not saved (C-ARCH-02), why a screenshot was not
/// exported (C-ARCH-06), and the notice of a lost connection (C-WIN-03, C-WIN-04).
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

    init(store: InspectionStore, appName: String) {
        self.store = store
        self.appName = appName
    }

    // MARK: - The notice

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

    var isLoading: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest3(store.$loadState, store.$tree, isDisconnected)
            .map { state, tree, isDisconnected in
                state == .loading && tree.isEmpty && !isDisconnected
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - The tags and the controls

    /// The layers the preview's tags name (C-PREV-16): the selected one, and the hovered one
    /// when it is another. None once the connection is gone.
    var tags: AnyPublisher<(selected: LayerSummary?, hovered: LayerSummary?), Never> {
        Publishers.CombineLatest4(
            store.$hoveredLayerID, store.$selectedLayerID, store.$tree, isDisconnected
        )
        .map { hovered, selected, tree, isDisconnected in
            guard !isDisconnected else { return (nil, nil) }
            return (LayerSummary(tree, selected), hovered == selected ? nil : LayerSummary(tree, hovered))
        }
        .removeDuplicates { $0.selected == $1.selected && $0.hovered == $1.hovered }
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

    // MARK: - What was not saved or exported

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
}
