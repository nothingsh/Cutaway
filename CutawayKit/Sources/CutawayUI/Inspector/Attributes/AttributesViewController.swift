import AppKit
import Combine
import CutawayModel
import CutawayProjects
import CutawayWire
import DeclarativeAppKit
import DeclarativeCombine

/// The attributes of the selected layer (C-ATTR-01 to C-ATTR-03, C-ATTR-10): a header naming
/// the layer, what holds it and its size (C-ATTR-18), a filter, and one list in five sections
/// by what the attributes are for: the class's own content, titled by its most specific group,
/// then Appearance, Layout, Behavior, and Object, which says what the object is, its addresses
/// and its owner (C-ATTR-11, C-HIER-07) and starts folded. The sections follow the attributes'
/// `section` alone; nothing here knows any particular group or attribute (P-ATTR-03). A section
/// folds away from its header, and every section with Option held; the header of the section
/// at the top of the list stays there while it scrolls (C-ATTR-15). The filter keeps the rows
/// whose titles or IDs hold it (C-ATTR-14). When there are no attributes to list, a symbol and
/// a line of text say why.
///
/// Attributes the app marks as editable get an editor while the server can change them, the
/// app is active and the connection holds (C-ATTR-04). New values for the same attributes are
/// shown in place, so that a field being typed in keeps its focus and a drag goes on
/// (C-ATTR-06); rows that are being changed show it, and failures are said in the row.
///
/// For a layer that backs a view, the constraints end the Layout section when the server gives
/// them (C-LAYOUT-02). They are rebuilt on their own, leaving the attribute rows as they are.
final class AttributesViewController: NSViewController {
    static let listIdentifier = "attributes.list"
    static let messageIdentifier = "attributes.message"
    static let detailIdentifier = "attributes.detail"
    static let retryIdentifier = "attributes.retry"
    static let headerIdentifier = "attributes.header"
    static let headerTitleIdentifier = "attributes.header.title"
    static let headerSubtitleIdentifier = "attributes.header.subtitle"
    static let filterIdentifier = "attributes.filter"
    static let filterCountIdentifier = "attributes.filter.count"
    static let noMatchIdentifier = "attributes.filter.none"
    static let stickyIdentifier = "attributes.sticky"

    let viewModel: AttributesViewModel
    /// What the panel asks of the inspection.
    let actions: AttributesPanelActions
    /// How long a request may take before the panel says it is loading: most answers come
    /// sooner, and a spinner for every click would flicker.
    private let loadingDelay: TimeInterval
    /// The groups as they came.
    private(set) var groups: [AttributeGroup] = []
    /// The sections as listed, in the order of the list.
    private(set) var sectionViews: [AttributeGroupView] = []
    /// The sections folded away, by kind, kept while the panel lives; Object starts folded
    /// (C-ATTR-10, C-ATTR-15).
    private(set) var collapsed: Set<String> = [AttributesViewModel.Listing.Kind.object.rawValue]
    /// The top of the Object section.
    private(set) var identityView: IdentityLinesView
    /// The constraints shown, or nil when the Layout section has none.
    private(set) var constraintRows: [ConstraintRow]?
    private(set) var constraintsView: ConstraintsSectionView?
    /// Whether UIKit's constraints are listed; kept while the panel lives, as the folding is.
    private var showsGeneratedConstraints = false
    /// What is listed now.
    private var shownListing = AttributesViewModel.Listing(sections: [])
    /// How many addresses the selected layer has, for the Object section's summary.
    private var addressCount = 0
    /// The shape of what is listed: rebuilt when it changes, updated in place when not.
    private var shownShape: AttributesViewModel.Shape?
    /// The rows shown, by what they show: what is updated in place (C-ATTR-06).
    private var shownRows = ShownAttributeRows()
    /// Each attribute's own row with the attribute it shows, in the order of the list.
    var attributeRows: [(attribute: Attribute, row: AttributeRowView)] { shownRows.rows }
    /// What shows each attribute, its own row or a part of a compound row (C-ATTR-19), in
    /// the order of `Listing.attributes`.
    var attributeCells: [(attribute: Attribute, cell: any AttributeCell)] { shownRows.cells }
    /// The compound rows, in the order of the list.
    var compoundRows: [CompoundRowView] { shownRows.compounds }

