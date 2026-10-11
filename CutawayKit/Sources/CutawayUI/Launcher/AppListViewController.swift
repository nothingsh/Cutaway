import AppKit
import Combine
import CutawayModel
import CutawayTransport
import DeclarativeAppKit
import DeclarativeCombine

/// The list of apps that can be inspected, grouped by where they run, or an explanation when
/// there are none. A click on an app, or Return on the selected one, opens it (C-LIST-01);
/// the arrow keys only move the selection.
final class AppListViewController: NSViewController {
    /// The accessibility identifier of the view shown when the list is empty.
    static let emptyStateIdentifier = "apps.empty"
    static let groupIdentifier = "apps.group"

    private static let appRowIdentifier = NSUserInterfaceItemIdentifier("AppRow")
    private static let groupRowIdentifier = NSUserInterfaceItemIdentifier("AppGroupRow")
    static let appRowHeight: CGFloat = 60
    static let groupRowHeight: CGFloat = 28
    static let incompatibleRowHeight: CGFloat = 76

    private let store: AppListStore
    /// What a chosen app is handed to. Without it the store inspects the app: for tests, as
    /// the app always hands it to the window coordinator.
    private let onChoose: ((AppLocation) -> Void)?
    private(set) var list = AppListRows()
    /// The table's rows.
    var rows: [AppListRows.Row] { list.rows }
    private var cancellables = Set<AnyCancellable>()
    let tableView = AppTableView()

    init(store: AppListStore, onChoose: ((AppLocation) -> Void)? = nil) {
        self.store = store
        self.onChoose = onChoose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        // Rows are driven by data, so this is a table: a stack's content closure runs once.
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app")))
        tableView.headerView = nil
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = false
        tableView.floatsGroupRows = false
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(tableWasClicked(_:))
        tableView.onReturn = { [weak self] in
            guard let self else { return }
            self.choose(row: self.tableView.selectedRow)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let root = NSView()
        root.addVStack(alignment: .fill) {
            VStack(alignment: .center, spacing: Theme.Spacing.small) {
                Spacer()
                NSImageView()
                    .image(Theme.symbol(Theme.Symbol.noApps, size: 44, weight: .light))
                    .contentTintColor(.tertiaryLabelColor)
                NSTextField(labelWithString: localized("appList.empty.title"))
                    .font(.systemFont(ofSize: 15, weight: .semibold))
                NSTextField(
                    wrappingLabelWithString:
                    localized("appList.empty.detail")
                )
                .textColor(.secondaryLabelColor)
                .alignment(.center)
                Spacer()
            }
            .padding(horizontal: 48, vertical: 24)
            .accessibilityIdentifier(Self.emptyStateIdentifier)
            .bind(\.isHidden, to: store.$entries.map { !$0.isEmpty })

            scrollView
                .bind(\.isHidden, to: store.$entries.map(\.isEmpty))
        }
        view = root

        store.$entries
            .sink { [weak self] entries in self?.show(entries) }
            .store(in: &cancellables)
        // Back in the list, no row is selected: a reload must not find a selection to act on.
        store.$inspectedApp
            .filter { $0 == nil }
            .sink { [weak self] _ in self?.tableView.deselectAll(nil) }
            .store(in: &cancellables)
    }

    private func show(_ entries: [AppEntry]) {
        let selected = rows.indices.contains(tableView.selectedRow)
            ? rows[tableView.selectedRow] : nil
        list = AppListRows(entries)
        tableView.reloadData()
        // The selection is only where the keyboard is; keep it on the same app.
        if let row = list.tableRow(ofSameAppAs: selected) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    @objc private func tableWasClicked(_ sender: NSTableView) {
        choose(row: sender.clickedRow)
    }

    /// Opens the app in `row`, if it is one that can be opened.
    func choose(row: Int) {
        guard rows.indices.contains(row), case .app(let entry) = rows[row], entry.isInspectable
        else { return }
        if let onChoose {
            onChoose(entry.id)
        } else {
            // For tests.
            store.inspect(entry.id)
        }
    }

    // MARK: - For tests

    /// The table row of the app at `index` among the apps.
    func tableRow(ofApp index: Int) -> Int? {
        list.tableRow(ofApp: index)
    }

    /// How many apps the list shows.
    var appCount: Int { list.appCount }

    /// The view of the app at `index` among the apps, configured.
    func row(_ index: Int) -> AppRowView? {
        guard let row = tableRow(ofApp: index) else { return nil }
        return tableView(tableView, viewFor: tableView.tableColumns.first, row: row) as? AppRowView
    }
}

extension AppListViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return Self.appRowHeight }
        switch rows[row] {
        case .group: return Self.groupRowHeight
        // One more line: the two protocol versions.
        case .app(let entry): return entry.isInspectable ? Self.appRowHeight : Self.incompatibleRowHeight
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .group = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard rows.indices.contains(row), case .app = rows[row] else { return nil }
        return HoverRowView()
    }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case .group(let title, let symbol):
            let view =
                tableView.makeView(withIdentifier: Self.groupRowIdentifier, owner: nil)
                    as? AppGroupHeaderView ?? AppGroupHeaderView()
            view.identifier = Self.groupRowIdentifier
            view.configure(title: title, symbol: symbol)
            return view
        case .app(let entry):
            let view =
                tableView.makeView(withIdentifier: Self.appRowIdentifier, owner: nil)
                    as? AppRowView ?? AppRowView()
            view.identifier = Self.appRowIdentifier
            view.configure(with: entry)
            return view
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        // A header is not a choice, and an incompatible app is listed but not a choice
        // either (C-LIST-02).
        guard rows.indices.contains(row), case .app(let entry) = rows[row] else { return false }
        return entry.isInspectable
    }
}

/// The table of the app list. Return opens the selected app.
final class AppTableView: NSTableView {
    var onReturn: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        // Return and the keypad's Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// A row that lightens under the pointer, so that a row reads as something to click.
final class HoverRowView: NSTableRowView {
    private(set) var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isHovered, !isSelected else { return }
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        NSBezierPath(
            roundedRect: bounds, xRadius: Theme.Radius.control,
            yRadius: Theme.Radius.control
        ).fill()
    }
}

/// The header of a group of apps: a symbol and a name.
final class AppGroupHeaderView: NSTableCellView {
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        addHStack(alignment: .center, spacing: 6) {
            symbolView.contentTintColor(.secondaryLabelColor)
            titleLabel
                .font(Theme.Font.captionEmphasized)
                .textColor(.secondaryLabelColor)
                .lineBreakMode(.byTruncatingTail)
                .accessibilityIdentifier(AppListViewController.groupIdentifier)
            Spacer()
        }
        .padding(top: 8, leading: Theme.Spacing.tight, bottom: 2, trailing: Theme.Spacing.tight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String, symbol: String) {
        titleLabel.stringValue = title
        symbolView.image = Theme.symbol(symbol, size: 11, weight: .medium)
    }
}
