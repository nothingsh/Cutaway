import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The app list as it is shown: C-LIST-01 to C-LIST-04. Views are checked by their
/// content, not by eye.
final class AppListViewTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")

    private static let simulator = AppLocation.simulator(port: 48160)

    private func session() -> Session {
        Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
    }

    /// The view and every view inside it, depth first.
    @MainActor
    static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants(of:))
    }

    @MainActor
    static func descendant(of view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let match = descendant(of: subview, identifier: identifier) { return match }
        }
        return nil
    }

    @MainActor
    private func label(_ identifier: String, in row: NSView) throws -> NSTextField {
        try XCTUnwrap(Self.descendant(of: row, identifier: identifier) as? NSTextField, identifier)
    }

    // MARK: - C-LIST-01: rows

    @MainActor
    func test_C_LIST_01_aRowShowsTheIcon() throws {
        let pixels = Data([
            0x00, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0xFF,
            0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00,
        ])
        let icon = Bitmap(pixelWidth: 2, pixelHeight: 2, bytesPerRow: 8, scale: 2, pixels: pixels)
        let row = AppRowView()
        row.configure(with: AppEntry(
            id: Self.simulator, info: Self.demo, status: .ready(.active), icon: icon))

        let imageView = try XCTUnwrap(
            Self.descendant(of: row, identifier: AppRowView.Identifier.icon) as? NSImageView)
        let image = try XCTUnwrap(imageView.image)
        // 2 pixels at 2 pixels per point.
        XCTAssertEqual(image.size, NSSize(width: 1, height: 1))
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cgImage.width, 2)
        XCTAssertEqual(cgImage.height, 2)
        let data = try XCTUnwrap(cgImage.dataProvider?.data) as Data
        XCTAssertEqual(data, pixels)

        let placeholder = try XCTUnwrap(
            Self.descendant(of: row, identifier: AppRowView.Identifier.iconPlaceholder))
        XCTAssertTrue(placeholder.isHidden)

        // Without an icon there is no image, and a placeholder stands in.
        row.configure(with: AppEntry(
            id: Self.simulator, info: Self.demo, status: .ready(.active), icon: nil))
        XCTAssertNil(imageView.image)
        XCTAssertFalse(placeholder.isHidden)
    }

    @MainActor
    func test_C_LIST_01_anEmptyBitmapMakesNoImage() {
        let empty = Bitmap(pixelWidth: 0, pixelHeight: 0, bytesPerRow: 0, scale: 1, pixels: Data())
        XCTAssertNil(empty.makeImage())
        // Pixels that are too few for the header are refused rather than read past.
        let short = Bitmap(pixelWidth: 2, pixelHeight: 2, bytesPerRow: 8, scale: 1, pixels: Data(count: 8))
        XCTAssertNil(short.makeImage())
    }

    @MainActor
    func test_C_LIST_01_aRowCopesWithMissingInfo() throws {
        let row = AppRowView()
        let bare = AppInfo(
            name: nil, bundleID: nil, appVersion: nil, deviceName: nil, deviceKind: .unknown,
            isSimulator: false, osName: nil, osVersion: nil, screenSize: nil, screenScale: 0,
            serverVersion: nil)
        row.configure(with: AppEntry(
            id: Self.simulator, info: bare, status: .ready(.active), icon: nil))
        XCTAssertEqual(try label(AppRowView.Identifier.name, in: row).stringValue, "Unnamed app")
        XCTAssertTrue(try label(AppRowView.Identifier.subtitle, in: row).isHidden)

        // Only a system name, or only a device name.
        var partial = bare
        partial.osName = "iOS"
        row.configure(with: AppEntry(
            id: Self.simulator, info: partial, status: .ready(.active), icon: nil))
        XCTAssertEqual(try label(AppRowView.Identifier.subtitle, in: row).stringValue, "iOS")
        partial.deviceName = "iPad"
        partial.osName = nil
        row.configure(with: AppEntry(
            id: Self.simulator, info: partial, status: .ready(.active), icon: nil))
        XCTAssertEqual(try label(AppRowView.Identifier.subtitle, in: row).stringValue, "iPad")

        // No info at all.
        row.configure(with: AppEntry(
            id: Self.simulator, info: nil, status: .ready(.active), icon: nil))
        XCTAssertEqual(try label(AppRowView.Identifier.name, in: row).stringValue, "Unnamed app")
    }

    @MainActor
    func test_C_LIST_01_reloadingTheListDoesNotInspectAgain() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        model.apply(.found(Self.simulator, Self.demo, session()))
        let row = try XCTUnwrap(controller.tableRow(ofApp: 0))
        controller.tableView.selectRowIndexes([row], byExtendingSelection: false)
        controller.choose(row: row)
        XCTAssertEqual(model.inspectedApp, Self.simulator)

        // The user goes back to the list, where the app is selected again (C-LIST-04); then the
        // list changes for an unrelated reason.
        model.leaveInspection()
        XCTAssertEqual(controller.tableView.selectedRow, row)
        model.apply(.stateChanged(Self.simulator, .background))
        model.apply(.found(.simulator(port: 48161), Self.demo, session()))

        XCTAssertNil(model.inspectedApp)
    }

    // MARK: - C-LIST-02: incompatible apps

    @MainActor
    func test_C_LIST_02_anIncompatibleAppCannotBeSelected() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        model.apply(.incompatible(
            Self.simulator, Self.demo, local: Version(major: 0, minor: 1),
            remote: Version(major: 1, minor: 0)))

        let row = try XCTUnwrap(controller.tableRow(ofApp: 0))
        XCTAssertFalse(controller.tableView(controller.tableView, shouldSelectRow: row))
        // Even if it is clicked, nothing opens; and the model would refuse anyway.
        controller.choose(row: row)
        XCTAssertNil(model.inspectedApp)
    }

    // MARK: - C-LIST-04: groups, rows and the keyboard

    private static let phone: AppInfo = {
        var phone = demo
        phone.deviceName = "Wynn's iPhone"
        phone.isSimulator = false
        phone.osVersion = "17.6"
        return phone
    }()

    @MainActor
    private func header(_ row: Int, _ controller: AppListViewController) throws -> AppGroupHeaderView {
        try XCTUnwrap(controller.tableView(controller.tableView, viewFor: nil, row: row) as? AppGroupHeaderView)
    }
}
