import AppKit
import Combine
import CutawayModel
import CutawayWire
import DeclarativeAppKit
import DeclarativeCombine

/// The attributes of the selected layer (C-ATTR-01 to C-ATTR-03): a header naming the layer,
/// then each group the app sent, in its order and titled as the app titled it, with its
/// attributes. Nothing here knows any particular group or attribute (P-ATTR-03). A group folds
/// away from its header. When there is nothing to list, a symbol and a line of text say why.
///
/// Attributes the app marks as editable get an editor while the server can change them, the
/// app is active and the connection holds (C-ATTR-04). New values for the same attributes are
/// shown in place, so that a field being typed in keeps its focus and a drag goes on
/// (C-ATTR-06); rows that are being changed show it, and failures are said in the row.
///
/// For a layer that backs a view, a Constraints section follows the groups when the server
/// gives constraints (C-LAYOUT-02). It is rebuilt on its own, leaving the attribute rows as
/// they are.
final class AttributesViewController: NSViewController {
    static let listIdentifier = "attributes.list"
    static let messageIdentifier = "attributes.message"
    static let detailIdentifier = "attributes.detail"
    static let retryIdentifier = "attributes.retry"
    static let headerIdentifier = "attributes.header"
    static let headerTitleIdentifier = "attributes.header.title"
    static let headerSubtitleIdentifier = "attributes.header.subtitle"
    static let headerControllerIdentifier = "attributes.header.controller"
    static let headerReferencesIdentifier = "attributes.header.references"

    let viewModel: AttributesViewModel
    private let onRetry: () -> Void
    /// Selects the layer at the other end of a constraint (C-LAYOUT-03).
    private let onShowLayer: (UInt64) -> Void
    /// How long a request may take before the panel says it is loading: most answers come
    /// sooner, and a spinner for every click would flicker.
    private let loadingDelay: TimeInterval
    /// The groups shown, with their views.
    private(set) var groups: [AttributeGroup] = []
    private(set) var groupViews: [AttributeGroupView] = []
    /// The groups the user folded away, by ID, kept while the panel lives.
    private var collapsed = Set<String>()
    /// The views the groups take in the list: the groups and the separators between them.
    private var groupArrangedViews: [NSView] = []
    /// The constraints shown, or nil when there is no Constraints section.
    private(set) var constraintRows: [ConstraintRow]?
    private(set) var constraintsView: ConstraintsSectionView?
    private var constraintsSeparator: NSView?
    /// Whether the Constraints section is folded away, and whether UIKit's constraints are
    /// listed; kept while the panel lives, as the groups' folding is.
    private var constraintsCollapsed = false
    private var showsGeneratedConstraints = false
    /// The shape of what is listed: rebuilt when it changes, updated in place when not.
    private var shownShape: AttributesViewModel.Shape?
    /// Each attribute row with the attribute it shows, in the order of `groups`.
    private(set) var attributeRows: [(attribute: Attribute, row: AttributeRowView)] = []
    private let message = CurrentValueSubject<AttributesViewModel.Message?, Never>(nil)
    /// True while a request runs and nothing is shown yet, below the header.
    private let isWaiting = CurrentValueSubject<Bool, Never>(false)
    /// The layer whose attributes are listed, and the one selected now.
    private var listedLayerID: UInt64?
    private var selectedLayerID: UInt64?
    private var pendingLoading: DispatchWorkItem?
    private let list = VScroll(alignment: .fill, spacing: 0) {}
    private var cancellables = Set<AnyCancellable>()

    init(
        store: AttributesStore, appName: String,
        layer: AnyPublisher<LayerSummary?, Never> = Just(nil).eraseToAnyPublisher(),
        tree: AnyPublisher<LayerTree, Never> = Just(.empty).eraseToAnyPublisher(),
        connection: AnyPublisher<InspectionStore.Connection, Never> = Just(.live).eraseToAnyPublisher(),
        onRetry: @escaping () -> Void = {}, onShowLayer: @escaping (UInt64) -> Void = { _ in },
        loadingDelay: TimeInterval = 0.2
    ) {
        viewModel = AttributesViewModel(
            store: store, appName: appName, layer: layer, tree: tree, connection: connection)
        self.onRetry = onRetry
        self.onShowLayer = onShowLayer
        self.loadingDelay = loadingDelay
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

        // Not shared: each subscriber gets the current value when it subscribes.
        let layer = viewModel.layer
        let header = makeHeader(layer: layer)
        let emptyState = makeEmptyState()

        // Takes the room below the header while nothing else is shown, so that the header
        // stays at the top.
        let filler = NSView()
            .contentHuggingPriority(.defaultLow, for: .vertical)
            .bind(\.isHidden, to: isWaiting.map { !$0 })

        let root = NSView()
        root.addVStack(alignment: .fill) {
            header
            list
            emptyState
            filler
        }
        view = root
        header.setContentHuggingPriority(.required, for: .vertical)
        follow(layer: layer)
    }

