import AppKit
import Combine
import CutawayModel
import CutawayProjects
import DeclarativeAppKit
import DeclarativeCombine

/// The settings window's Projects page (C-SRC-01): the project folder linked to each app, by
/// its name, its bundle ID and the folder, which can be changed or forgotten. A folder that is
/// gone says so. Folders are linked from an inspector or archive window.
@MainActor
final class ProjectsSettingsViewController: NSViewController {
    static let tableIdentifier = "settings.projects.table"
    static let changeIdentifier = "settings.projects.change"
    static let removeIdentifier = "settings.projects.remove"
    static let emptyIdentifier = "settings.projects.empty"
    static let appColumn = NSUserInterfaceItemIdentifier("settings.projects.app")
    static let bundleIDColumn = NSUserInterfaceItemIdentifier("settings.projects.bundleID")
    static let folderColumn = NSUserInterfaceItemIdentifier("settings.projects.folder")

    let projects: ProjectSources
    /// Asks for a folder for an app, as an inspector window does. Tests choose one of their
    /// own.
    var chooseFolder: @MainActor (NSWindow, String, URL?, @escaping (URL) -> Void) -> Void =
        ProjectFolderPanel.choose

    /// The links shown, in the table's order, each with where its folder is now.
    private(set) var rows: [(link: ProjectFolders.Link, location: ProjectFolders.Location)] = []
    private var cancellables = Set<AnyCancellable>()

    private(set) lazy var table: NSTableView = .init().configure { table in
        for (identifier, title, width) in [
            (Self.appColumn, localized("settings.projects.app"), 140.0),
            (Self.bundleIDColumn, localized("settings.projects.bundleID"), 180.0),
            (Self.folderColumn, localized("settings.projects.folder"), 220.0),
        ] {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.style = .fullWidth
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityIdentifier(Self.tableIdentifier)
    }

    private(set) lazy var changeButton = NSButton(title: localized("settings.projects.change"), target: nil,
                                                  action: nil)
    private(set) lazy var removeButton = NSButton(title: localized("settings.projects.remove"), target: nil,
                                                  action: nil)
    private let emptyLabel = NSTextField(wrappingLabelWithString: localized("settings.projects.empty"))
    private let selection = CurrentValueSubject<IndexSet, Never>([])

    init(projects: ProjectSources) {
        self.projects = projects
        super.init(nibName: nil, bundle: nil)
        title = localized("settings.tab.projects")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let scroll = NSScrollView().configure {
            $0.documentView = table
            $0.hasVerticalScroller = true
            $0.borderType = .bezelBorder
        }
        .autohidesScrollers(true)
        .frame(width: 560, height: 170)
        view = NSView().configure {
            $0.addVStack(alignment: .leading, spacing: 12) {
                // Where the rows would be, while there are none.
                scroll.overlay(alignment: .center) {
                    emptyLabel
                        .alignment(.center)
                        .textColor(.secondaryLabelColor)
                        .accessibilityIdentifier(Self.emptyIdentifier)
                        .frame(width: 420)
                }
                HStack(spacing: 8) {
                    changeButton
                        .accessibilityIdentifier(Self.changeIdentifier)
                        .bind(\.isEnabled, to: selection.map { $0.count == 1 })
                        .sink(\.clickPublisher) { [weak self] in self?.changeSelectedFolder() }
                    removeButton
                        .accessibilityIdentifier(Self.removeIdentifier)
                        .bind(\.isEnabled, to: selection.map { !$0.isEmpty })
                        .sink(\.clickPublisher) { [weak self] in self?.removeSelectedLinks() }
                }
                NSTextField(wrappingLabelWithString: localized("settings.projects.explanation"))
                    .font(.systemFont(ofSize: NSFont.smallSystemFontSize))
                    .textColor(.secondaryLabelColor)
                    .frame(width: 560)
            }
            .padding(top: 20, leading: 20, bottom: 20, trailing: 20)
        }
        projects.folders.$links
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        reload()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // A folder may have come back, or gone, since the page was last shown.
        reload()
        preferredContentSize = view.fittingSize
    }

    /// Shows the links as they are kept, and where each folder is now.
    func reload() {
        let selected = Set(table.selectedRowIndexes
            .compactMap { rows.indices.contains($0) ? rows[$0].link.bundleID : nil })
        let folders = projects.folders
        rows = folders.links.map { ($0, folders.location(of: $0)) }
        table.reloadData()
        let keep = IndexSet(rows.indices.filter { selected.contains(rows[$0].link.bundleID) })
        table.selectRowIndexes(keep, byExtendingSelection: false)
        emptyLabel.isHidden = !rows.isEmpty
        selection.send(table.selectedRowIndexes)
    }

    /// Change…: a folder panel for the selected app, starting at its folder.
    func changeSelectedFolder() {
        guard table.selectedRowIndexes.count == 1, let index = table.selectedRowIndexes.first,
              rows.indices.contains(index), let window = view.window
        else { return }
        let link = rows[index].link
        let start: URL? = if case .found(let url) = rows[index].location { url } else { nil }
        chooseFolder(window, link.appName, start) { [weak self] folder in
            self?.projects.link(folder, bundleID: link.bundleID, appName: link.appName)
        }
    }

    /// Remove: forgets the selected apps' folders and their indexes.
    func removeSelectedLinks() {
        let bundleIDs = table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].link.bundleID : nil }
        for bundleID in bundleIDs {
            projects.remove(bundleID: bundleID)
        }
    }

    /// What a row's folder column says: the path with `~`, or that the folder is gone.
    static func folderText(_ location: ProjectFolders.Location) -> String {
        switch location {
        case .found(let url): (url.path as NSString).abbreviatingWithTildeInPath
        case .missing: localized("settings.projects.missing")
        }
    }
}

extension ProjectsSettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn?.identifier, rows.indices.contains(row) else { return nil }
        let (link, location) = rows[row]
        let cell = tableView.makeView(withIdentifier: column, owner: nil) as? NSTableCellView
            ?? Self.makeCell(column)
        let text = cell.textField
        text?.textColor = .labelColor
        text?.toolTip = nil
        switch column {
        case Self.appColumn:
            text?.stringValue = link.appName
        case Self.bundleIDColumn:
            text?.stringValue = link.bundleID
            text?.textColor = .secondaryLabelColor
        default:
            switch location {
            case .found(let url):
                text?.stringValue = Self.folderText(location)
                text?.toolTip = url.path
            case .missing(let path):
                text?.attributedStringValue = Self.missingText()
                text?.toolTip = path
            }
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selection.send(table.selectedRowIndexes)
    }

    /// "Can't find" in the warning colour, after a warning sign.
    private static func missingText() -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.systemOrange, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]
        let text = NSMutableAttributedString()
        if let image = Theme.symbol(Theme.Symbol.missingFolder, size: 11) {
            let attachment = NSTextAttachment()
            attachment.image = image
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: " ", attributes: attributes))
        }
        text.append(NSAttributedString(string: localized("settings.projects.missing"), attributes: attributes))
        return text
    }

    /// A cell with one text.
    private static func makeCell(_ column: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = column
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = column == folderColumn ? .byTruncatingMiddle : .byTruncatingTail
        text.font = column == bundleIDColumn ? Theme.Font.captionDigits : .systemFont(ofSize: NSFont.systemFontSize)
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
