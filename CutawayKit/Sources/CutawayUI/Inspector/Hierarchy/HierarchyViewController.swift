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
    // can reach it: `store`, `viewModel`, the column's sizing state, and the getters of
    // `tree` and `focus`. It belongs to HierarchyViewController alone. What is internal for
    // tests says so.

    static let outlineIdentifier = "hierarchy.outline"
    static let statusIdentifier = "hierarchy.status"
    static let countIdentifier = "hierarchy.count"
    static let searchIdentifier = "hierarchy.search"
    static let expandIdentifier = "hierarchy.expand"
    static let pathIdentifier = "hierarchy.path"
    static let leaveFocusIdentifier = "hierarchy.leaveFocus"

    private static let rowIdentifier = NSUserInterfaceItemIdentifier("HierarchyRow")

    /// What the outline view holds for a layer. It recognises a row after a reload by the
    /// identity of this object, so there is one per layer for as long as the layer exists.
    private final class Item: NSObject {
        let id: UInt64

        init(id: UInt64) {
            self.id = id
        }
    }

    // MARK: - Controls

    let outlineView = HierarchyOutlineView()
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
    /// What the outline shows, as the store last published it. Inside a subscription the
    /// store may already hold newer values.
    private(set) var tree = LayerTree.empty
    private var filter: HierarchyFilter?
    private(set) var focus: UInt64?
    /// The outline's top rows: the focused layer, or every window's root layer; with a
    /// search, only those it leaves.
    private var roots: [UInt64] = []
    private var items: [UInt64: Item] = [:]
    /// How wide each title is when shown in full. Class names repeat a lot.
    var titleWidths: [String: CGFloat] = [:]
    /// The column's width that every title of the tree needs.
    var titlesWidth: CGFloat = 0
    /// Set while a sizing of the column waits for the user's expansion to be over.
    var isColumnSizingPending = false
    /// True while the outline is being made to match the store. Its notifications are then
    /// not the user's doing.
    private var isShowingStore = false
    /// Set while the outline writes an expansion to the store, which publishes it back.
    private var isWritingExpansion = false
    /// The children a search leaves, by layer, as the outline view has asked for them since
    /// the rows were last shown.
    private var shownChildren: [UInt64: [UInt64]] = [:]
    /// Rows the outline view collapsed for good inside a row that is being collapsed with ⌥,
    /// waiting for that row's own notification, which comes last.
    private var collapsedInside: [UInt64] = []
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
            scrollView
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
        outlineView.indentationPerLevel = 14
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
            .sink { [weak self] id in self?.showSelection(id, scroll: true) }
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
    /// symbol.
    private static func pathItems(_ store: InspectionStore) -> [NSPathControlItem] {
        HierarchyViewModel.pathSteps(store).map { step in
            let item = NSPathControlItem()
            item.title = step.title
            item.image = Theme.squareSymbol(step.symbolName, size: 11, side: 16)
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
    private func reportVisibleRows() {
        let range = outlineView.rows(in: outlineView.visibleRect)
        let ids = (range.location..<(range.location + range.length)).compactMap(layerID(atRow:))
        guard ids != reportedVisible else { return }
        reportedVisible = ids
        store.setVisibleLayers(ids)
    }

    // MARK: - From the store to the outline

    private func item(for id: UInt64) -> Item {
        if let item = items[id] { return item }
        let item = Item(id: id)
        items[id] = item
        return item
    }

    private func writingExpansion(_ body: () -> Void) {
        isWritingExpansion = true
        body()
        isWritingExpansion = false
    }

    private func showingStore(_ body: () -> Void) {
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
    private func applyExpansion(below ids: [UInt64]) {
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
                outlineView.collapseItem(item)
            }
        }
    }

    /// Selects the row of a layer, or nothing; scrolls to it when asked.
    private func showSelection(_ id: UInt64?, scroll: Bool) {
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
        (outlineView.item(atRow: row) as? Item)?.id
    }

    /// The view of one row, configured.
    func rowView(_ row: Int) -> HierarchyRowView? {
        guard let item = outlineView.item(atRow: row) else { return nil }
        return outlineView(outlineView, viewFor: outlineView.tableColumns.first, item: item)
            as? HierarchyRowView
    }
}

