import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-SRC-06: Copy LLDB Command, in the Edit menu and in a layer's context menu, on a pasteboard
/// of the test's own.
@MainActor
final class LLDBMenuTests: XCTestCase {
    private let pasteboard = NSPasteboard.withUniqueName()

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private func inspector(_ hierarchy: Hierarchy) throws -> InspectorWindowController {
        let session = Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        let model = InspectionStore(session: session)
        model.apply(hierarchy)
        let inspector = InspectorWindowController(location: .simulator(port: 48160), entry: nil, store: model)
        inspector.pasteboard = pasteboard
        addTeardownBlock { @MainActor in inspector.close() }
        return inspector
    }

    private func item(_ action: Selector, for id: UInt64? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.representedObject = id
        return item
    }

    private static let print = #selector(InspectorWindowController.copyLLDBPrintCommand(_:))
    private static let breakpoints = #selector(InspectorWindowController.copyLLDBFrameBreakpoints(_:))

    func test_C_SRC_06_theEditMenuCopiesTheSelectedLayersCommands() throws {
        let inspector = try inspector(try Fixtures.hierarchy())
        inspector.store.select(3)
        XCTAssertTrue(inspector.validateMenuItem(item(Self.print)))
        XCTAssertTrue(inspector.validateMenuItem(item(Self.breakpoints)))

        inspector.copyLLDBPrintCommand(item(Self.print))
        XCTAssertEqual(pasteboard.string(forType: .string), "expr -l objc -O -- (id)0x103806e00")
        inspector.copyLLDBFrameBreakpoints(item(Self.breakpoints))
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            """
            breakpoint set -n "-[CALayer setPosition:]" -c '(void *)$arg1 == (void *)0x600003b4c080'
            breakpoint set -n "-[CALayer setBounds:]" -c '(void *)$arg1 == (void *)0x600003b4c080'
            """)

        // The Edit menu has the submenu, whose items go to the window.
        let edit = MainMenuBuilder(coordinator: WindowCoordinator(store: AppListStore(), discoversDevices: false))
            .makeMainMenu().items.first { $0.title == "Edit" }?.submenu
        let lldb = try XCTUnwrap(edit?.items.first { $0.identifier == LLDBMenu.identifier }?.submenu)
        XCTAssertEqual(lldb.items.map(\.title), ["Print Object", "Stop When the Frame Changes"])
        XCTAssertEqual(lldb.items.map(\.action), [Self.print, Self.breakpoints])
        XCTAssertTrue(lldb.items.allSatisfy { $0.target == nil && $0.representedObject == nil })
    }

    func test_C_SRC_06_withoutAddressesNothingCanBeCopied() throws {
        let inspector = try inspector(Fixtures.withoutProtocol11(try Fixtures.hierarchy()))
        inspector.store.select(3)
        XCTAssertFalse(inspector.validateMenuItem(item(Self.print)))
        XCTAssertFalse(inspector.validateMenuItem(item(Self.breakpoints)))
        pasteboard.clearContents()
        inspector.copyLLDBPrintCommand(nil)
        XCTAssertNil(pasteboard.string(forType: .string), "nothing copied")
        // Nothing selected.
        inspector.store.select(nil)
        let full = try self.inspector(try Fixtures.hierarchy())
        XCTAssertFalse(full.validateMenuItem(item(Self.print)))

        // The layer's context menu has no such item.
        let menu = NSMenu()
        inspector.splitController.hierarchyController.layerMenu.fill(menu, for: 3)
        XCTAssertNil(menu.items.first { $0.identifier == LLDBMenu.identifier })
    }

    func test_C_SRC_06_theContextMenuCopiesForItsLayer() throws {
        let inspector = try inspector(try Fixtures.hierarchy())
        inspector.store.select(4)
        let menu = NSMenu()
        inspector.splitController.hierarchyController.layerMenu.fill(menu, for: 3)
        let lldb = try XCTUnwrap(menu.items.first { $0.identifier == LLDBMenu.identifier }?.submenu)
        XCTAssertEqual(lldb.items.compactMap { $0.representedObject as? UInt64 }, [3, 3])
        let printItem = try XCTUnwrap(lldb.items.first)
        XCTAssertTrue(inspector.validateMenuItem(printItem))
        inspector.copyLLDBPrintCommand(printItem)
        XCTAssertEqual(
            pasteboard.string(forType: .string), "expr -l objc -O -- (id)0x103806e00",
            "the row's layer, not the selected one")

        // A layer with no view prints its layer; it has a layer to stop on too.
        inspector.splitController.hierarchyController.layerMenu.fill(menu, for: 5)
        let five = try XCTUnwrap(menu.items.first { $0.identifier == LLDBMenu.identifier }?.submenu)
        XCTAssertTrue(five.items.allSatisfy { inspector.validateMenuItem($0) })
    }

    func test_C_SRC_06_anArchivesAddressesAreFromWhenItWasSaved() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLDBMenuTests-\(UUID().uuidString).cutaway")
        try Fixtures.archive().write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let coordinator = WindowCoordinator(store: AppListStore(), discoversDevices: false)
        coordinator.recents = MemoryRecentArchives()
        let opened = await coordinator.openArchive(url)
        let archive = try XCTUnwrap(opened)
        addTeardownBlock { @MainActor in archive.close() }
        let loaded = await Wait.until { await archive.store.loadState == .loaded }
        XCTAssertTrue(loaded)
        archive.pasteboard = pasteboard
        archive.store.expandAll()
        archive.store.select(3)

        let printItem = item(Self.print)
        XCTAssertTrue(archive.validateMenuItem(printItem))
        let note = "Addresses are from when the archive was saved"
        if #available(macOS 14.4, *) {
            XCTAssertEqual(printItem.subtitle, note)
        } else {
            XCTAssertEqual(printItem.toolTip, note)
        }
        archive.copyLLDBPrintCommand(printItem)
        XCTAssertEqual(pasteboard.string(forType: .string), "expr -l objc -O -- (id)0x103806e00")

        // An app's window says nothing of the kind.
        let live = try inspector(try Fixtures.hierarchy())
        live.store.select(3)
        let liveItem = item(Self.print)
        XCTAssertTrue(live.validateMenuItem(liveItem))
        if #available(macOS 14.4, *) { XCTAssertNil(liveItem.subtitle) }
    }
}
