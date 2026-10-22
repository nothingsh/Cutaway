import AppKit
import CutawayModel
import CutawayProjects
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// C-SRC-01: linking a folder from an inspector or archive window, a folder that is gone,
/// the Projects page, and that nothing is written into the folder.
@MainActor
final class LinkProjectFolderTests: XCTestCase {
    private var suiteName = ""
    private var builders: [ProjectBuilder] = []
    private var directory: URL?

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        for builder in builders {
            builder.remove()
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func sources() throws -> ProjectSources {
        suiteName = "LinkProjectFolderTests.\(UUID().uuidString)"
        return ProjectSources(folders: ProjectFolders(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))))
    }

    private func sample(_ name: String = "Project") throws -> ProjectBuilder {
        let builder = try ProjectBuilder(name: name)
        builders.append(builder)
        try SampleProject.write(into: builder)
        return builder
    }

    private func inspector(_ sources: ProjectSources, bundleID: String? = "dev.cutaway.demo") throws
        -> InspectorWindowController
    {
        var info = OpenInXcodeTests.demo
        info.bundleID = bundleID
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")))
        model.apply(try Fixtures.hierarchy())
        let inspector = InspectorWindowController(
            location: .simulator(port: 48160),
            entry: AppEntry(id: .simulator(port: 48160), info: info, status: .ready(.active), icon: nil),
            store: model, projects: sources)
        addTeardownBlock { @MainActor in inspector.close() }
        return inspector
    }

    private func linkItem() -> NSMenuItem {
        NSMenuItem(title: "", action: #selector(InspectorWindowController.linkProjectFolder(_:)), keyEquivalent: "")
    }

    func test_C_SRC_01_linkProjectFolderLinksTheWindowsApp() async throws {
        let sources = try sources()
        let project = try sample()
        let inspector = try inspector(sources)
        inspector.showWindow(nil)
        var started: [URL?] = []
        inspector.fileActions.chooseProjectFolder = { _, appName, start, link in
            XCTAssertEqual(appName, "Demo")
            started.append(start)
            link(project.root)
        }
        let item = linkItem()
        XCTAssertTrue(inspector.validateMenuItem(item))
        inspector.linkProjectFolder(item)
        XCTAssertEqual(sources.folders.link(for: "dev.cutaway.demo")?.path, project.root.path)
        XCTAssertEqual(sources.folders.link(for: "dev.cutaway.demo")?.appName, "Demo")
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        XCTAssertNotNil(sources.indexes["dev.cutaway.demo"]?.declarations["HomeViewController"])

        // Again: the panel starts at the folder, which the item names.
        XCTAssertTrue(inspector.validateMenuItem(item))
        XCTAssertEqual(item.toolTip, project.root.path)
        if #available(macOS 14.4, *) { XCTAssertEqual(item.subtitle, "Project") }
        inspector.linkProjectFolder(item)
        XCTAssertEqual(started, [nil, URL(fileURLWithPath: project.root.path, isDirectory: true)])
    }

    func test_C_SRC_01_anAppWithoutABundleIDCannotLinkAFolder() throws {
        let inspector = try inspector(try sources(), bundleID: nil)
        inspector.fileActions.chooseProjectFolder = { _, _, _, _ in XCTFail("asked for a folder") }
        XCTAssertFalse(inspector.validateMenuItem(linkItem()))
        inspector.linkProjectFolder(nil)
    }

    func test_C_SRC_01_anArchiveFindsTheFolderByTheBundleIDItWasSavedFrom() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinkProjectFolderTests-\(UUID().uuidString)")
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Demo.cutaway")
        try Fixtures.archive().write(to: url)
        let sources = try sources()
        let project = try sample()
        // Linked from the app's window before: the archive of the same app finds it.
        sources.link(project.root, bundleID: "dev.cutaway.demo", appName: "Demo")
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        let coordinator = WindowCoordinator(store: AppListStore(), discoversDevices: false, projects: sources)
        coordinator.recents = MemoryRecentArchives()
        let opened = await coordinator.openArchive(url)
        let archive = try XCTUnwrap(opened)
        addTeardownBlock { @MainActor in archive.close() }
        XCTAssertTrue(archive.isArchive)
        XCTAssertEqual(archive.project.bundleID, "dev.cutaway.demo")
        XCTAssertEqual(archive.project.linkedFolder?.path, project.root.path)
        XCTAssertTrue(archive.validateMenuItem(linkItem()))
        XCTAssertNotNil(archive.project.currentIndex?.declarations["HomeViewController"])
    }

    func test_C_SRC_01_aMissingFolderIsToldOfOnTheFirstWindowOnly() async throws {
        let sources = try sources()
        let project = try sample()
        sources.link(project.root, bundleID: "dev.cutaway.demo", appName: "Demo")
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        let path = project.root.path
        try FileManager.default.removeItem(at: project.root)

        var told: [(String, String)] = []
        var chosen = 0
        let first = try inspector(sources)
        first.fileActions.tellOfMissingFolder = { _, appName, path, chooseAgain in
            told.append((appName, path))
            chooseAgain()
        }
        first.fileActions.chooseProjectFolder = { _, _, _, _ in chosen += 1 }
        first.showWindow(nil)
        XCTAssertEqual(told.map(\.0), ["Demo"])
        XCTAssertEqual(told.map(\.1), [path])
        XCTAssertEqual(chosen, 1, "Choose Again offers the folder panel")
        XCTAssertNil(sources.indexes["dev.cutaway.demo"])

        // Read as not linked, but kept; told of once since Cutaway opened.
        let second = try inspector(sources)
        second.fileActions.tellOfMissingFolder = { _, appName, path, _ in told.append((appName, path)) }
        second.showWindow(nil)
        second.refresh(nil)
        XCTAssertEqual(told.count, 1)
        XCTAssertNotNil(sources.folders.link(for: "dev.cutaway.demo"))
    }

    func test_C_SRC_02_openingAWindowAndRefreshingUpdateTheIndex() async throws {
        let sources = try sources()
        let project = try sample()
        sources.link(project.root, bundleID: "dev.cutaway.demo", appName: "Demo")
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        let files = try XCTUnwrap(sources.reports["dev.cutaway.demo"]).read

        try project.write("Shop/Opened.swift", "class Opened {}")
        let inspector = try inspector(sources)
        inspector.showWindow(nil)
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        XCTAssertEqual(sources.reports["dev.cutaway.demo"], ProjectIndexReport(read: 1, reused: files))

        try project.write("Shop/Refreshed.swift", "class Refreshed {}")
        inspector.refresh(nil)
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        XCTAssertEqual(sources.reports["dev.cutaway.demo"], ProjectIndexReport(read: 1, reused: files + 1))
        XCTAssertNotNil(sources.indexes["dev.cutaway.demo"]?.declarations["Refreshed"])
    }

    func test_C_SRC_01_nothingIsWrittenIntoTheFolder() async throws {
        let sources = try sources()
        let project = try sample()
        let before = FolderSnapshot(project.root)
        XCTAssertGreaterThan(before.files.count, 20)

        // Linked from a window, indexed, a class looked up and opened, refreshed, and the
        // Projects page shown.
        let inspector = try inspector(sources)
        inspector.showWindow(nil)
        inspector.fileActions.chooseProjectFolder = { _, _, _, link in link(project.root) }
        inspector.linkProjectFolder(nil)
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        let recorder = LaunchRecorder()
        inspector.project.opener = recorder.opener(xcode: URL(fileURLWithPath: "/Applications/Xcode.app"))
        let locations = try XCTUnwrap(sources.indexes["dev.cutaway.demo"]).locations(ofClass: "HomeViewController")
        inspector.project.open(locations)
        XCTAssertEqual(recorder.runs.count, 1)
        inspector.refresh(nil)
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        let page = ProjectsSettingsViewController(projects: sources)
        page.loadView()
        page.reload()

        XCTAssertEqual(FolderSnapshot(project.root), before)
    }
}

