import AppKit
import Combine
import CutawayModel
import DeclarativeAppKit
import DeclarativeCombine

/// The layers of the inspected app as an outline (C-HIER-01 to C-HIER-03), or a line of text
/// when there is no tree to show.
///
/// The store owns expansion and selection. What the user does in the outline is written to
/// the store; what the store publishes is shown in the outline, and showing it never writes
/// back.
final class HierarchyViewController: NSViewController {
    // What the HierarchyViewController+*.swift files use is internal here only so that they
    // can reach it: `store`, `viewModel`, the column's sizing state, the getters of `tree`
    // and `focus`, and what the outline view's data source and delegate
    // (HierarchyViewController+Outline.swift) read and write: `Item`, `roots`, `filter`,
    // `shownChildren`, `collapsedInside`, the guards `isShowingStore`, `writingExpansion` and
    // `showingStore`, and the helpers under "From the store to the outline". It belongs to
    // HierarchyViewController alone. What is internal for tests says so.

    static let outlineIdentifier = "hierarchy.outline"
    static let statusIdentifier = "hierarchy.status"
    static let countIdentifier = "hierarchy.count"
    static let searchIdentifier = "hierarchy.search"
    static let expandIdentifier = "hierarchy.expand"
    static let pathIdentifier = "hierarchy.path"
    static let leaveFocusIdentifier = "hierarchy.leaveFocus"

    static let rowIdentifier = NSUserInterfaceItemIdentifier("HierarchyRow")

    /// What the outline view holds for a layer. It recognises a row after a reload by the
    /// identity of this object, so there is one per layer for as long as the layer exists.
    final class Item: NSObject {
        let id: UInt64

        init(id: UInt64) {
            self.id = id
        }
    }

    // MARK: - Controls

