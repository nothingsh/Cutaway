import Combine
import CutawayModel
import Foundation

/// What the hierarchy list says around its rows, derived from the inspection: the text and
/// symbol that stand in for the rows, the footer's count, the path down to the focus, and
/// whether the expand menu can be used.
///
/// It only builds publishers when asked; the list subscribes to them where it lays itself out.
/// Where a publisher reads the store inside its closure, it does so there and then: the
/// property that publishes still holds its old value, those published before it the new ones.
@MainActor
final class HierarchyViewModel {
    /// One step of the path from the window's root layer down to the focus (C-HIER-05).
    struct PathStep: Equatable {
        var title: String
        var icon: LayerIcon
    }

    let store: InspectionStore
    /// The inspected app's name, for the text shown while it is not active (C-DET-04).
    let appName: String
    /// False once the connection is gone (C-WIN-03).
    var isConnected: AnyPublisher<Bool, Never> {
        store.$connection.map { !$0.isLost }.removeDuplicates().eraseToAnyPublisher()
    }

    init(store: InspectionStore, appName: String) {
        self.store = store
        self.appName = appName
    }

    // MARK: - In place of the rows

    /// The text that stands in for the whole pane while there is no tree to show, or nil.
    var loadStatus: AnyPublisher<String?, Never> {
        Publishers.CombineLatest(store.$loadState, store.$tree)
            .map { [appName] state, tree in
                Self.statusText(state, tree, appName: appName)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// The text that stands in for the rows: the load status, or that the search left none.
    /// The search field stays, so that the search can be cleared (C-HIER-04).
    var status: AnyPublisher<String?, Never> {
        Publishers.CombineLatest(loadStatus, store.$rowsRevision)
            .map { [weak store] status, _ in
                status ?? Self.noMatchText(store?.filter)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var isLoading: AnyPublisher<Bool, Never> {
        store.$loadState.map { $0 == .loading }.removeDuplicates().eraseToAnyPublisher()
    }

    /// The name of the SF Symbol above the status text, or nil for none.
    var statusSymbolName: AnyPublisher<String?, Never> {
        Publishers.CombineLatest3(store.$loadState, store.$tree, store.$rowsRevision)
            .map { [weak store] state, tree, _ -> String? in
                switch state {
                case .loading: return nil
                case .failed(.appNotActive):
                    return Theme.Symbol.hierarchyNotActive
                case .failed: return Theme.Symbol.hierarchyFailed
                case .loaded:
                    if tree.isEmpty {
                        return Theme.Symbol.emptyTree
                    }
                    guard Self.noMatchText(store?.filter) != nil else {
                        return nil
                    }
                    return Theme.Symbol.noMatches
                }
            }
            .eraseToAnyPublisher()
    }

    static func statusText(
        _ state: InspectionStore.LoadState, _ tree: LayerTree, appName: String
    ) -> String? {
        switch state {
        case .loading:
            return localized("hierarchy.status.loading")
        case .failed(.appNotActive):
            return localized("hierarchy.status.notActive", appName)
        case .failed(.invalidHierarchy(let explanation)):
            // The explanation is a developer's diagnostic and stays in English.
            return localized("hierarchy.status.invalid", explanation)
        case .failed(.other):
            return localized("hierarchy.status.failed")
        case .loaded:
            return tree.isEmpty ? localized("hierarchy.status.noWindows") : nil
        }
    }

    /// Nil unless there is a search and it left no rows (C-HIER-04).
    static func noMatchText(_ filter: HierarchyFilter?) -> String? {
        guard let filter, filter.shown.isEmpty else { return nil }
        return localized("hierarchy.search.noMatch", filter.text)
    }

    // MARK: - Around the rows

    /// The footer's text, as the rows change.
    var count: AnyPublisher<String, Never> {
        store.$rowsRevision
            .compactMap { [weak store] _ in store.map { Self.countText($0) } }
            .eraseToAnyPublisher()
    }

    /// The footer: how many matches the search left, or how many layers the focus, or the
    /// whole tree, has and how many of those are hidden. The numbers are written as the
    /// region writes them (C-LOC-02).
    static func countText(_ store: InspectionStore, locale: Locale = .current) -> String {
        func number(_ count: Int) -> String { count.formatted(.number.locale(locale)) }
        if let filter = store.filter {
            let count = filter.matches.count
            return localized("hierarchy.count.matches", count, number(count))
        }
        let tree = store.tree
        let ids = tree.layers(within: store.focusedLayerID).map(\.id)
        let hidden = ids.filter(tree.isDimmed).count
        let layers = localized("hierarchy.count.layers", ids.count, number(ids.count))
        return hidden == 0 ? layers : localized("hierarchy.count.hidden", layers, number(hidden))
    }

    /// Whether the expand menu can be used: not during a search, and not once the connection
    /// is gone (C-HIER-06).
    var expandEnabled: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest(store.$filter, isConnected)
            .map { filter, connected in filter == nil && connected }
            .eraseToAnyPublisher()
    }

    /// The steps from the window's root layer down to the focus, each with its title and
    /// icon.
    static func pathSteps(_ store: InspectionStore) -> [PathStep] {
        guard let focus = store.focusedLayerID else { return [] }
        let tree = store.tree
        return tree.path(to: focus).map { id in
            PathStep(title: tree.displayTitle(of: id), icon: LayerIcon(tree.node(id)))
        }
    }
}