/// C-SRC-01: the settings' Projects page lists the linked apps, changes and removes them.
@MainActor
final class ProjectsSettingsPageTests: XCTestCase {
    private var suiteName = ""
    private var builders: [ProjectBuilder] = []

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        for builder in builders {
            builder.remove()
        }
    }

    private func folder(_ name: String) throws -> ProjectBuilder {
        let builder = try ProjectBuilder(name: name)
        builders.append(builder)
        return builder
    }

    private func page() throws -> (ProjectsSettingsViewController, ProjectSources, SettingsWindowController) {
        suiteName = "ProjectsSettingsPageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let sources = ProjectSources(folders: ProjectFolders(defaults: defaults))
        let window = SettingsWindowController(
            settings: AppSettings(defaults: defaults),
            language: WindowCoordinator.languageSetting(defaults: defaults, domain: suiteName),
            projects: sources, shownLanguage: "en", systemPreferences: { [] }, restart: {})
        addTeardownBlock { @MainActor in window.close() }
        window.tabs.selectedTabViewItemIndex = 2
        window.showWindow(nil)
        return (window.projectsPage, sources, window)
    }

    private func texts(_ page: ProjectsSettingsViewController, row: Int) -> [String] {
        (0..<page.table.numberOfColumns).compactMap {
            (page.table.view(atColumn: $0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue
        }
    }

    func test_C_SRC_01_theProjectsPageListsTheLinkedApps() throws {
        let (page, sources, window) = try page()
        XCTAssertEqual(window.window?.title, "Projects")
        XCTAssertEqual(page.table.numberOfRows, 0)
        XCTAssertFalse(try XCTUnwrap(LinkProjectFolderTests
                .view(page.view, ProjectsSettingsViewController.emptyIdentifier)).isHidden)

        let shop = try folder("Shop")
        let notes = try folder("Notes")
        sources.link(shop.root, bundleID: "com.example.shop", appName: "Shop")
        sources.link(notes.root, bundleID: "com.example.notes", appName: "Field Notes")
        page.reload()
        XCTAssertEqual(page.table.numberOfRows, 2)
        XCTAssertEqual(
            texts(page, row: 0),
            ["Field Notes", "com.example.notes", (notes.root.path as NSString).abbreviatingWithTildeInPath])
        XCTAssertEqual(texts(page, row: 1).prefix(2), ["Shop", "com.example.shop"])
        XCTAssertTrue(try XCTUnwrap(LinkProjectFolderTests
                .view(page.view, ProjectsSettingsViewController.emptyIdentifier)).isHidden)

        // A folder that is gone says so, with its path in the tooltip.
        try FileManager.default.removeItem(at: notes.root)
        page.reload()
        let cell = page.table.view(atColumn: 2, row: 0, makeIfNecessary: true) as? NSTableCellView
        XCTAssertEqual(cell?.textField?.stringValue.hasSuffix("Can\u{2019}t find"), true)
        XCTAssertEqual(cell?.textField?.toolTip, notes.root.path)
    }

    func test_C_SRC_01_aFolderIsChangedAndRemovedFromThePage() async throws {
        let (page, sources, _) = try page()
        let shop = try folder("Shop")
        let notes = try folder("Notes")
        let other = try folder("Other")
        sources.link(shop.root, bundleID: "com.example.shop", appName: "Shop")
        sources.link(notes.root, bundleID: "com.example.notes", appName: "Field Notes")
        page.reload()
        XCTAssertFalse(page.changeButton.isEnabled)
        XCTAssertFalse(page.removeButton.isEnabled)

        page.table.selectRowIndexes([1], byExtendingSelection: false)
        XCTAssertTrue(page.changeButton.isEnabled)
        var started: [URL?] = []
        page.chooseFolder = { _, appName, start, link in
            XCTAssertEqual(appName, "Shop")
            started.append(start)
            link(other.root)
        }
        page.changeButton.performClick(nil)
        XCTAssertEqual(started.first??.path, shop.root.path)
        XCTAssertEqual(sources.folders.link(for: "com.example.shop")?.path, other.root.path)
        await sources.waitForIndex(bundleID: "com.example.shop")
        XCTAssertNotNil(sources.indexes["com.example.shop"])

        // Both selected: Change… is off, Remove forgets both, and their indexes.
        page.reload()
        page.table.selectRowIndexes([0, 1], byExtendingSelection: false)
        XCTAssertFalse(page.changeButton.isEnabled)
        page.removeButton.performClick(nil)
        XCTAssertEqual(sources.folders.links, [])
        XCTAssertNil(sources.indexes["com.example.shop"])
        page.reload()
        XCTAssertEqual(page.table.numberOfRows, 0)
    }
}

extension LinkProjectFolderTests {
    static func view(_ root: NSView, _ identifier: String) -> NSView? {
        OpenInXcodeTests.views(in: root, identifier: identifier).first
    }
}