    let outlineView = HierarchyOutlineView()
    /// The ancestors of the rows at the top, over the list (C-HIER-13).
    let stickyView = HierarchyStickyView()
    /// Collapse All, Expand to Level n, Expand All (C-HIER-06). Rebuilt when the rows change,
    /// which is when the levels there are can change.
    ///
    /// A bordered pull-down with its arrow, so that it reads as a menu beside the search field.
    let expandButton = NSPopUpButton(frame: .zero, pullsDown: true).configure {
        ($0.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
    }

    /// The steps from the window's root layer down to the focus (C-HIER-05).
    let pathControl = NSPathControl().configure {
        $0.pathStyle = .standard
        $0.focusRingType = .none
    }

    /// The search field (C-HIER-04). The window's Find command puts the focus in it.
    let searchField = NSSearchField().configure {
        // Every keystroke and the clear button send the action; typing is held back below.
        $0.sendsSearchStringImmediately = true
        $0.sendsWholeSearchString = false
    }

    /// How long, in seconds, typing in the search field must pause before its text reaches
    /// the store (C-HIER-04): a word typed quickly filters the whole tree once, not once a
    /// letter. Clearing the field and pressing Return do not wait.
    nonisolated static let searchDelay: TimeInterval = 0.15

    /// A text of the search field on its way to the store, and whether it goes at once. No
    /// text drops the one still waiting and sends nothing.
    private struct SearchEdit {
        let text: String?
        let isImmediate: Bool
    }

    /// What the search field sends. A newer edit replaces one still waiting.
    private let searchEdits = PassthroughSubject<SearchEdit, Never>()
    /// The typed text still waiting for its pause, if any.
    private var waitingSearchText: String?

    // MARK: - State

    let store: InspectionStore
    let viewModel: HierarchyViewModel
    /// What a row's context menu holds.
    let layerMenu: LayerContextMenu
    /// Whether the pointer is on a row (a sticky one too), each time it moves: ⌥ there
    /// measures the row's layer in the preview (C-PREV-10).
    var onPointerOverRow: ((Bool) -> Void)?
    /// What the outline shows, as the store last published it. Inside a subscription the
    /// store may already hold newer values.
    private(set) var tree = LayerTree.empty
    private(set) var filter: HierarchyFilter?
    private(set) var focus: UInt64?
    /// The outline's top rows: the focused layer, or every window's root layer; with a
    /// search, only those it leaves.
    private(set) var roots: [UInt64] = []
    private var items: [UInt64: Item] = [:]
    /// How wide each title is when shown in full. Class names repeat a lot.
    var titleWidths: [String: CGFloat] = [:]
    /// The column's width that every title of the tree needs.
    var titlesWidth: CGFloat = 0
    /// Set while a sizing of the column waits for the user's expansion to be over.
    var isColumnSizingPending = false
    /// True while the outline is being made to match the store. Its notifications are then
    /// not the user's doing.
    private(set) var isShowingStore = false
    /// Set while the outline writes an expansion to the store, which publishes it back.
    private var isWritingExpansion = false
    /// The children a search leaves, by layer, as the outline view has asked for them since
    /// the rows were last shown.
    var shownChildren: [UInt64: [UInt64]] = [:]
    /// Rows the outline view collapsed for good inside a row that is being collapsed with ⌥,
    /// waiting for that row's own notification, which comes last.
    var collapsedInside: [UInt64] = []
    /// The selected and the hovered layer as the store last published them: inside its
    /// subscriptions the store still holds the old ones. What the rows' guides, hover and the
    /// sticky rows show.
    var shownSelection: UInt64?
    var shownHover: UInt64?
    /// The rows in view as last reported to the store; nil before the first report.
    private var reportedVisible: [UInt64]?
    private var cancellables = Set<AnyCancellable>()

    init(store: InspectionStore, appName: String) {
        self.store = store
        viewModel = HierarchyViewModel(store: store, appName: appName)
        layerMenu = LayerContextMenu(store: store)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        sendWaitingSearch()
    }

    override func loadView() {
        configureOutlineView()
        let scrollView = makeScrollView()
        let status = viewModel.status

        let root = NSView()
        // Below the toolbar: the title bar's row has the window's buttons and the sidebar's
        // toggle, and takes the clicks there.
        root.addVStack(alignment: .fill, safeArea: .top) {
            makeFilterBar()
            makeStatusView()
            HierarchyListView(scrollView: scrollView, stickyView: stickyView)
                // Takes the room the bars leave, as the scroll view alone did.
                .contentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
                .contentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                .bind(\.isHidden, to: status.map { $0 != nil })
            makeCountBar()
        }
        view = root
        followStore()
    }

    private func configureOutlineView() {
        // A tree of rows driven by data: an outline view, as the app list is a table view.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layer"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        // The column is as wide as the rows shown need (see sizeColumnToRows), not as wide as
        // the list, and the outline view does not second-guess that.
        outlineView.columnAutoresizingStyle = .noColumnAutoresizing
        outlineView.autoresizesOutlineColumn = false
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowHeight = 24
        // With guides, less indentation still shows which row is inside which (C-HIER-12).
        outlineView.indentationPerLevel = 12
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.setAccessibilityIdentifier(Self.outlineIdentifier)
        outlineView.dataSource = self
        outlineView.delegate = self
        // Every click, also one on the row that is already selected, which changes nothing in
        // the selection and so is not reported as a change.
        outlineView.target = self
        // Filled when it opens, for the row that was clicked.
        outlineView.menu = NSMenu()
        outlineView.menu?.delegate = self
        outlineView.action = #selector(outlineViewWasClicked(_:))
        outlineView.doubleAction = #selector(outlineViewWasDoubleClicked(_:))
        configurePointer()
    }

    /// The outline view in a scroll view whose scrolling and resizing fit the column.
    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        // Scrolling changes the clip view's bounds; resizing, and the list's first layout
        // after it takes the place of the status text, change its frame. Both notifications
        // are posted on the main thread, where the view lives.
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: clip)
            .merge(with: NotificationCenter.default.publisher(
                for: NSView.frameDidChangeNotification, object: clip))
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.fitColumn()
                    self?.reportVisibleRows()
                    self?.updateSticky()
                    self?.outlineView.pointerMayHaveMoved()
                }
            }
            .store(in: &cancellables)
        return scrollView
    }

    /// The filter, the expand menu and, while focused, the path to the focused layer.
    private func makeFilterBar() -> NSView {
        VStack(alignment: .fill, spacing: Theme.Spacing.small) {
            HStack(alignment: .center, spacing: 6) {
                searchField
                    .placeholderString(localized("hierarchy.filter.placeholder"))
                    .accessibilityIdentifier(Self.searchIdentifier)
                    .bind(\.isEnabled, to: viewModel.isConnected)
                    .onReceive(store.$searchText) { [weak self] field, text in
                        // Only a text that differs: setting the same text while the user
                        // types would move the insertion point to the end.
                        guard field.stringValue != text else { return }
                        field.stringValue = text
                        // The store's text, set elsewhere, wins over typing still waiting;
                        // it is the store's already, so nothing goes back to it.
                        self?.waitingSearchText = nil
                        self?.searchEdits.send(SearchEdit(text: nil, isImmediate: true))
                    }
                    .onReceive(Self.delayedTyping(searchEdits)) { [weak self] _, text in
                        self?.waitingSearchText = nil
                        self?.store.setSearchText(text)
                    }
                    .sink(\.actionPublisher) { [weak self] in self?.searchWasEdited(returned: false) }
                    .sink(\.returnPublisher) { [weak self] in self?.searchWasEdited(returned: true) }
                expandButton
                    .toolTip(localized("hierarchy.expandMenu.tooltip"))
                    .accessibilityIdentifier(Self.expandIdentifier)
                    .bind(\.isEnabled, to: viewModel.expandEnabled)
                    .onReceive(store.$rowsRevision) { [weak store] button, _ in
                        Self.fillExpandMenu(
                            button, depth: store?.expandableDepth ?? 0)
                    }
                    .sink(\.indexOfSelectedItemPublisher) { [weak self] index in
                        self?.expandMenuItemWasChosen(at: index)
                    }
            }
            HStack(alignment: .center, spacing: 4) {
                pathControl
                    .controlSize(.small)
                    // The path takes the room the button leaves and is cut short in it:
                    // the button stays at the row's trailing edge whatever the path.
                    .contentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                    .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                    .accessibilityIdentifier(Self.pathIdentifier)
                    .bind(\.isEnabled, to: viewModel.isConnected)
                    .onReceive(store.$rowsRevision) { [weak store] path, _ in
                        path.pathItems = store.map(Self.pathItems) ?? []
                    }
                    .sink(\.actionPublisher) { [weak self] in self?.pathWasClicked() }
                NSButton().configure { $0.isBordered = false }
                    .image(Theme.symbol(
                        Theme.Symbol.leaveFocus, size: 12,
                        description: localized("hierarchy.showAllLayers")))
                    .contentTintColor(.secondaryLabelColor)
                    .toolTip(localized("hierarchy.showAllLayers"))
                    .accessibilityIdentifier(Self.leaveFocusIdentifier)
                    .bind(\.isEnabled, to: viewModel.isConnected)
                    .sink(\.clickPublisher) { [weak store] in store?.focus(on: nil) }
            }
            .bind(\.isHidden, to: store.$focusedLayerID.map { $0 == nil })
        }
        .padding(horizontal: 10, vertical: 8)
        .bind(\.isHidden, to: viewModel.loadStatus.map { $0 != nil })
    }

    /// Loading, a failure or no rows, in place of the list.
    private func makeStatusView() -> NSView {
        let status = viewModel.status
        let statusSymbol = viewModel.statusSymbolName
            .map { name -> NSImage? in
                name.flatMap { Theme.symbol($0, size: 26, weight: .light) }
            }
        return VStack(alignment: .center, spacing: Theme.Spacing.small) {
            Spacer()
            NSProgressIndicator()
                .configure {
                    $0.style = .spinning
                    $0.controlSize = .small
                    $0.isIndeterminate = true
                }
                .onReceive(viewModel.isLoading) { spinner, loading in
                    spinner.isHidden = !loading
                    if loading {
                        spinner.startAnimation(nil)
                    } else {
                        spinner.stopAnimation(nil)
                    }
                }
            NSImageView()
                .contentTintColor(.tertiaryLabelColor)
                .bind(\.image, to: statusSymbol)
                .bind(\.isHidden, to: statusSymbol.map { $0 == nil })
            NSTextField(wrappingLabelWithString: "")
                .textColor(.secondaryLabelColor)
                .alignment(.center)
                .accessibilityIdentifier(Self.statusIdentifier)
                .bind(\.stringValue, to: status.map { $0 ?? "" })
            Spacer()
        }
        .padding(16)
        .bind(\.isHidden, to: status.map { $0 == nil })
    }

    /// The number of layers below the list.
    private func makeCountBar() -> NSView {
        VStack(alignment: .fill, spacing: 0) {
            NSBox().configure { $0.boxType = .separator }
            HStack(alignment: .center, spacing: 0) {
                NSTextField(labelWithString: "")
                    .font(Theme.Font.caption)
                    .textColor(.secondaryLabelColor)
                    .lineBreakMode(.byTruncatingTail)
                    .accessibilityIdentifier(Self.countIdentifier)
                    .bind(\.stringValue, to: viewModel.count)
                Spacer()
            }
            .padding(horizontal: 14, vertical: 6)
        }
        .bind(\.isHidden, to: viewModel.loadStatus.map { $0 != nil })
    }

    /// The rows, the selection and the expansion follow the store.
    private func followStore() {
        // The rows: the tree, the search and the focus are all in place when this publishes.
        store.$rowsRevision
            .sink { [weak self] _ in self?.showRows() }
            .store(in: &cancellables)
        store.$selectedLayerID
            .removeDuplicates()
            .sink { [weak self] id in
                self?.shownSelection = id
                self?.showSelection(id, scroll: true)
                self?.followSideways(id)
                self?.decorateRows()
            }
            .store(in: &cancellables)
        // The hover, from the list or the preview (C-HIER-15).
        store.$hoveredLayerID
            .removeDuplicates()
            .sink { [weak self] id in
                self?.shownHover = id
                self?.decorateRows()
            }
            .store(in: &cancellables)
        // Expansion the store makes on its own: expanding to a level, revealing a row,
        // focusing (C-HIER-06). The outline follows it without reloading.
        store.$expansionRevision
            .dropFirst()
            .sink { [weak self] _ in self?.followExpansion() }
            .store(in: &cancellables)
        // The connection is gone: nothing on the list can be changed any more (C-WIN-03).
        store.$connection
            .sink { [weak self] connection in
                if connection.isLost { self?.outlineView.isEnabled = false }
            }
            .store(in: &cancellables)
    }

    private func followExpansion() {
        // A change the outline made itself is in place already; a search shows every row
        // expanded whatever the store holds.
        guard !isWritingExpansion, filter == nil else { return }
        followedExpansions += 1
        defer { sizeColumnToRows() }
        showingStore {
            applyExpansion(below: roots)
        }
        showSelection(store.selectedLayerID, scroll: false)
        reportVisibleRows()
    }

    /// The expand menu's items for a part of the tree whose deepest layer is `depth` deep. A
    /// pull-down button shows its first item as its face. Each item holds the depth it
    /// expands to.
    private static func fillExpandMenu(_ button: NSPopUpButton, depth: Int) {
        button.removeAllItems()
        button.addItem(withTitle: "")
        button.item(at: 0)?.image = Theme.symbol(
            Theme.Symbol.expandMenu, size: 13, description: localized("hierarchy.expandMenu.tooltip"))
        guard let menu = button.menu else { return }
        func add(_ title: String, _ toDepth: Int) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = toDepth
            menu.addItem(item)
        }
        add(localized("hierarchy.expandMenu.collapseAll"), 0)
        if depth > 0 {
            menu.addItem(.separator())
            for level in 1...depth { add(localized("hierarchy.expandMenu.expandToLevel", level), level) }
        }
        menu.addItem(.separator())
        add(localized("hierarchy.expandMenu.expandAll"), .max)
    }

    /// The steps from the window's root layer down to the focus, each with its title and
    /// icon.
    private static func pathItems(_ store: InspectionStore) -> [NSPathControlItem] {
        HierarchyViewModel.pathSteps(store).map { step in
            let item = NSPathControlItem()
            item.title = step.title
            item.image = LayerIconImage.image(step.icon, side: 14)
            return item
        }
    }

    private func pathWasClicked() {
        guard let clicked = pathControl.clickedPathItem,
              let index = pathControl.pathItems.firstIndex(of: clicked)
        else { return }
        pathStepWasClicked(at: index)
    }

    /// A step of the path: the focus moves to that layer (C-HIER-05).
    func pathStepWasClicked(at index: Int) {
        guard let focus else { return }
        let path = tree.path(to: focus)
        guard path.indices.contains(index) else { return }
        store.focus(on: path[index])
    }

    private func expandMenuItemWasChosen(at index: Int) {
        guard let depth = expandButton.item(at: index)?.representedObject as? Int else { return }
        store.expand(toDepth: depth)
    }

    /// Typing waits for a pause; clearing the field and Return go at once (C-HIER-04).
    private func searchWasEdited(returned: Bool) {
        let text = searchField.stringValue
        let isImmediate = returned || text.isEmpty
        waitingSearchText = isImmediate ? nil : text
        searchEdits.send(SearchEdit(text: text, isImmediate: isImmediate))
    }

    /// Typing still waiting when the list goes away reaches the store now, as it did before
    /// typing waited: the inspection's settings carry it over (C-WIN-04).
    private func sendWaitingSearch() {
        guard let text = waitingSearchText else { return }
        waitingSearchText = nil
        searchEdits.send(SearchEdit(text: nil, isImmediate: true))
        store.setSearchText(text)
    }

    /// The texts of the edits, each as soon as no newer edit replaced it: typed ones after
    /// `searchDelay`, the others at once. Delivered on the main queue, as the field's are.
    private static func delayedTyping(
        _ edits: some Publisher<SearchEdit, Never>
    ) -> AnyPublisher<String, Never> {
        edits
            .map { edit -> AnyPublisher<String, Never> in
                guard let text = edit.text.map(Just.init) else {
                    return Empty().eraseToAnyPublisher()
                }
                if edit.isImmediate { return text.eraseToAnyPublisher() }
                return text.delay(for: .seconds(searchDelay), scheduler: DispatchQueue.main)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    @objc private func outlineViewWasClicked(_ sender: NSOutlineView) {
        rowWasClicked(sender.clickedRow)
    }

    /// A click on a row. A click on the selected layer's row asks again for its attributes when
    /// they could not be loaded (C-ATTR-01). The action comes after the selection has changed,
    /// so a click on another row lands here as a click on the selected row too; asking again
    /// does nothing for a request that has not failed.
    func rowWasClicked(_ row: Int) {
        guard row >= 0, let id = layerID(atRow: row), id == store.selectedLayerID else { return }
        store.retryAttributes()
    }

    @objc private func outlineViewWasDoubleClicked(_ sender: NSOutlineView) {
        rowWasDoubleClicked(sender.clickedRow)
    }

    /// A double click on a row with sublayers expands or collapses it, as its disclosure
    /// triangle does, and goes to the store the same way (C-HIER-10). The search's rows are
    /// expanded to show the matches, not as the store holds them: there it only selects.
    func rowWasDoubleClicked(_ row: Int) {
        guard filter == nil, row >= 0, let item = outlineView.item(atRow: row),
              outlineView.isExpandable(item)
        else { return }
        if outlineView.isItemExpanded(item) {
            outlineView.collapseItem(item)
        } else {
            outlineView.expandItem(item)
        }
    }

    /// Tells the store which rows are in view, top to bottom, when that changed: their
    /// screenshots are asked for first (C-DET-01).
    func reportVisibleRows() {
        let range = outlineView.rows(in: outlineView.visibleRect)
        let ids = (range.location..<(range.location + range.length)).compactMap(layerID(atRow:))
        guard ids != reportedVisible else { return }
        reportedVisible = ids
        store.setVisibleLayers(ids)
    }

    // MARK: - From the store to the outline

    func item(for id: UInt64) -> Item {
        if let item = items[id] { return item }
        let item = Item(id: id)
        items[id] = item
        return item
    }

    func writingExpansion(_ body: () -> Void) {
        isWritingExpansion = true
        body()
        isWritingExpansion = false
    }

    func showingStore(_ body: () -> Void) {
        let wasShowingStore = isShowingStore
        isShowingStore = true
        body()
        isShowingStore = wasShowingStore
    }

    /// Shows the store's rows: its tree, within its focus, left by its search, with the
    /// expansion and the selection the store holds. When the rows are those already shown,
    /// the outline is left as it is; otherwise it reloads, staying where it is scrolled to.
    /// Only a change of the selection scrolls to the selected row.
    private func showRows() {
        let tree = store.tree
        let filter = store.filter
        let focus = store.focusedLayerID
        // The cheap comparisons first: comparing the trees goes through every layer.
        let rowsChanged =
            filter != self.filter || focus != self.focus || !HierarchyOutlineSync.sameRows(self.tree, tree)
        self.tree = tree
        self.filter = filter
        self.focus = focus
        shownChildren = [:]
        let top = focus.map { [$0] } ?? tree.roots
        roots = filter.map { filter in top.filter(filter.shown.contains) } ?? top
        items = items.filter { tree.contains($0.key) }
        // A selection in view before the reload stays in view after it, wherever its row
        // went; one that was out of view leaves the scroll position alone.
        let selected = store.selectedLayerID
        let selectionWasInView = selected.map(isRowInView) ?? false
        if rowsChanged {
            // A reload keeps where the list is scrolled to.
            showingStore {
                // Hidden meanwhile, so that the outline view does not lay out the rows in
                // view for each change: that took most of the time with thousands of rows.
                // A hidden view gives up the keyboard focus; the list takes it back.
                let hadFocus = outlineView.window?.firstResponder === outlineView
                outlineView.isHidden = true
                outlineView.reloadData()
                applyExpansion()
                outlineView.isHidden = false
                if hadFocus { outlineView.window?.makeFirstResponder(outlineView) }
            }
            reloadCount += 1
        }
        // The column is as wide as the rows shown need.
        sizeColumnToRows()
        showSelection(selected, scroll: selectionWasInView && !(selected.map(isRowInView) ?? true))
        reportVisibleRows()
    }

    /// Whether the layer has a row that is at least partly in view.
    private func isRowInView(_ id: UInt64) -> Bool {
        guard let item = items[id] else { return false }
        let row = outlineView.row(forItem: item)
        return row >= 0 && outlineView.visibleRect.intersects(outlineView.rect(ofRow: row))
    }

    /// Expands and collapses the rows as the store holds them; with a search, every row is
    /// expanded, whatever the store holds (C-HIER-04).
    private func applyExpansion() {
        if filter != nil {
            outlineView.expandItem(nil, expandChildren: true)
        } else {
            applyExpansion(below: roots)
        }
    }

    /// Expands and collapses rows to match the store, top down: the outline view cannot
    /// expand a row before the row it is inside of is expanded. A row expanded in the store
    /// together with every row inside it is expanded with them in one call: the outline view
    /// inserts rows for each call, and row by row, thousands of them took seconds.
    func applyExpansion(below ids: [UInt64]) {
        let whole = HierarchyOutlineSync.wholeExpansions(below: ids, in: tree) { store.isExpanded($0) }
        var pending = Array(ids.reversed())
        while let id = pending.popLast() {
            let item = item(for: id)
            guard outlineView.isExpandable(item) else { continue }
            if whole.contains(id) {
                outlineView.expandItem(item, expandChildren: true)
            } else if store.isExpanded(id) {
                outlineView.expandItem(item)
                pending.append(contentsOf: tree.children(of: id).reversed())
            } else {
                // The rows inside are collapsed with it: the outline view would otherwise
                // remember them as expanded and open them again with it, whatever the store
                // holds by then.
                outlineView.collapseItem(item, collapseChildren: true)
            }
        }
    }

    /// Selects the row of a layer, or nothing; scrolls to it when asked.
    func showSelection(_ id: UInt64?, scroll: Bool) {
        showingStore {
            // A row index outlives a reload, the layer in that row may not: always set the
            // selection anew.
            let row = id.flatMap { tree.contains($0) ? outlineView.row(forItem: item(for: $0)) : nil }
            guard let row, row >= 0 else {
                outlineView.deselectAll(nil)
                return
            }
            if outlineView.selectedRow != row {
                outlineView.selectRowIndexes([row], byExtendingSelection: false)
            }
            if scroll { outlineView.scrollRowToVisible(row) }
        }
    }

    // MARK: - For tests

    /// How many times the outline was reloaded.
    private(set) var reloadCount = 0
    /// How many times the outline followed an expansion the store made.
    private(set) var followedExpansions = 0

    /// The layer a row shows. Internal for tests.
    func layerID(atRow row: Int) -> UInt64? {
        layerID(of: outlineView.item(atRow: row))
    }

    /// The layer of one of the outline view's items.
    func layerID(of item: Any?) -> UInt64? {
        (item as? Item)?.id
    }

    /// The row of a layer, or -1 when it has none.
    func row(of id: UInt64) -> Int {
        guard tree.contains(id) else { return -1 }
        return outlineView.row(forItem: item(for: id))
    }

    /// The view of one row, configured.
    func rowView(_ row: Int) -> HierarchyRowView? {
        guard let item = outlineView.item(atRow: row) else { return nil }
        return outlineView(outlineView, viewFor: outlineView.tableColumns.first, item: item)
            as? HierarchyRowView
    }
}
