import AppKit
import Combine
import CutawayModel
import CutawayTransport
import DeclarativeAppKit
import DeclarativeCombine

/// The list of apps that can be inspected, grouped by where they run, or an explanation when
/// there are none. A click on an app, or Return on the selected one, opens it (C-LIST-01);
/// the arrow keys only move the selection, from one app that can be inspected to the next
/// (C-LIST-04). The first such app is selected as soon as there is one.
final class AppListViewController: NSViewController {
    /// The accessibility identifier of the view shown when the list is empty.
    static let emptyStateIdentifier = "apps.empty"
    static let emptyLinkIdentifier = "apps.empty.link"
    static let emptyImageIdentifier = "apps.empty.image"
    /// The empty list's picture: the layers of the app's icon, apart (C-LIST-04).
    static var emptyImage: NSImage? { Bundle.module.image(forResource: "EmptyLayers") }
    static let emptyImageOpacity: CGFloat = 0.35
    static let groupIdentifier = "apps.group"
    static let groupViaIdentifier = "apps.group.via"
    static let groupTileIdentifier = "apps.group.tile"

    private static let appRowIdentifier = NSUserInterfaceItemIdentifier("AppRow")
    private static let groupRowIdentifier = NSUserInterfaceItemIdentifier("AppGroupRow")
    static let appRowHeight: CGFloat = 50
    static let groupRowHeight: CGFloat = 32

    private let store: AppListStore
    /// What a chosen app is handed to. Without it the store inspects the app: for tests, as
    /// the app always hands it to the window coordinator.
    private let onChoose: ((AppLocation) -> Void)?
    /// Opens a page on the web: the empty list's link to the integration guide.
    private let openURL: @MainActor (URL) -> Void
    private(set) var list = AppListRows()
    /// The table's rows.
    var rows: [AppListRows.Row] { list.rows }
    private var cancellables = Set<AnyCancellable>()
    let tableView = AppTableView()