    private let message = CurrentValueSubject<AttributesViewModel.Message?, Never>(nil)
    /// True while a request runs and nothing is shown yet, below the header.
    private let isWaiting = CurrentValueSubject<Bool, Never>(false)
    /// What the header says about the selected layer, as last summarized.
    private let selectedLayer = CurrentValueSubject<LayerSummary?, Never>(nil)
    /// The layer whose attributes are listed, and the one selected now.
    private var listedLayerID: UInt64?
    private var selectedLayerID: UInt64?
    private var pendingLoading: DispatchWorkItem?
    let list = VScroll(alignment: .fill, spacing: 0) {}
    /// The sections, each after a line that shows when a section above it does.
    private let sections = VStack(alignment: .fill, spacing: 0) {}
    private var separators: [(line: NSView, section: NSView)] = []

    /// The filter, the header that stays at the top of the list and the pointer while the
    /// list scrolls (C-ATTR-14, C-ATTR-15).
    private lazy var chrome = AttributesListChrome(
        list: list, sections: { [weak self] in self?.allSections ?? [] },
        filterDidChange: { [weak self] in
            self?.applyFilter()
            self?.scrollToTop()
        },
        pausePointer: { [weak self] in
            self?.constraintsView?.pauseForScrolling()
            for (_, row) in self?.attributeRows ?? [] { row.references?.point(at: nil) }
        },
        resumePointer: { [weak self] in self?.constraintsView?.pointerMayHaveMoved() })

    /// The pages of a layer with very many attributes (C-SCALE-03).
    private lazy var pages = AttributePageArranger(
        list: list, parts: { [weak self] in self?.lazyParts ?? [] },
        isPinned: { [weak self] row in self?.isPinned(row) ?? false },
        rowsDidChange: { [weak self] in
            self?.listBuiltRows()
            self?.showRowStates()
        },
        didArrangeLater: { [weak self] in self?.chrome.updateSticky() },
        layout: { [weak self] in self?.view.layoutSubtreeIfNeeded() })

    /// The filter's field. For tests.
    var filterField: NSSearchField { chrome.filterField }
    /// How many attributes the filter keeps of how many, or nil without a filter. For tests.
    var filterCounts: (shown: Int, total: Int)? { chrome.filterCounts }

    /// The selected layer's ancestors, under its name (C-ATTR-16).
    private(set) lazy var ancestorsBar: AncestorsBar = .init().configure {
        $0.onHover = { [weak self] id in self?.actions.hoverLayer(id) }
        $0.onSelect = { [weak self] id in self?.actions.showLayer(id) }
    }

    private var cancellables = Set<AnyCancellable>()
    private let projectIndex: AnyPublisher<ProjectIndex?, Never>