    /// The selected layer's symbol, title, class, view controller and references.
    private func makeHeader(layer: AnyPublisher<LayerSummary?, Never>) -> NSView {
        VStack(alignment: .fill, spacing: 0) {
            // The symbol stays beside the title however many lines follow it.
            HStack(alignment: .top, spacing: 10) {
                NSBox()
                    .configure {
                        $0.boxType = .custom
                        $0.borderWidth = 0
                        $0.cornerRadius = 7
                        $0.fillColor = .quaternarySystemFill
                        $0.contentViewMargins = .zero
                        $0.titlePosition = .noTitle
                        $0.contentView?.addContent(VStack(alignment: .center) {
                            Spacer()
                            NSImageView()
                                .contentTintColor(.controlAccentColor)
                                .bind(\.image, to: layer.map {
                                    $0.flatMap { Theme.symbol($0.symbol, size: 14) }
                                })
                            Spacer()
                        })
                    }
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    NSTextField(labelWithString: "")
                        .font(Theme.Font.bodyEmphasized)
                        .lineBreakMode(.byTruncatingTail)
                        .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                        .isSelectable(true)
                        .accessibilityIdentifier(Self.headerTitleIdentifier)
                        .bind(\.stringValue, to: layer.map { $0?.title ?? "" })
                    NSTextField(labelWithString: "")
                        .font(Theme.Font.captionDigits)
                        .textColor(.secondaryLabelColor)
                        .lineBreakMode(.byTruncatingTail)
                        .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                        .isSelectable(true)
                        .accessibilityIdentifier(Self.headerSubtitleIdentifier)
                        .bind(\.stringValue, to: layer.map { $0?.subtitle ?? "" })
                    // Where the layer is held (C-HIER-07): only what the hierarchy says.
                    Self.headerLine(
                        localized("attributes.header.viewController"), identifier: Self.headerControllerIdentifier,
                        value: layer.map { $0?.controller })
                    Self.headerLine(
                        localized("attributes.header.referencedBy"), identifier: Self.headerReferencesIdentifier,
                        value: layer.map { summary in
                            summary.flatMap {
                                $0.references.isEmpty ? nil : $0.references.joined(separator: "\n")
                            }
                        })
                }
                // The texts take the rest of the row, so that one that fits is shown whole:
                // they give way to the panes' widths (`Theme.textGivesWay`), and beside a
                // spacer the stack squeezed them instead.
                .contentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            }
            .padding(top: Theme.Spacing.medium, leading: Theme.Spacing.large,
                     bottom: Theme.Spacing.medium, trailing: Theme.Spacing.large)
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
            .sink { [weak self] summary in self?.selectedLayerID = summary?.id }
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
    }

    // MARK: - Changing attributes

    private func makeRow(_ attribute: Attribute) -> AttributeRowView {
        let title = AttributeText.title(attribute.title, id: attribute.id)
        guard viewModel.hasEditor(attribute), let key = viewModel.key(of: attribute) else {
            return AttributeRowView(title: title, value: attribute.value)
        }
        let editor = AttributeEditorView(
            attribute: attribute, onSet: viewModel.setValue(for: key),
            onFinish: viewModel.finish(for: key))
        return AttributeRowView(title: title, value: attribute.value, editor: editor)
    }

    /// Each row's value and state: a row being changed shows the value on its way.
    private func showRowStates() {
        for (attribute, row) in attributeRows {
            let state = viewModel.rowState(of: attribute)
            row.show(state.value)
            row.show(sending: state.isSending, failure: state.failureText)
        }
    }

    // MARK: - What is shown

    /// As wide as the wider of the header's two labels.
    private static var headerLabelWidth: CGFloat {
        [localized("attributes.header.viewController"), localized("attributes.header.referencedBy")]
            .map {
                NSTextField(labelWithString: $0).font(Theme.Font.caption).intrinsicContentSize.width
            }
            .max().map { $0.rounded(.up) } ?? 0
    }

