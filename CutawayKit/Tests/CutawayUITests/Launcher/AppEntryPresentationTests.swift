import CutawayModel
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// What a row of the app list says about an app, without the row: C-LIST-01, C-LIST-02,
/// C-LIST-03.
final class AppEntryPresentationTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")

    private static let bare = AppInfo(
        name: nil, bundleID: nil, appVersion: nil, deviceName: nil, deviceKind: .unknown,
        isSimulator: false, osName: nil, osVersion: nil, screenSize: nil, screenScale: 0,
        serverVersion: nil)

    private func entry(_ info: AppInfo?, _ status: AppEntry.Status = .ready(.active)) -> AppEntry {
        AppEntry(id: .simulator(port: 48160), info: info, status: status, icon: nil)
    }

    func test_C_LIST_01_anAppIsShownByNameVersionBundleAndDevice() {
        let shown = AppEntryPresentation(entry(Self.demo))
        XCTAssertEqual(shown.name, "Demo")
        XCTAssertEqual(shown.version, "1.0")
        XCTAssertEqual(shown.bundleID, "dev.cutaway.demo")
        XCTAssertEqual(shown.deviceLine, "iPhone 16 · iOS 18.0")
        XCTAssertEqual(shown.deviceSymbolName, Theme.Symbol.phone)
        XCTAssertNil(shown.badge)
        XCTAssertNil(shown.compatibility)
        XCTAssertFalse(shown.isDimmed)
    }

    func test_C_LIST_01_missingInfoLeavesItsPartsOut() {
        let bare = AppEntryPresentation(entry(Self.bare))
        XCTAssertEqual(bare.name, "Unnamed app")
        XCTAssertNil(bare.version)
        XCTAssertNil(bare.bundleID)
        XCTAssertNil(bare.deviceLine)
        XCTAssertEqual(bare.deviceSymbolName, Theme.Symbol.unknownDevice)
        XCTAssertEqual(AppEntryPresentation(entry(nil)).name, "Unnamed app")

        // An empty name is no name.
        var empty = Self.bare
        empty.name = ""
        XCTAssertEqual(AppEntryPresentation.name(of: empty), "Unnamed app")

        // Only a system name, or only a device name.
        var partial = Self.bare
        partial.osName = "iOS"
        XCTAssertEqual(AppEntryPresentation.deviceLine(partial), "iOS")
        partial.deviceName = "iPad"
        partial.osName = nil
        XCTAssertEqual(AppEntryPresentation.deviceLine(partial), "iPad")
    }

    func test_C_LIST_01_eachKindOfDeviceHasItsSymbol() {
        XCTAssertEqual(AppEntryPresentation.deviceSymbolName(.phone), Theme.Symbol.phone)
        XCTAssertEqual(AppEntryPresentation.deviceSymbolName(.pad), Theme.Symbol.pad)
        XCTAssertEqual(AppEntryPresentation.deviceSymbolName(.mac), Theme.Symbol.mac)
        XCTAssertEqual(AppEntryPresentation.deviceSymbolName(.unknown), Theme.Symbol.unknownDevice)
        XCTAssertEqual(AppEntryPresentation.deviceSymbolName(nil), Theme.Symbol.unknownDevice)
    }

    func test_C_LIST_02_anIncompatibleAppIsDimmedWithBothVersions() {
        let shown = AppEntryPresentation(entry(
            Self.demo,
            .incompatible(local: Version(major: 0, minor: 1), remote: Version(major: 1, minor: 3))))
        XCTAssertEqual(shown.name, "Demo")
        XCTAssertEqual(shown.badge, .incompatible)
        XCTAssertEqual(shown.badge?.text, "Incompatible")
        XCTAssertEqual(
            shown.compatibility,
            "Speaks protocol 1.3; this Cutaway speaks 0.1. It cannot be inspected.")
        XCTAssertTrue(shown.isDimmed)
    }

    func test_C_LIST_03_appsThatAreNotActiveCarryAMark() {
        XCTAssertNil(AppEntryPresentation(entry(Self.demo, .ready(.active))).badge)
        let inactive = AppEntryPresentation(entry(Self.demo, .ready(.inactive)))
        XCTAssertEqual(inactive.badge, .inactive)
        XCTAssertEqual(inactive.badge?.text, "Inactive")
        XCTAssertEqual(inactive.badge?.symbol, Theme.Symbol.inactive)
        let background = AppEntryPresentation(entry(Self.demo, .ready(.background)))
        XCTAssertEqual(background.badge, .background)
        XCTAssertEqual(background.badge?.text, "In Background")
        XCTAssertEqual(background.badge?.symbol, Theme.Symbol.background)
        XCTAssertFalse(background.isDimmed)
    }
}
