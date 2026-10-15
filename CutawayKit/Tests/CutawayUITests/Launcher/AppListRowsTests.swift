import CutawayModel
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The app list's rows, without the table: C-LIST-01, C-LIST-04.
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
        // A new app ahead of them, and the second one changed.
        var changed = second
        changed.status = .ready(.background)
        let after = AppListRows([entry(.device(serial: "A", port: 48160)), first, changed])

        XCTAssertEqual(after.choosableRow(of: second.id), 4)
        XCTAssertEqual(after.choosableRow(of: first.id), 3)
        XCTAssertNil(AppListRows([first]).choosableRow(of: second.id), "gone")
        XCTAssertNil(
            AppListRows([incompatible(second.id)]).choosableRow(of: second.id), "not a choice")
    }

    // MARK: - C-LIST-04: the keyboard

    private func incompatible(_ id: AppLocation) -> AppEntry {
        AppEntry(
            id: id, info: Self.demo,
            status: .incompatible(local: Version(major: 1, minor: 1), remote: Version(major: 2, minor: 0)),
            icon: nil)
    }
}