    /// A line of the header: a label and a value that can be selected, one entry to a line;
    /// hidden while there is no value.
    private static func headerLine(
        _ title: String, identifier: String, value: some Publisher<String?, Never>
    ) -> NSView {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            NSTextField(labelWithString: title)
                .font(Theme.Font.caption)
                .textColor(.tertiaryLabelColor)
                // The same for both lines, so that their values line up.
                .frame(width: headerLabelWidth)
            NSTextField(wrappingLabelWithString: "")
                .font(Theme.Font.caption)
                .textColor(.secondaryLabelColor)
                .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                .isSelectable(true)
                .accessibilityIdentifier(identifier)
                .bind(\.stringValue, to: value.map { $0 ?? "" })
        }
        .padding(top: 2, leading: 0, bottom: 0, trailing: 0)
        .bind(\.isHidden, to: value.map { $0 == nil })
    }

    /// Every symbol the panel's messages use. A misspelt name makes no image.
    static var symbols: [String] {
        ["cursorarrow.click.2", "list.bullet.rectangle", "questionmark.square.dashed",
         "moon.zzz", "exclamationmark.triangle", "checkmark.circle.fill", "circle",
         "chevron.right", "chevron.down"] + ConstraintRowView.symbols
    }

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
            return
        }
        isWaiting.send(false)
        present(state)
    }

    /// Shows a state other than loading: the groups and the constraints, or a message.
    private func present(_ state: AttributesStore.State) {
        let rows = viewModel.constraintRows(for: state)
        let shown = AttributesViewModel.message(
            for: state, appName: viewModel.appName, hasConstraints: rows != nil)
        if case .loaded(let groups, _) = state, shown == nil {
            showGroups(groups)
            showConstraints(rows)
        } else {
            showGroups([])
            showConstraints(nil)
        }
        message.send(shown)
        list.isHidden = shown != nil
    }

    /// Shows the Constraints section, or none, after the groups. Built again only when what it
    /// says changes.
    private func showConstraints(_ rows: [ConstraintRow]?) {
        defer { constraintsSeparator?.isHidden = groupViews.isEmpty }
        guard rows != constraintRows else { return }
        constraintRows = rows
        constraintsView?.removeFromSuperview()
        constraintsSeparator?.removeFromSuperview()
        constraintsView = nil
        constraintsSeparator = nil
        guard let rows else { return }
        let section = ConstraintsSectionView(
            rows: rows, isCollapsed: constraintsCollapsed,
            showsGenerated: showsGeneratedConstraints, onShowLayer: onShowLayer)
        section.onToggle = { [weak self] in self?.constraintsCollapsed = $0 }
        section.onToggleGenerated = { [weak self] in self?.showsGeneratedConstraints = $0 }
        let separator = Self.separator()
        list.stack.addArrangedSubview(separator)
        list.stack.addArrangedSubview(section)
        constraintsView = section
        constraintsSeparator = separator
        scrollToTopForAnotherLayer()
    }

    /// A line between two parts of the list.
    private static func separator() -> NSView {
        VStack(alignment: .fill) {
            NSBox().configure { $0.boxType = .separator }
        }.padding(horizontal: Theme.Spacing.large, vertical: 0)
    }

    /// Another layer's attributes start at the top; a new answer for the same layer stays
    /// where the user scrolled to.
    private func scrollToTopForAnotherLayer() {
        guard selectedLayerID != listedLayerID else { return }
        listedLayerID = selectedLayerID
        list.contentView.scroll(to: .zero)
        list.reflectScrolledClipView(list.contentView)
    }

    private func showGroups(_ new: [AttributeGroup], force: Bool = false) {
        let newShape = viewModel.shape(of: new)
        if !new.isEmpty, newShape == shownShape {
            // The same attributes of the same layer: new values in place (C-ATTR-06).
            groups = new
            attributeRows = zip(new.flatMap(\.attributes), attributeRows.map(\.row)).map {
                (attribute: $0, row: $1)
            }
            showRowStates()
            return
        }
        guard new != groups || force || newShape != shownShape else { return }
        groups = new
        shownShape = new.isEmpty ? nil : newShape
        // The Constraints section after them stays.
        let stack = list.stack
        for view in groupArrangedViews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        groupArrangedViews = []
        attributeRows = []
        groupViews = new.map { group in
            let key = group.id ?? group.title ?? ""
            let rows = group.attributes.map { attribute in
                let row = makeRow(attribute)
                attributeRows.append((attribute, row))
                return row
            }
            let view = AttributeGroupView(
                title: AttributeText.title(group.title, id: group.id), rows: rows,
                isCollapsed: collapsed.contains(key))
            view.onToggle = { [weak self] isCollapsed in
                if isCollapsed { self?.collapsed.insert(key) } else { self?.collapsed.remove(key) }
            }
            return view
        }
        for (index, view) in groupViews.enumerated() {
            if index > 0 { groupArrangedViews.append(Self.separator()) }
            groupArrangedViews.append(view)
        }
        for (index, view) in groupArrangedViews.enumerated() {
            stack.insertArrangedSubview(view, at: index)
        }
        constraintsSeparator?.isHidden = groupViews.isEmpty
        showRowStates()
        if !new.isEmpty { scrollToTopForAnotherLayer() }
    }

    // MARK: - For tests

    /// One row of the panel. For tests.
    enum Row: Equatable {
        case group(title: String)
        case attribute(title: String, value: AttributeValue?)
    }

    /// The rows for some groups: each group's header, then its attributes, as they came.
    /// For tests.
    static func rows(for groups: [AttributeGroup]) -> [Row] {
        groups.flatMap { group in
            [Row.group(title: AttributeText.title(group.title, id: group.id))]
                + group.attributes.map { attribute in
                    Row.attribute(
                        title: AttributeText.title(attribute.title, id: attribute.id),
                        value: attribute.value)
                }
        }
    }
}