    init(
        store: AttributesStore, appName: String, inputs: AttributesPanelInputs = .init(),
        actions: AttributesPanelActions = .init(), loadingDelay: TimeInterval = 0.2
    ) {
        viewModel = AttributesViewModel(
            store: store, appName: appName, layer: inputs.layer, tree: inputs.tree, connection: inputs.connection)
        self.actions = actions
        self.loadingDelay = loadingDelay
        projectIndex = inputs.projectIndex
        identityView = IdentityLinesView(copy: actions.copy, openInXcode: actions.openInXcode)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        list.setAccessibilityIdentifier(Self.listIdentifier)
        list.autohidesScrollers = true
        list.stack.padding(top: 0, leading: 0, bottom: Theme.Spacing.medium, trailing: 0)
        list.stack.addArrangedSubview(sections)
        list.stack.addArrangedSubview(chrome.makeFilterResults())

        // One summary for each change, shared by all that follow it: it walks the tree and looks
        // the classes up in the project's index. Each that subscribes later gets the current one.
        viewModel.layer
            .sink { [weak self] summary in self?.selectedLayer.send(summary) }
            .store(in: &cancellables)
        let layer = selectedLayer.eraseToAnyPublisher()
        let header = makeHeader(layer: layer)
        let emptyState = makeEmptyState()

        // Takes the room below the header while nothing else is shown, so that the header
        // stays at the top.
        let filler = NSView()
            .contentHuggingPriority(.defaultLow, for: .vertical)
            .bind(\.isHidden, to: isWaiting.map { !$0 })

        // The panel draws its own backdrop, the one the header that stays at the top has too.
        let root = Self.backdrop()
        root.addVStack(alignment: .fill) {
            header
            list
            emptyState
            filler
        }
        view = root
        header.setContentHuggingPriority(.required, for: .vertical)
        chrome.installStickyBar(in: root)
        rebuild(AttributesViewModel.listing(of: []))
        follow(layer: layer)
    }