extension HierarchyViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    private func children(of item: Any?) -> [UInt64] {
        guard let item = item as? Item else { return roots }
        let children = tree.children(of: item.id)
        guard let filter else { return children }
        // The outline view asks for each child by its index: filtering the children for each
        // would take a node's k children k times.
        if let shown = shownChildren[item.id] { return shown }
        let shown = children.filter(filter.shown.contains)
        shownChildren[item.id] = shown
        return shown
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        self.item(for: children(of: item)[index])
    }

    /// Typing a title's first letters selects its row.
    func outlineView(
        _ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any
    ) -> String? {
        (item as? Item).map { tree.displayTitle(of: $0.id) }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !children(of: item).isEmpty
    }

    func outlineView(
        _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
    ) -> NSView? {
        guard let item = item as? Item else { return nil }
        let view =
            outlineView.makeView(withIdentifier: Self.rowIdentifier, owner: nil)
                as? HierarchyRowView ?? HierarchyRowView()
        view.identifier = Self.rowIdentifier
        view.configure(HierarchyRow(tree, item.id, filter: filter))
        return view
    }

    // MARK: From the outline to the store

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isShowingStore else { return }
        // Rows appeared: the column follows them, with a search too.
        defer { sizeColumnSoon() }
        // With a search, expanding is the list's own business (C-HIER-04).
        guard filter == nil, let item = notification.userInfo?["NSObject"] as? Item
        else { return }
        writingExpansion { store.setExpanded(item.id, true) }
        // The rows that just appeared are as the outline view remembers them, or collapsed.
        // The store says how they should be.
        showingStore {
            applyExpansion(below: tree.children(of: item.id))
        }
        reportVisibleRows()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isShowingStore else { return }
        // Rows went away: the column follows them, with a search too.
        defer { sizeColumnSoon() }
        guard filter == nil, let item = notification.userInfo?["NSObject"] as? Item
        else { return }
        // Collapsing a row collapses every expanded row inside it first, each with its own
        // notification, and the row itself last. Without ⌥ the outline view expands them
        // again with that row, as they were, so the store keeps them expanded: their
        // expansion does not show while the row is collapsed. With ⌥ they stay collapsed and
        // go to the store together with the row. Either way the tree is laid out once, not
        // once for each.
        if let parent = outlineView.parent(forItem: item), !outlineView.isItemExpanded(parent) {
            if outlineView.isCollapsingChildren { collapsedInside.append(item.id) }
            return
        }
        let collapsed = collapsedInside + [item.id]
        collapsedInside.removeAll()
        writingExpansion { store.setExpanded(collapsed, false) }
        // The outline view has dropped a selection that was inside the collapsed row. The
        // store moved it onto the row; show that.
        showSelection(store.selectedLayerID, scroll: true)
        reportVisibleRows()
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isShowingStore else { return }
        // The outline view's selection now, not at the time the notification was posted: it
        // arrives after a collapse has already been dealt with.
        let id = layerID(atRow: outlineView.selectedRow)
        // Collapsing a row of the search drops a selection inside it from the outline. The
        // search's rows are the list's own business: the store keeps its selection.
        if id == nil, filter != nil, let selected = store.selectedLayerID,
           tree.contains(selected), outlineView.row(forItem: item(for: selected)) < 0
        {
            return
        }
        // A row of the search may be inside nodes the store holds collapsed: they are
        // expanded, so that the row clicked is the one selected (C-HIER-04).
        if let id, filter != nil {
            store.reveal(id)
        } else {
            store.select(id)
        }
    }
}

/// The hierarchy's outline view. Tells whether the collapse under way collapses every row
/// inside too, as ⌥ does, which its notifications do not tell.
final class HierarchyOutlineView: NSOutlineView {
    private(set) var isCollapsingChildren = false

    override func collapseItem(_ item: Any?, collapseChildren: Bool) {
        let wasCollapsingChildren = isCollapsingChildren
        isCollapsingChildren = collapseChildren
        super.collapseItem(item, collapseChildren: collapseChildren)
        isCollapsingChildren = wasCollapsingChildren
    }
}
