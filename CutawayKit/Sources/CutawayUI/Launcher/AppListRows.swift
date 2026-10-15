import CutawayModel
import CutawayTransport

/// The rows of the app list (C-LIST-01): the apps in the store's order, with a header before
/// each group of apps that run in the same place.
struct AppListRows: Equatable {
    /// Where a group of apps runs.
    enum Place: Equatable {
        /// The simulators on this Mac.
        case thisMac
        /// One device connected by USB.
        case usb(serial: String)
    }

    /// The header of a group (C-LIST-04): where it runs, its name, and how it is reached.
    struct Group: Equatable {
        var place: Place
        /// "This Mac", or the device's name.
        var title: String
        /// "Simulators" or "USB", after the title.
        var via: String
    }

    /// One row of the table.
    enum Row: Equatable {
        case group(Group)
        case app(AppEntry)
    }

    /// Which way the arrow keys move.
    enum Direction {
        case up, down
    }

    private(set) var rows: [Row] = []

    init() {}

    init(_ entries: [AppEntry]) {
        rows = Self.rows(for: entries)
    }

    /// The rows for some entries, in their order, with a header before each group.
    static func rows(for entries: [AppEntry]) -> [Row] {
        var rows: [Row] = []
        var currentPlace: Place?
        for entry in entries {
            let group: Group
            switch entry.id {
            case .simulator:
                group = Group(
                    place: .thisMac, title: localized("appList.group.thisMac"),
                    via: localized("appList.group.simulators"))
            case .device(let serial, _):
                let name = entry.info?.deviceName
                    .flatMap { $0.isEmpty ? nil : $0 } ?? localized("appList.group.usbDevice")
                group = Group(place: .usb(serial: serial), title: name, via: localized("appList.group.usb"))
            }
            if group.place != currentPlace {
                rows.append(.group(group))
                currentPlace = group.place
            }
            rows.append(.app(entry))
        }
        return rows
    }

    /// Whether `row` is an app that can be inspected: one the selection may rest on.
    func isChoosable(_ row: Int) -> Bool {
        guard rows.indices.contains(row), case .app(let entry) = rows[row] else { return false }
        return entry.isInspectable
    }

    /// The first app that can be inspected; nil when there is none.
    var firstChoosableRow: Int? {
        rows.indices.first(where: isChoosable)
    }

    /// The next app that can be inspected from `row` in `direction`, past headers and apps that
    /// cannot be inspected; nil at the end. Without a selection (`row` outside the rows), the
    /// first one.
    func nextChoosableRow(from row: Int, direction: Direction) -> Int? {
        guard rows.indices.contains(row) else { return firstChoosableRow }
        switch direction {
        case .down: return rows.indices[(row + 1)...].first(where: isChoosable)
        case .up: return rows.indices[..<row].last(where: isChoosable)
        }
    }

    /// The table row of the app at `id`, when it can be inspected.
    func choosableRow(of id: AppLocation) -> Int? {
        let row = rows.indices.first { row in
            if case .app(let entry) = rows[row] { entry.id == id } else { false }
        }
        return row.flatMap { isChoosable($0) ? $0 : nil }
    }

    /// The table row of the app at `index` among the apps.
    func tableRow(ofApp index: Int) -> Int? {
        var seen = -1
        for (row, item) in rows.enumerated() {
            guard case .app = item else { continue }
            seen += 1
            if seen == index { return row }
        }
        return nil
    }

    /// How many apps the list shows.
    var appCount: Int {
        rows.filter { if case .app = $0 { return true } else { return false } }.count
    }
}
