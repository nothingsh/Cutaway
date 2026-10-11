import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The app list as it is shown: C-LIST-01, C-LIST-02, C-LIST-03. Views are checked by their
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

    /// Whether `view` is shown: neither it nor any view above it is hidden.
    @MainActor
    private func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    // MARK: - C-LIST-02: the empty state

    @MainActor
    func test_C_LIST_02_anEmptyListShowsAnExplanation() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        let root = controller.view

        let empty = try XCTUnwrap(
            Self.descendant(of: root, identifier: AppListViewController.emptyStateIdentifier))
        XCTAssertTrue(isShown(empty))
        XCTAssertFalse(isShown(controller.tableView))
        let texts = empty.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertEqual(texts.first, "No Apps Found")
        XCTAssertTrue(texts.contains { $0.contains("CutawayServer") })

        model.apply(.found(Self.simulator, Self.demo, session()))
        XCTAssertFalse(isShown(empty))
        XCTAssertTrue(isShown(controller.tableView))
        XCTAssertEqual(controller.appCount, 1)

        model.apply(.lost(Self.simulator))
        XCTAssertTrue(isShown(empty))
        XCTAssertEqual(controller.tableView.numberOfRows, 0)
    }

    // MARK: - C-LIST-01: rows

    @MainActor
    func test_C_LIST_01_aRowShowsNameBundleDeviceAndSystem() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        model.apply(.found(Self.simulator, Self.demo, session()))

        let row = try XCTUnwrap(controller.row(0))
        XCTAssertEqual(try label(AppRowView.Identifier.name, in: row).stringValue, "Demo")
        XCTAssertEqual(
            try label(AppRowView.Identifier.bundle, in: row).stringValue, "dev.cutaway.demo")
        XCTAssertEqual(
            try label(AppRowView.Identifier.device, in: row).stringValue, "iPhone 16 · iOS 18.0")
        XCTAssertEqual(row.alphaValue, 1)
    }

    @MainActor
    func test_C_LIST_01_rowsFollowTheModelsOrder() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        var second = Self.demo
        second.name = "Second"
        model.apply(.found(.simulator(port: 48161), second, session()))
        model.apply(.found(Self.simulator, Self.demo, session()))

        // A header, then the two apps.
        XCTAssertEqual(controller.tableView.numberOfRows, 3)
        XCTAssertEqual(controller.appCount, 2)
        let names = try (0..<2).map { index in
            try label(AppRowView.Identifier.name, in: try XCTUnwrap(controller.row(index))).stringValue
        }
        XCTAssertEqual(names, ["Demo", "Second"])
    }

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
        XCTAssertTrue(try label(AppRowView.Identifier.bundle, in: row).isHidden)
        XCTAssertTrue(try label(AppRowView.Identifier.device, in: row).isHidden)

        // Only a system name, or only a device name.
        var partial = bare
        partial.osName = "iOS"
        row.configure(with: AppEntry(
            id: Self.simulator, info: partial, status: .ready(.active), icon: nil))
        XCTAssertEqual(try label(AppRowView.Identifier.device, in: row).stringValue, "iOS")
        partial.deviceName = "iPad"
        partial.osName = nil
        row.configure(with: AppEntry(
            id: Self.simulator, info: partial, status: .ready(.active), icon: nil))
        XCTAssertEqual(try label(AppRowView.Identifier.device, in: row).stringValue, "iPad")

        // No info at all.
        row.configure(with: AppEntry(
            id: Self.simulator, info: nil, status: .ready(.active), icon: nil))
        XCTAssertEqual(try label(AppRowView.Identifier.name, in: row).stringValue, "Unnamed app")
    }

    @MainActor
    func test_C_LIST_01_aClickOnARowInspectsTheApp() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        model.apply(.found(Self.simulator, Self.demo, session()))
        let row = try XCTUnwrap(controller.tableRow(ofApp: 0))

        controller.choose(row: row)

        XCTAssertEqual(model.inspectedApp, Self.simulator)
        // The click is the table's action.
        XCTAssertTrue(controller.tableView.target === controller)
        XCTAssertNotNil(controller.tableView.action)
    }

    @MainActor
    func test_C_LIST_01_returnInspectsTheSelectedAppAndTheArrowsOnlySelect() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        model.apply(.found(Self.simulator, Self.demo, session()))
        let row = try XCTUnwrap(controller.tableRow(ofApp: 0))

        // Moving the selection, as the arrow keys do, opens nothing.
        controller.tableView.selectRowIndexes([row], byExtendingSelection: false)
        XCTAssertNil(model.inspectedApp)

        let returnKey = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
            keyCode: 36))
        controller.tableView.keyDown(with: returnKey)
        XCTAssertEqual(model.inspectedApp, Self.simulator)
    }

    @MainActor
    func test_C_LIST_01_aChosenAppGoesToWhoeverAskedForIt() throws {
        let model = AppListStore()
        var chosen: [AppLocation] = []
        let controller = AppListViewController(store: model, onChoose: { chosen.append($0) })
        _ = controller.view
        model.apply(.found(Self.simulator, Self.demo, session()))

        controller.choose(row: try XCTUnwrap(controller.tableRow(ofApp: 0)))

        XCTAssertEqual(chosen, [Self.simulator])
        XCTAssertNil(model.inspectedApp, "the model was told directly")
    }

    @MainActor
    func test_C_LIST_01_appsAreGroupedByWhereTheyRun() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        var phone = Self.demo
        phone.deviceName = "Wynn's iPhone"
        phone.isSimulator = false
        var pad = Self.demo
        pad.deviceName = "iPad Air"
        pad.isSimulator = false
        model.apply(.found(.device(serial: "B", port: 48160), pad, session()))
        model.apply(.found(.device(serial: "A", port: 48161), phone, session()))
        model.apply(.found(.device(serial: "A", port: 48160), phone, session()))
        model.apply(.found(Self.simulator, Self.demo, session()))

        let headers = controller.rows.compactMap { row -> String? in
            if case .group(let title, _) = row { return title } else { return nil }
        }
        XCTAssertEqual(headers, ["This Mac", "Wynn's iPhone · USB", "iPad Air · USB"])
        XCTAssertEqual(controller.rows.count, 7)
        XCTAssertEqual(controller.appCount, 4)
        // A header is not a choice.
        XCTAssertFalse(controller.tableView(controller.tableView, shouldSelectRow: 0))
        controller.choose(row: 0)
        XCTAssertNil(model.inspectedApp)
        let header = try XCTUnwrap(controller.tableView(
            controller.tableView, viewFor: nil, row: 0) as? AppGroupHeaderView)
        XCTAssertEqual(try label(AppListViewController.groupIdentifier, in: header).stringValue,
                       "This Mac")
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

        // The user goes back to the list; then the list changes for an unrelated reason.
        model.leaveInspection()
        XCTAssertEqual(controller.tableView.selectedRow, -1, "the row stayed selected")
        model.apply(.stateChanged(Self.simulator, .background))
        model.apply(.found(.simulator(port: 48161), Self.demo, session()))

        XCTAssertNil(model.inspectedApp)
    }

    // MARK: - C-LIST-03

    @MainActor
    func test_C_LIST_03_appsThatAreNotActiveCarryAMark() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        model.apply(.found(Self.simulator, Self.demo, session()))

        func badge() throws -> StatusCapsule {
            try XCTUnwrap(controller.row(0)).badge
        }
        XCTAssertTrue(try badge().isHidden)
        XCTAssertEqual(
            try XCTUnwrap(controller.row(0)).badge.accessibilityIdentifier(),
            AppRowView.Identifier.badge)

        model.apply(.stateChanged(Self.simulator, .inactive))
        XCTAssertFalse(try badge().isHidden)
        XCTAssertEqual(try badge().text, "Inactive")
        XCTAssertEqual(try badge().kind?.color, .systemOrange)

        model.apply(.stateChanged(Self.simulator, .background))
        XCTAssertFalse(try badge().isHidden)
        XCTAssertEqual(try badge().text, "In Background")

        model.apply(.stateChanged(Self.simulator, .active))
        XCTAssertTrue(try badge().isHidden)
    }

    // MARK: - C-LIST-02: incompatible apps

    @MainActor
    func test_C_LIST_02_anIncompatibleAppIsListedDimmedWithBothVersions() throws {
        let model = AppListStore()
        let controller = AppListViewController(store: model)
        _ = controller.view
        model.apply(.incompatible(
            Self.simulator, Self.demo, local: Version(major: 0, minor: 1),
            remote: Version(major: 1, minor: 3)))

        XCTAssertEqual(controller.appCount, 1)
        let row = try XCTUnwrap(controller.row(0))
        XCTAssertEqual(try label(AppRowView.Identifier.name, in: row).stringValue, "Demo")
        XCTAssertEqual(row.badge.text, "Incompatible")
        XCTAssertFalse(row.badge.isHidden)
        let note = try label(AppRowView.Identifier.compatibility, in: row)
        XCTAssertFalse(note.isHidden)
        XCTAssertTrue(note.stringValue.contains("1.3"), note.stringValue)
        XCTAssertTrue(note.stringValue.contains("0.1"), note.stringValue)
        XCTAssertLessThan(row.alphaValue, 1)

        // A compatible app has no such note.
        model.apply(.found(Self.simulator, Self.demo, session()))
        let ready = try XCTUnwrap(controller.row(0))
        XCTAssertTrue(try label(AppRowView.Identifier.compatibility, in: ready).isHidden)
        XCTAssertEqual(ready.alphaValue, 1)
    }

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
}
