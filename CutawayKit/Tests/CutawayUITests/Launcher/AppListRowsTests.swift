import CutawayModel
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The app list's rows, without the table: C-LIST-01.
final class AppListRowsTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")

    private func entry(_ id: AppLocation, deviceName: String? = "iPhone 16") -> AppEntry {
        var info = Self.demo
        info.deviceName = deviceName
        return AppEntry(id: id, info: info, status: .ready(.active), icon: nil)
    }

    func test_C_LIST_01_appsAreGroupedByWhereTheyRun() {
        let simulator = entry(.simulator(port: 48160))
        let phoneA = entry(.device(serial: "A", port: 48160), deviceName: "Wynn's iPhone")
        let phoneB = entry(.device(serial: "A", port: 48161), deviceName: "Wynn's iPhone")
        let pad = entry(.device(serial: "B", port: 48160), deviceName: "iPad Air")
        let unnamed = entry(.device(serial: "C", port: 48160), deviceName: "")

        let list = AppListRows([simulator, phoneA, phoneB, pad, unnamed])

        XCTAssertEqual(list.rows, [
            .group(title: "This Mac", symbol: Theme.Symbol.thisMac),
            .app(simulator),
            .group(title: "Wynn's iPhone · USB", symbol: Theme.Symbol.usbDevice),
            .app(phoneA),
            .app(phoneB),
            .group(title: "iPad Air · USB", symbol: Theme.Symbol.usbDevice),
            .app(pad),
            .group(title: "USB Device · USB", symbol: Theme.Symbol.usbDevice),
            .app(unnamed),
        ])
        XCTAssertEqual(list.appCount, 5)
        XCTAssertEqual(AppListRows().rows, [])
        XCTAssertEqual(AppListRows().appCount, 0)
    }

    func test_C_LIST_01_anAppsTableRowCountsOnlyApps() {
        let first = entry(.simulator(port: 48160))
        let second = entry(.device(serial: "A", port: 48160))
        let list = AppListRows([first, second])

        XCTAssertEqual(list.tableRow(ofApp: 0), 1)
        XCTAssertEqual(list.tableRow(ofApp: 1), 3)
        XCTAssertNil(list.tableRow(ofApp: 2))
    }

    func test_C_LIST_01_theSameAppIsFoundInANewList() {
        let first = entry(.simulator(port: 48160))
        let second = entry(.simulator(port: 48161))
        let before = AppListRows([first, second])
        // A new app ahead of them, and the second one changed.
        var changed = second
        changed.status = .ready(.background)
        let after = AppListRows([entry(.device(serial: "A", port: 48160)), first, changed])

        XCTAssertEqual(after.tableRow(ofSameAppAs: before.rows[2]), 4)
        XCTAssertEqual(after.tableRow(ofSameAppAs: before.rows[1]), 3)
        XCTAssertNil(after.tableRow(ofSameAppAs: before.rows[0]), "a header")
        XCTAssertNil(after.tableRow(ofSameAppAs: nil))
        XCTAssertNil(AppListRows([first]).tableRow(ofSameAppAs: before.rows[2]), "gone")
    }
}