    init(
        store: AppListStore, onChoose: ((AppLocation) -> Void)? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.store = store
        self.onChoose = onChoose
        self.openURL = openURL
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
        tableView.onArrow = { [weak self] direction in self?.move(direction) }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let root = NSView()
        root.addVStack(alignment: .fill) {
            // The layers of the app's icon, apart (C-LIST-04).
            VStack(alignment: .center, spacing: 18) {
                Spacer()
                NSImageView()
                    .image(Self.emptyImage)
                    .imageScaling(.scaleProportionallyUpOrDown)
                    .frame(width: 160, height: 120)
                    // Faint: a placeholder, not the first thing the eye goes to.
                    .alphaValue(Self.emptyImageOpacity)
                    .accessibilityIdentifier(Self.emptyImageIdentifier)
                VStack(alignment: .center, spacing: 6) {
                    NSTextField(labelWithString: localized("appList.empty.title"))
                        .font(.systemFont(ofSize: 15, weight: .semibold))
                    NSTextField(wrappingLabelWithString: localized("appList.empty.detail"))
                        .textColor(.secondaryLabelColor)
                        .alignment(.center)
                }
                emptyLink
                    .accessibilityIdentifier(Self.emptyLinkIdentifier)
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
        // Back in the list, the app just inspected is selected again, or else the first one.
        // Selecting opens nothing: only a click or Return does.
        store.$inspectedApp
            .sink { [weak self] app in
                guard let self else { return }
                if app == nil, let left = self.inspected {
                    self.select(self.list.choosableRow(of: left) ?? self.list.firstChoosableRow)
                }
                self.inspected = app
            }
            .store(in: &cancellables)
    }

    /// The app being inspected, as last published.
    private var inspected: AppLocation?

    private func show(_ entries: [AppEntry]) {
        let selected = rows.indices.contains(tableView.selectedRow)
            ? rows[tableView.selectedRow] : nil
        list = AppListRows(entries)
        tableView.reloadData()
        // The selection is only where the keyboard is; keep it on the same app, or else on the
        // first one that can be inspected.
        let same: Int? = if case .app(let entry)? = selected { list.choosableRow(of: entry.id) } else { nil }
        select(same ?? list.firstChoosableRow)
    }

    /// Selects `row` and scrolls to it; nil selects nothing.
    private func select(_ row: Int?) {
        guard let row else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    /// Moves the selection to the next app that can be inspected; at the end it stays.
    func move(_ direction: AppListRows.Direction) {
        guard let row = list.nextChoosableRow(from: tableView.selectedRow, direction: direction)
        else { return }
        select(row)
    }

    /// The link to the integration guide under the empty list's explanation.
    private(set) lazy var emptyLink: NSButton = .init(
        title: "", target: self, action: #selector(openIntegrationGuide(_:))
    ).configure {
        $0.isBordered = false
        $0.attributedTitle = NSAttributedString(
            string: localized("appList.empty.link"),
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.linkColor])
    }

    @objc func openIntegrationGuide(_ sender: Any?) {
        openURL(Links.integrationGuide)
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
        guard rows.indices.contains(row), case .group = rows[row] else { return Self.appRowHeight }
        return Self.groupRowHeight
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
        case .group(let group):
            let view =
                tableView.makeView(withIdentifier: Self.groupRowIdentifier, owner: nil)
                    as? AppGroupHeaderView ?? AppGroupHeaderView()
            view.identifier = Self.groupRowIdentifier
            view.configure(with: group)
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

/// The table of the app list. Return opens the selected app; the arrow keys move between the
/// apps that can be inspected, which the table's own handling does not promise to do.
final class AppTableView: NSTableView {
    var onReturn: () -> Void = {}
    var onArrow: (AppListRows.Direction) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        // The arrow keys carry the numeric pad and function flags by themselves.
        let plain = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function]).isEmpty
        switch event.keyCode {
        // Return and the keypad's Enter.
        case 36, 76: onReturn()
        case 126 where plain: onArrow(.up)
        case 125 where plain: onArrow(.down)
        default: super.keyDown(with: event)
        }
    }
}

/// A row that lightens under the pointer, so that a row reads as something to click; with the
/// hierarchy list's fill (C-LIST-04).
final class HoverRowView: NSTableRowView {
    var isHovered = false {
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
        Theme.hoverFill.setFill()
        // The shape of the inset table's selection.
        NSBezierPath(
            roundedRect: HierarchyTableRowView.hoverRect(in: bounds), xRadius: Theme.Radius.control,
            yRadius: Theme.Radius.control
        ).fill()
    }
}

/// The header of a group of apps (C-LIST-04): a tile for where they run, the name, and how it
/// is reached.
final class AppGroupHeaderView: NSTableCellView {
    static let tileSide: CGFloat = 18

    private let tileView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let viaLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        addHStack(alignment: .center, spacing: Theme.Spacing.small) {
            tileView
                .frame(width: Self.tileSide, height: Self.tileSide)
                .accessibilityIdentifier(AppListViewController.groupTileIdentifier)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                titleLabel
                    .font(.systemFont(ofSize: 12, weight: .semibold))
                    .lineBreakMode(.byTruncatingTail)
                    .compressionResistancePriority(.defaultLow, for: .horizontal)
                    .accessibilityIdentifier(AppListViewController.groupIdentifier)
                viaLabel
                    .font(Theme.Font.caption)
                    .textColor(.secondaryLabelColor)
                    .accessibilityIdentifier(AppListViewController.groupViaIdentifier)
            }
            Spacer()
        }
        .padding(top: 10, leading: 10, bottom: 4, trailing: 10)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The tile of a place: this Mac in the window's colour, a USB device in the bars'.
    static func tile(of place: AppListRows.Place) -> NSImage {
        switch place {
        case .thisMac: LayerIconImage.deviceTile(.simulator, .window, side: tileSide)
        case .usb: LayerIconImage.deviceTile(.phone, .bar, side: tileSide)
        }
    }

    func configure(with group: AppListRows.Group) {
        tileView.image = Self.tile(of: group.place)
        titleLabel.stringValue = group.title
        viaLabel.stringValue = group.via
    }
}
