import CutawayWire
import XCTest

@testable import CutawayUI

/// What an inspector window's title bar says, and the names of the files saved from it:
/// C-WIN-01, C-ARCH-02, C-ARCH-05, C-ARCH-06.
final class InspectorWindowTitleTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")

    func test_C_WIN_01_anAppsWindowIsTitledByTheAppAndItsDevice() {
        let title = InspectorWindowTitle(app: Self.demo)
        XCTAssertEqual(title.title, "Demo")
        XCTAssertEqual(title.subtitle, "iPhone 16 · iOS 18.0")

        let unknown = InspectorWindowTitle(app: nil)
        XCTAssertEqual(unknown.title, "Unnamed app")
        XCTAssertEqual(unknown.subtitle, "")
    }

    func test_C_ARCH_05_anArchivesWindowIsTitledByItsFile() {
        let url = URL(fileURLWithPath: "/tmp/Demo.cutaway")
        let savedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let title = InspectorWindowTitle(archive: url, app: Self.demo, savedAt: savedAt)
        XCTAssertEqual(title.title, "Demo")
        XCTAssertEqual(
            title.subtitle,
            "Demo \u{00B7} iPhone 16 \u{00B7} iOS 18.0 \u{00B7} Saved "
                + savedAt.formatted(date: .abbreviated, time: .shortened))

        // Without a device line, the parts that are known.
        var bare = Self.demo
        bare.name = nil
        bare.deviceName = nil
        bare.osName = nil
        bare.osVersion = nil
        XCTAssertTrue(
            InspectorWindowTitle(archive: url, app: bare, savedAt: savedAt).subtitle
                .hasPrefix("Unnamed app \u{00B7} Saved "))
    }

    func test_C_ARCH_02_anArchiveIsOfferedTheAppsNameAndTheTime() throws {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 10, 9)
        (components.hour, components.minute, components.second) = (14, 5, 59)
        let date = try XCTUnwrap(Calendar.current.date(from: components))
        XCTAssertEqual(
            InspectorWindowTitle.archiveName(appName: "Demo", at: date), "Demo 2026-10-09 14.05")
    }

    func test_C_ARCH_06_aScreenshotIsOfferedTheLayersTitleAndID() {
        XCTAssertEqual(
            InspectorWindowTitle.screenshotName(title: "CardView", layerID: 4, kind: .solo),
            "CardView 4")
        XCTAssertEqual(
            InspectorWindowTitle.screenshotName(title: "CALayer", layerID: 8, kind: .group),
            "CALayer 8 with Sublayers")
    }
}
