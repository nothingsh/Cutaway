import CutawayModel

/// The rows of the app list (C-LIST-01): the apps in the store's order, with a header before
/// each group of apps that run in the same place.
struct AppListRows: Equatable {
    /// One row of the table.
    enum Row: Equatable {
        /// The header of a group: the simulators on this Mac, or one USB device.
        case group(title: String, symbol: String)
        case app(AppEntry)
    }

    private(set) var rows: [Row] = []

    init() {}

    init(_ entries: [AppEntry]) {
        rows = Self.rows(for: entries)
    }

    /// The rows for some entries, in their order, with a header before each group.
    static func rows(for entries: [AppEntry]) -> [Row] {
        var rows: [Row] = []
        var currentGroup: String?
        for entry in entries {
            let group: String
            let header: Row
            switch entry.id {
            case .simulator:
                group = "simulator"
                header = .group(title: localized("appList.group.thisMac"), symbol: Theme.Symbol.thisMac)
            case .device(let serial, _):
                group = "device:" + serial
                let name = entry.info?.deviceName
                    .flatMap { $0.isEmpty ? nil : $0 } ?? localized("appList.group.usbDevice")
                header = .group(title: localized("appList.group.usb", name), symbol: Theme.Symbol.usbDevice)
            }
            if group != currentGroup {
                rows.append(header)
                currentGroup = group
            }
            rows.append(.app(entry))
        }
        return rows
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

    /// The table row of the same app as `row`, which is from another list; nil when `row` is
    /// not an app's or this list does not have it.
    func tableRow(ofSameAppAs row: Row?) -> Int? {
        guard case .app(let entry)? = row else { return nil }
        return rows.firstIndex(where: {
            if case .app(let other) = $0 { return other.id == entry.id } else { return false }
        })
    }
}