    /// The selected layer's icon and title, what holds it, and the filter.
    private func makeHeader(layer: AnyPublisher<LayerSummary?, Never>) -> NSView {
        VStack(alignment: .fill, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                NSImageView()
                    .imageScaling(.scaleNone)
                    .bind(\.image, to: layer.map { $0.map { LayerIconImage.image($0.icon, side: 24) } })
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    NSTextField(labelWithString: "")
                        .font(Theme.Font.bodyEmphasized)
                        .lineBreakMode(.byTruncatingTail)
                        .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                        .accessibilityIdentifier(Self.headerTitleIdentifier)
                        .bind(\.stringValue, to: layer.map { $0?.title ?? "" })
                    // What holds the layer (C-HIER-07) and its size (C-ATTR-18). Cut short in
                    // the middle, so that the size at the end stays in view.
                    NSTextField(labelWithString: "")
                        .font(Theme.Font.caption)
                        .textColor(.secondaryLabelColor)
                        .lineBreakMode(.byTruncatingMiddle)
                        .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                        .accessibilityIdentifier(Self.headerSubtitleIdentifier)
                        .bind(\.stringValue, to: layer.map { $0?.headerLine ?? "" })
                        .bind(\.isHidden, to: layer.map { $0?.headerLine == nil })
                }
                // The texts take the rest of the row, so that one that fits is shown whole:
                // they give way to the panes' widths (`Theme.textGivesWay`), and beside a
                // spacer the stack squeezed them instead.
                .contentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            }
            // Clear of the toolbar's inspector button, which floats over the top right corner.
            .padding(top: Theme.Spacing.medium, leading: Theme.Spacing.large,
                     bottom: Theme.Spacing.small, trailing: 44)
            // The icons of the ancestors line up with the selected layer's.
            VStack(alignment: .fill) {
                ancestorsBar
                    .bind(\.isEnabled, to: viewModel.isConnected)
            }
            .padding(top: 0, leading: Theme.Spacing.large - 5, bottom: Theme.Spacing.small,
                     trailing: Theme.Spacing.medium)
            .bind(\.isHidden, to: layer.map { $0?.ancestors.isEmpty ?? true })
            VStack(alignment: .fill) {
                chrome.makeFilterBox()
            }
            .padding(top: 0, leading: Theme.Spacing.medium, bottom: Theme.Spacing.small,
                     trailing: Theme.Spacing.medium)
            NSBox().configure { $0.boxType = .separator }
        }
        .accessibilityIdentifier(Self.headerIdentifier)
        .bind(\.isHidden, to: layer.map { $0 == nil })
    }

    /// The message in place of the list: loading, nothing selected, a failure.
    private func makeEmptyState() -> NSView {
        let spinner = NSProgressIndicator()
            .configure {
                $0.style = .spinning
                $0.controlSize = .small
                $0.isIndeterminate = true
            }
            .onReceive(message.map { $0?.showsSpinner ?? false }.removeDuplicates()) {
                spinner, spins in
                spinner.isHidden = !spins
                if spins {
                    spinner.startAnimation(nil)
                } else {
                    spinner.stopAnimation(nil)
                }
            }
        return VStack(alignment: .center, spacing: 6) {
            Spacer()
            spinner
            NSImageView()
                .contentTintColor(.tertiaryLabelColor)
                .bind(\.image, to: message.map {
                    $0?.symbol.flatMap { Theme.symbol($0, size: 28, weight: .light) }
                })
                .bind(\.isHidden, to: message.map { $0?.symbol == nil })
            NSTextField(wrappingLabelWithString: "")
                .font(Theme.Font.bodyEmphasized)
                .alignment(.center)
                .isSelectable(false)
                .accessibilityIdentifier(Self.messageIdentifier)
                .bind(\.stringValue, to: message.map { $0?.title ?? "" })
            NSTextField(wrappingLabelWithString: "")
                .font(Theme.Font.caption)
                .textColor(.secondaryLabelColor)
                .alignment(.center)
                .isSelectable(false)
                .accessibilityIdentifier(Self.detailIdentifier)
                .bind(\.stringValue, to: message.map { $0?.detail ?? "" })
                .bind(\.isHidden, to: message.map { $0?.detail == nil })
            NSButton()
                .title(localized("attributes.retry"))
                .bezelStyle(.rounded)
                .controlSize(.small)
                .accessibilityIdentifier(Self.retryIdentifier)
                .bind(\.isHidden, to: message.map { !($0?.offersRetry ?? false) })
                .sink(\.clickPublisher) { [weak self] in self?.actions.retry() }
            Spacer()
        }
        .padding(24)
        .bind(\.isHidden, to: message.map { $0 == nil })
    }

    /// The panel follows the selected layer, the tree and the store's state.
    private func follow(layer: AnyPublisher<LayerSummary?, Never>) {
        layer
            .sink { [weak self] summary in
                self?.selectedLayerID = summary?.id
                self?.addressCount = [summary?.viewAddress, summary?.layerAddress, summary?.controllerAddress]
                    .compactMap { $0 }.count
                self?.ancestorsBar.show(summary?.ancestors ?? [])
                self?.identityView.show(summary)
                self?.showLayerSize(summary?.size)
                self?.showObjectSummary()
                self?.applyFilter()
            }
            .store(in: &cancellables)
        // The tree there is now, for the first list; its changes are followed below.
        viewModel.firstTree
            .sink { [weak self] tree in self?.viewModel.tree = tree }
            .store(in: &cancellables)

        // Whether the store can edit and the changes: either builds the rows' editors again.
        viewModel.editing
            .sink { [weak self] _ in
                guard let self else { return }
                self.showGroups(self.groups, force: true)
            }
            .store(in: &cancellables)

        viewModel.state
            .sink { [weak self] state in self?.show(state) }
            .store(in: &cancellables)

        // The names of the constraints' ends follow the tree. After the state: the first list
        // is built once, knowing whether it can edit.
        viewModel.treeChanges
            .sink { [weak self] tree in
                guard let self else { return }
                self.viewModel.tree = tree
                if case .loading = self.viewModel.store.state { return }
                self.present(self.viewModel.store.state)
            }
            .store(in: &cancellables)

        list.documentVisibleRectPublisher
            .sink { [weak self] _ in
                self?.pages.arrangeSoon()
                self?.chrome.updateSticky()
                self?.chrome.pauseThePointerWhileScrolling()
            }
            .store(in: &cancellables)

        // The names of colours and texts follow the project folder's index (C-SRC-04,
        // C-SRC-05): rows change in place once it is built. Each index that comes is a new
        // one; comparing two would hold the main thread (C-SRC-02).
        projectIndex
            .sink { [weak self] index in
                guard let self else { return }
                self.viewModel.projectIndex = index
                self.showRowStates()
            }
            .store(in: &cancellables)
    }

    // MARK: - Changing attributes

    /// The selected layer's size, for insets boxes (C-ATTR-22).
    private var layerSize: String?

    private func showLayerSize(_ size: String?) {
        guard size != layerSize else { return }
        layerSize = size
        for (_, cell) in attributeCells { cell.show(layerSize: size) }
    }

    /// Each row's value and state: a row being changed shows the value on its way.
    func showRowStates() {
        let layer = groups.flatMap(\.attributes)
        for (attribute, row) in attributeCells {
            let state = viewModel.rowState(of: attribute, among: layer)
            row.show(state.value, names: state.names)
            row.show(sending: state.isSending, failure: state.failureText)
            row.showInactive(state.inactiveReason)
            row.show(layerSize: layerSize)
        }
    }

    // MARK: - What is shown

    /// Shows what the store published. The list is rebuilt only when the groups change, and
    /// then from the top.
    private func show(_ state: AttributesStore.State) {
        pendingLoading?.cancel()
        pendingLoading = nil
        if case .loading = state, loadingDelay > 0 {
            // Nothing for a moment: the answer usually comes first.
            showGroups([])
            showConstraints(nil)
            message.send(nil)
            let work = DispatchWorkItem { [weak self] in
                guard let self, case .loading = self.viewModel.store.state else { return }
                self.message.send(AttributesViewModel.message(
                    for: .loading, appName: self.viewModel.appName))
            }
            pendingLoading = work
            DispatchQueue.main.asyncAfter(deadline: .now() + loadingDelay, execute: work)
            list.isHidden = true
            isWaiting.send(true)
            chrome.updateSticky()
            return
        }
        isWaiting.send(false)
        present(state)
    }

    /// Shows a state other than loading: the groups and the constraints, or a message.
    private func present(_ state: AttributesStore.State) {
        let rows = viewModel.constraintRows(for: state)
        let shown = AttributesViewModel.message(for: state, appName: viewModel.appName)
        if case .loaded(let groups, _) = state, shown == nil {
            showGroups(groups)
            showConstraints(rows)
        } else {
            showGroups([])
            showConstraints(nil)
        }
        message.send(shown)
        list.isHidden = shown != nil
        // The pages near the top, now that the list shows (C-SCALE-03).
        if !lazyParts.isEmpty { view.layoutSubtreeIfNeeded() }
        pages.arrange()
        chrome.updateSticky()
    }

    /// Shows the constraints, or none, at the end of the Layout section. Built again only when
    /// what they say changes; the sections are built again only when the Layout section comes
    /// or goes with them.
    private func showConstraints(_ rows: [ConstraintRow]?) {
        guard rows != constraintRows else { return }
        let hadLayout = layoutSection != nil
        constraintRows = rows
        constraintsView = rows.map { rows in
            let view = ConstraintsSectionView(
                rows: rows, showsGenerated: showsGeneratedConstraints, onShowLayer: actions.showLayer,
                onHoverEnd: actions.hoverConstraintEnd, onPoint: actions.pointConstraints)
            view.onToggleGenerated = { [weak self] in self?.showsGeneratedConstraints = $0 }
            return view
        }
        if hasLayoutSection(shownListing) != hadLayout {
            rebuild(shownListing)
            showRowStates()
        } else {
            layoutSection?.setConstraints(constraintsView)
            applyFilter()
        }
        if rows != nil { scrollToTopForAnotherLayer() }
    }

    /// Another layer's attributes start at the top; a new answer for the same layer stays
    /// where the user scrolled to.
    private func scrollToTopForAnotherLayer() {
        guard selectedLayerID != listedLayerID else { return }
        listedLayerID = selectedLayerID
        scrollToTop()
    }

    func scrollToTop() {
        list.contentView.scroll(to: .zero)
        list.reflectScrolledClipView(list.contentView)
    }

    private func showGroups(_ new: [AttributeGroup], force: Bool = false) {
        let newShape = viewModel.shape(of: new)
        let listing = AttributesViewModel.listing(of: new)
        if !new.isEmpty, newShape == shownShape {
            // The same attributes of the same layer: new values in place (C-ATTR-06). The same
            // shape lists them the same way, so the rows follow in the same order.
            groups = new
            shownListing = listing
            if !lazyParts.isEmpty {
                replaceValues(listing)
                showRowStates()
                showObjectSummary()
                return
            }
            shownRows.show(listing.attributes)
            showRowStates()
            showObjectSummary()
            return
        }
        guard new != groups || force || newShape != shownShape else { return }
        groups = new
        shownShape = new.isEmpty ? nil : newShape
        rebuild(listing)
        showRowStates()
        if !new.isEmpty { scrollToTopForAnotherLayer() }
    }

    /// Builds the sections again, their rows in the order of `listing.attributes`. The Layout
    /// section is there for its attributes or the constraints, the Object section always.
    private func rebuild(_ listing: AttributesViewModel.Listing) {
        shownListing = listing
        var built: [(item: AttributeClusters.Item, row: any AttributeListRow)] = []
        let byPage = AttributePageArranger.isBuiltByPage(listing)
        sectionViews = AttributesViewModel.Listing.Kind.allCases.compactMap { kind in
            let section = listing.section(kind)
            switch kind {
            case .layout: guard hasLayoutSection(listing) else { return nil }
            case .object: break
            case .content, .app, .appearance, .behavior, .accessibility:
                guard section != nil else { return nil }
            }
            let parts = (section?.parts ?? []).enumerated().map { index, part in
                // The Content section is titled by its first group; in App every group has
                // its title over it (C-ATTR-23). The others' groups go without headings, as
                // the section is about what they are for.
                let heading = kind == .app || (kind == .content && index > 0)
                    ? AttributeText.title(part.groupTitle, id: part.groupID) : nil
                // Very many: page by page as the list comes near them (C-SCALE-03).
                if byPage { return pagedPart(part.listed, heading: heading) }
                let rows = part.listed.map(makeListRow)
                built += zip(part.listed, rows).map { (item: $0, row: $1) }
                return AttributeGroupView.Part(heading: heading, rows: rows)
            }
            return sectionView(kind, first: section?.parts.first, parts: parts)
        }
        // The pages built page by page have no rows yet.
        shownRows = ShownAttributeRows(built)
        layoutSection?.setConstraints(constraintsView)
        showObjectSummary()
        arrange()
    }

    private func sectionView(
        _ kind: AttributesViewModel.Listing.Kind, first: AttributesViewModel.Listing.Part?,
        parts: [AttributeGroupView.Part]
    ) -> AttributeGroupView {
        let title: String
        let icon: SectionHeader.Icon?
        if kind == .content, let first {
            title = AttributeText.title(first.groupTitle, id: first.groupID)
            // The class the server names, or a guess from the group's name (C-ATTR-17).
            icon = .layer(first.groupClassName.map { LayerIcon(groupClass: $0) }
                ?? LayerIcon(group: first.groupTitle, id: first.groupID))
        } else {
            title = Self.title(of: kind)
            icon = Self.symbol(of: kind).map { .symbol($0) }
        }
        let key = kind.rawValue
        let view = AttributeGroupView(
            title: title, icon: icon, parts: parts, lines: kind == .object ? identityView : nil,
            isCollapsed: collapsed.contains(key))
        view.foldKey = key
        view.onToggle = { [weak self] isCollapsed in self?.fold(key, isCollapsed) }
        view.onToggleAll = { [weak self] isCollapsed in self?.foldAll(isCollapsed) }
        return view
    }

    /// Whether the Layout section is listed: for its attributes or the constraints.
    private func hasLayoutSection(_ listing: AttributesViewModel.Listing) -> Bool {
        listing.section(.layout) != nil || constraintRows != nil
    }

    func section(_ kind: AttributesViewModel.Listing.Kind) -> AttributeGroupView? {
        sectionViews.first { $0.foldKey == kind.rawValue }
    }

    private var layoutSection: AttributeGroupView? { section(.layout) }
    var objectSection: AttributeGroupView? { section(.object) }

    /// What the folded Object section says (C-ATTR-10): each Identity attribute's title and
    /// value, then how many addresses there are.
    private func showObjectSummary() {
        let attributes = shownListing.section(.object)?.attributes ?? []
        var items = attributes.map { attribute in
            AttributeText.title(attribute.title, id: attribute.id) + " "
                + AttributeText.text(of: attribute.value)
        }
        if addressCount > 0 { items.append(localized("attributes.object.addresses", addressCount)) }
        objectSection?.summary = items.joined(separator: " · ")
    }

    /// Every section in the order of the list.
    private var allSections: [any FoldingSection] { sectionViews }

    /// Puts the sections into the list, each after a line of its own. The lines are made
    /// again each time: one kept and shown again narrowed the inspector to its least width.
    private func arrange() {
        for view in sections.arrangedSubviews {
            sections.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        separators = allSections.map { section in
            let line = Self.separator()
            sections.addArrangedSubview(line)
            sections.addArrangedSubview(section)
            return (line, section)
        }
        applyFilter()
    }

    // MARK: - Folding (C-ATTR-15)

    private func fold(_ key: String, _ isCollapsed: Bool) {
        if isCollapsed { collapsed.insert(key) } else { collapsed.remove(key) }
        updateStickyAfterLayout()
    }

    /// Folds or unfolds every section, as Option and a click on any header do.
    private func foldAll(_ isCollapsed: Bool) {
        for section in sectionViews {
            section.setCollapsed(isCollapsed)
            if isCollapsed { collapsed.insert(section.foldKey) } else { collapsed.remove(section.foldKey) }
        }
        updateStickyAfterLayout()
    }

    // MARK: - Filtering (C-ATTR-14)

    /// Keeps the rows whose titles or IDs hold `text`, from the top of the list.
    func setFilter(_ text: String) {
        chrome.setFilter(text)
    }

    /// Shows the sections, rows and lines the filter keeps.
    private func applyFilter() {
        guard isViewLoaded else { return }
        chrome.apply(to: sectionViews, separators: separators)
        // The pages the filter made again have no rows yet (C-SCALE-03).
        if !lazyParts.isEmpty { listBuiltRows() }
        updateStickyAfterLayout()
    }

    private func updateStickyAfterLayout() {
        guard isViewLoaded else { return }
        view.layoutSubtreeIfNeeded()
        pages.arrange()
        chrome.updateSticky()
    }

    // MARK: - Pages (C-SCALE-03)

    /// Builds the pages near what the list shows. For tests.
    func arrangePages() {
        pages.arrange()
    }

    /// The rows the panel keeps, from the pages built now.
    private func listBuiltRows() {
        shownRows = ShownAttributeRows(lazyParts.flatMap(\.built))
    }

    /// New values for the same attributes (C-ATTR-06): the pages keep their rows, which take
    /// the new values with the rest.
    private func replaceValues(_ listing: AttributesViewModel.Listing) {
        let parts = AttributesViewModel.Listing.Kind.allCases.flatMap { listing.section($0)?.parts ?? [] }
        for (lazy, part) in zip(lazyParts, parts) { lazy.replaceValues(part.listed) }
        listBuiltRows()
    }
}
