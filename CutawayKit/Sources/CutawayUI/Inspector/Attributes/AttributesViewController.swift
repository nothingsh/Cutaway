import AppKit
import Combine
import CutawayModel
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
    private let onRetry: () -> Void
    /// Selects the layer at the other end of a constraint (C-LAYOUT-03), or an ancestor
    /// (C-ATTR-16).
    private let onShowLayer: (UInt64) -> Void
    /// Hovers the layer an ancestor names, or none (C-ATTR-16, C-HIER-15).
    private let onHoverLayer: (UInt64?) -> Void
    /// Hovers the other end of a constraint, or none (C-LAYOUT-06).
    private let onHoverConstraintEnd: (ConstraintRow.End?) -> Void
    private let onPointConstraints: (ConstraintPointer) -> Void
    /// How long a request may take before the panel says it is loading: most answers come
    /// sooner, and a spinner for every click would flicker.
    private let loadingDelay: TimeInterval
    /// The groups as they came.
    private(set) var groups: [AttributeGroup] = []
    /// The sections as listed, in the order of the list.
    private(set) var sectionViews: [AttributeGroupView] = []
    /// The sections folded away, by kind, kept while the panel lives; Object starts folded
    /// (C-ATTR-10, C-ATTR-15).
    var collapsed: Set<String> = [AttributesViewModel.Listing.Kind.object.rawValue]
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
    /// Each attribute's own row with the attribute it shows, in the order of the list.
    /// Set only as the rows are made (`AttributesViewController+Rows.swift`).
    var attributeRows: [(attribute: Attribute, row: AttributeRowView)] = []
    /// What shows each attribute, its own row or a part of a compound row (C-ATTR-19), in
    /// the order of `Listing.attributes`: what is updated in place (C-ATTR-06).
    var attributeCells: [(attribute: Attribute, cell: any AttributeCell)] = []
    /// The compound rows, in the order of the list.
    var compoundRows: [CompoundRowView] = []

    /// The filter (C-ATTR-14): kept while the panel lives, whatever is selected, refreshed or
    /// changed; nil when it keeps everything.
    var filter: String?
    /// How many attributes the filter keeps of how many, or nil without a filter.
    var filterCounts: (shown: Int, total: Int)?
    /// The section whose header stays at the top of the list, if any (C-ATTR-15).
    var stickySection: (any FoldingSection)?
    private let message = CurrentValueSubject<AttributesViewModel.Message?, Never>(nil)
    /// True while a request runs and nothing is shown yet, below the header.
    private let isWaiting = CurrentValueSubject<Bool, Never>(false)
    /// The layer whose attributes are listed, and the one selected now.
    private var listedLayerID: UInt64?
    private var selectedLayerID: UInt64?
    private var pendingLoading: DispatchWorkItem?
    // `list`, `separators`, `stickyBar`, `filter`, `filterCounts` and `stickySection` are
    // internal only so that AttributesViewController+Folding.swift can reach them.
    let list = VScroll(alignment: .fill, spacing: 0) {}
    /// The sections, each after a line that shows when a section above it does.
    private let sections = VStack(alignment: .fill, spacing: 0) {}
    var separators: [(line: NSView, section: NSView)] = []
    private(set) lazy var filterField: NSSearchField = FilterSearchField().configure {
        $0.sendsSearchStringImmediately = true
        $0.placeholderString = localized("attributes.filter.placeholder")
        // Each change of the text as it is typed; the action, for Esc and the clear button.
        $0.delegate = self
        $0.target = self
        $0.action = #selector(filterChanged(_:))
    }

    private(set) lazy var countLabel = NSTextField(labelWithString: "")
    private(set) lazy var noMatchLabel = NSTextField(wrappingLabelWithString: "")
    private(set) lazy var stickyHeader: SectionHeader = .init().configure {
        $0.target = self
        $0.action = #selector(toggleSticky(_:))
    }

    /// The selected layer's ancestors, under its name (C-ATTR-16).
    private(set) lazy var ancestorsBar: AncestorsBar = .init().configure {
        $0.onHover = { [weak self] id in self?.onHoverLayer(id) }
        $0.onSelect = { [weak self] id in self?.onShowLayer(id) }
    }

    /// The header that stays at the top, on the same backdrop as the panel (`backdrop()`),
    /// so that it is of a piece with the list under it (reported by the user: the sidebar's
    /// material let much more of the desktop through than the panel does).
    lazy var stickyBar: NSVisualEffectView = Self.backdrop().configure {
        $0.isHidden = true
    }

    private var cancellables = Set<AnyCancellable>()
    private let projectIndex: AnyPublisher<ProjectIndex?, Never>

    init(
        store: AttributesStore, appName: String,
        layer: AnyPublisher<LayerSummary?, Never> = Just(nil).eraseToAnyPublisher(),
        tree: AnyPublisher<LayerTree, Never> = Just(.empty).eraseToAnyPublisher(),
        connection: AnyPublisher<InspectionStore.Connection, Never> = Just(.live).eraseToAnyPublisher(),
        onRetry: @escaping () -> Void = {}, onShowLayer: @escaping (UInt64) -> Void = { _ in },
        onHoverLayer: @escaping (UInt64?) -> Void = { _ in },
        onHoverConstraintEnd: @escaping (ConstraintRow.End?) -> Void = { _ in },
        onPointConstraints: @escaping (ConstraintPointer) -> Void = { _ in },
        copy: @escaping @MainActor (String) -> Void = AttributesViewController.copyToPasteboard,
        openInXcode: @escaping @MainActor ([SourceLocation], NSView) -> Void = { _, _ in },
        projectIndex: AnyPublisher<ProjectIndex?, Never> = Just(nil).eraseToAnyPublisher(),
        loadingDelay: TimeInterval = 0.2
    ) {
        viewModel = AttributesViewModel(
            store: store, appName: appName, layer: layer, tree: tree, connection: connection)
        self.onRetry = onRetry
        self.onShowLayer = onShowLayer
        self.onHoverLayer = onHoverLayer
        self.onHoverConstraintEnd = onHoverConstraintEnd
        self.onPointConstraints = onPointConstraints
        self.loadingDelay = loadingDelay
        self.projectIndex = projectIndex
        identityView = IdentityLinesView(copy: copy, openInXcode: openInXcode)
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
        list.stack.addArrangedSubview(makeFilterResults())

        // Not shared: each subscriber gets the current value when it subscribes.
        let layer = viewModel.layer
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
        addStickyBar(over: list, in: root)
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
                        .isSelectable(true)
                        .accessibilityIdentifier(Self.headerTitleIdentifier)
                        .bind(\.stringValue, to: layer.map { $0?.title ?? "" })
                    // What holds the layer (C-HIER-07) and its size (C-ATTR-18). Cut short in
                    // the middle, so that the size at the end stays in view.
                    NSTextField(labelWithString: "")
                        .font(Theme.Font.caption)
                        .textColor(.secondaryLabelColor)
                        .lineBreakMode(.byTruncatingMiddle)
                        .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                        .isSelectable(true)
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
                    .bind(\.isEnabled, to: viewModel.isLive)
            }
            .padding(top: 0, leading: Theme.Spacing.large - 5, bottom: Theme.Spacing.small,
                     trailing: Theme.Spacing.medium)
            .bind(\.isHidden, to: layer.map { $0?.ancestors.isEmpty ?? true })
            VStack(alignment: .fill) {
                Self.filterBox(around: filterField
                    .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                    .accessibilityIdentifier(Self.filterIdentifier))
            }
            .padding(top: 0, leading: Theme.Spacing.medium, bottom: Theme.Spacing.small,
                     trailing: Theme.Spacing.medium)
            NSBox().configure { $0.boxType = .separator }
        }
        .accessibilityIdentifier(Self.headerIdentifier)
        .bind(\.isHidden, to: layer.map { $0 == nil })
    }

    /// What follows the sections while a filter is on: how many attributes it keeps, or that
    /// it keeps none (C-ATTR-14).
    private func makeFilterResults() -> NSView {
        VStack(alignment: .fill, spacing: 0) {
            VStack(alignment: .center) {
                noMatchLabel
                    .font(Theme.Font.body)
                    .textColor(.secondaryLabelColor)
                    .alignment(.center)
                    .accessibilityIdentifier(Self.noMatchIdentifier)
            }
            .padding(horizontal: Theme.Spacing.large, vertical: 28)
            VStack(alignment: .leading) {
                countLabel
                    .font(Theme.Font.caption)
                    .textColor(.tertiaryLabelColor)
                    .accessibilityIdentifier(Self.filterCountIdentifier)
            }
            .padding(top: Theme.Spacing.small, leading: Theme.Spacing.large, bottom: 0,
                     trailing: Theme.Spacing.large)
        }
    }

    /// The bar over the top of the list that holds the header of the section scrolled under it
    /// (C-ATTR-15).
    private func addStickyBar(over list: NSView, in root: NSView) {
        stickyBar.addVStack(alignment: .fill, spacing: 0) {
            VStack(alignment: .fill) {
                stickyHeader
                    .accessibilityIdentifier(Self.stickyIdentifier)
            }
            .padding(top: 8, leading: Theme.Spacing.large, bottom: 6, trailing: Theme.Spacing.medium)
            NSBox().configure { $0.boxType = .separator }
        }
        stickyBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stickyBar)
        NSLayoutConstraint.activate([
            stickyBar.topAnchor.constraint(equalTo: list.topAnchor),
            stickyBar.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            stickyBar.trailingAnchor.constraint(equalTo: list.trailingAnchor),
        ])
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
                .accessibilityIdentifier(Self.messageIdentifier)
                .bind(\.stringValue, to: message.map { $0?.title ?? "" })
            NSTextField(wrappingLabelWithString: "")
                .font(Theme.Font.caption)
                .textColor(.secondaryLabelColor)
                .alignment(.center)
                .accessibilityIdentifier(Self.detailIdentifier)
                .bind(\.stringValue, to: message.map { $0?.detail ?? "" })
                .bind(\.isHidden, to: message.map { $0?.detail == nil })
            NSButton()
                .title(localized("attributes.retry"))
                .bezelStyle(.rounded)
                .controlSize(.small)
                .accessibilityIdentifier(Self.retryIdentifier)
                .bind(\.isHidden, to: message.map { !($0?.offersRetry ?? false) })
                .sink(\.clickPublisher) { [weak self] in self?.onRetry() }
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

        // First, so that the first list is built knowing whether it can edit.
        viewModel.editing
            .sink { [weak self] canEdit, edits, isConnected in
                guard let self else { return }
                self.viewModel.canEdit = canEdit
                self.viewModel.edits = edits
                self.viewModel.isConnected = isConnected
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
            .sink { [weak self] _ in self?.updateSticky() }
            .store(in: &cancellables)

        // The names of colours and texts follow the project folder's index (C-SRC-04,
        // C-SRC-05): rows change in place once it is built.
        projectIndex
            .sink { [weak self] index in
                guard let self, index != self.viewModel.projectIndex else { return }
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
    private func showRowStates() {
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
            updateSticky()
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
        updateSticky()
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
                rows: rows, showsGenerated: showsGeneratedConstraints, onShowLayer: onShowLayer,
                onHoverEnd: onHoverConstraintEnd, onPoint: onPointConstraints)
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

    /// A line between two sections.
    private static func separator() -> NSView {
        VStack(alignment: .fill) {
            NSBox().configure { $0.boxType = .separator }
        }
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
            attributeCells = zip(listing.attributes, attributeCells.map(\.cell)).map {
                (attribute: $0, cell: $1)
            }
            attributeRows = attributeCells.compactMap { attribute, cell in
                (cell as? AttributeRowView).map { (attribute: attribute, row: $0) }
            }
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
        attributeRows = []
        attributeCells = []
        compoundRows = []
        sectionViews = AttributesViewModel.Listing.Kind.allCases.compactMap { kind in
            let section = listing.section(kind)
            switch kind {
            case .layout: guard hasLayoutSection(listing) else { return nil }
            case .object: break
            case .content, .appearance, .behavior: guard section != nil else { return nil }
            }
            let parts = (section?.parts ?? []).enumerated().map { index, part in
                // The Content section is titled by its first group; the others' groups go
                // without headings, as the section is about what they are for.
                AttributeGroupView.Part(
                    heading: kind == .content && index > 0
                        ? AttributeText.title(part.groupTitle, id: part.groupID) : nil,
                    rows: rows(part.listed))
            }
            return sectionView(kind, first: section?.parts.first, parts: parts)
        }
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
    var allSections: [any FoldingSection] { sectionViews }

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
}
