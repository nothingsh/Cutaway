import AppKit
import CutawayModel
import CutawayProjects
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayProjects
@testable import CutawayUI

/// What an Open in Xcode would run, recorded instead of run.
@MainActor
final class LaunchRecorder {
    struct Run: Equatable {
        var executable: URL
        var arguments: [String]
        var developerDir: String?
    }

    var runs: [Run] = []
    var opened: [URL] = []
    /// The exit status each run ends with; nil throws as a program that cannot start does.
    var status: Int32? = 0

    /// An opener with this Xcode, or none, whose steps are recorded.
    func opener(xcode: URL?, hasXed: Bool = true) -> XcodeOpener {
        var opener = XcodeOpener()
        opener.locateXcode = { xcode }
        opener.isExecutable = { _ in hasXed }
        opener.run = { [weak self] executable, arguments, environment, ended in
            guard let self else { return }
            self.runs.append(Run(
                executable: executable, arguments: arguments, developerDir: environment["DEVELOPER_DIR"]))
            guard let status = self.status else { throw CocoaError(.executableNotLoadable) }
            ended(status)
        }
        opener.openFile = { [weak self] in self?.opened.append($0) }
        return opener
    }
}

/// C-SRC-03: Xcode's own `xed` at the line, and the file in its default app without it.
@MainActor
final class XcodeOpenerTests: XCTestCase {
    private let xcode = URL(fileURLWithPath: "/Applications/Xcode-beta.app", isDirectory: true)
    private let location = SourceLocation(
        file: URL(fileURLWithPath: "/Users/someone/Shop/Home/HomeViewController.swift"), line: 12,
        folder: "Home")

    func test_C_SRC_03_openingRunsXcodesOwnXedAtTheLine() {
        let recorder = LaunchRecorder()
        recorder.opener(xcode: xcode).open(location)
        XCTAssertEqual(recorder.runs, [
            .init(
                executable: URL(fileURLWithPath: "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xed"),
                arguments: ["--line", "12", "/Users/someone/Shop/Home/HomeViewController.swift"],
                developerDir: "/Applications/Xcode-beta.app/Contents/Developer"),
        ])
        XCTAssertEqual(recorder.opened, [])
    }

    func test_C_SRC_03_withoutXcodeTheFileOpensInItsDefaultApp() {
        let recorder = LaunchRecorder()
        recorder.opener(xcode: nil).open(location)
        XCTAssertEqual(recorder.runs, [])
        XCTAssertEqual(recorder.opened, [location.file])
    }

    func test_C_SRC_03_withoutXedOrWhenItFailsTheFileOpensInItsDefaultApp() {
        let missing = LaunchRecorder()
        missing.opener(xcode: xcode, hasXed: false).open(location)
        XCTAssertEqual(missing.runs, [])
        XCTAssertEqual(missing.opened, [location.file])

        let failing = LaunchRecorder()
        failing.status = 1
        failing.opener(xcode: xcode).open(location)
        XCTAssertEqual(failing.runs.count, 1)
        XCTAssertEqual(failing.opened, [location.file])

        let unstartable = LaunchRecorder()
        unstartable.status = nil
        unstartable.opener(xcode: xcode).open(location)
        XCTAssertEqual(unstartable.opened, [location.file])
    }

    func test_C_SRC_03_theDefaultLauncherReportsTheExitStatus() async throws {
        // The real way of running a program, on one that is always there.
        var opener = XcodeOpener()
        var opened: [URL] = []
        opener.locateXcode = { URL(fileURLWithPath: "/", isDirectory: true) }
        opener.isExecutable = { _ in true }
        let run = opener.run
        opener.run = { _, arguments, environment, ended in
            try run(URL(fileURLWithPath: "/usr/bin/false"), arguments, environment, ended)
        }
        opener.openFile = { opened.append($0) }
        opener.open(location)
        let deadline = Date().addingTimeInterval(5)
        while opened.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(opened, [location.file], "a program that fails falls back to the file")
    }
}

/// C-SRC-03: where Open in Xcode shows for the selected layer, and what it opens.
@MainActor
final class OpenInXcodeTests: XCTestCase {
    static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "1.1.0")

    private var suiteName = ""
    private var builder: ProjectBuilder?

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        builder?.remove()
    }

    /// Sources whose folders are kept in a domain of this test's own.
    private func sources() throws -> ProjectSources {
        suiteName = "OpenInXcodeTests.\(UUID().uuidString)"
        return ProjectSources(folders: ProjectFolders(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))))
    }

    /// A project for the `hierarchy` fixture: its view controller once, its card view twice,
    /// and the system's classes, which are never looked for.
    private func project() throws -> ProjectBuilder {
        let builder = try ProjectBuilder()
        self.builder = builder
        try builder.write("Demo/Home/HomeViewController.swift", "import UIKit\n\nfinal class HomeViewController {}\n")
        try builder.write("Demo/Cards/CardView.swift", "class CardView {}\n")
        try builder.write("Legacy/CardView.swift", "\n\nclass CardView {}\n")
        try builder.write("Demo/System.swift", "class UIView {}\nclass CALayer {}\nclass UILabel {}\n")
        return builder
    }

    /// A live inspector of the fixtures' tree, for an app with a bundle ID.
    private func inspector(
        _ sources: ProjectSources, info: AppInfo? = OpenInXcodeTests.demo
    ) throws -> InspectorWindowController {
        let session = Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        let model = InspectionStore(session: session)
        model.apply(try Fixtures.hierarchy())
        let entry = info.map { AppEntry(id: .simulator(port: 48160), info: $0, status: .ready(.active), icon: nil) }
        let inspector = InspectorWindowController(
            location: .simulator(port: 48160), entry: entry, store: model, projects: sources)
        inspector.fileActions.tellOfMissingFolder = { _, _, _, _ in }
        addTeardownBlock { @MainActor in inspector.close() }
        return inspector
    }

    private func linkedInspector() async throws -> (InspectorWindowController, LaunchRecorder) {
        let sources = try sources()
        let project = try project()
        sources.link(project.root, bundleID: "dev.cutaway.demo", appName: "Demo")
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        let inspector = try inspector(sources)
        let recorder = LaunchRecorder()
        inspector.project.opener = recorder.opener(xcode: URL(fileURLWithPath: "/Applications/Xcode.app"))
        inspector.showWindow(nil)
        return (inspector, recorder)
    }

    static func views(in view: NSView, identifier: String) -> [NSView] {
        (view.accessibilityIdentifier() == identifier ? [view] : [])
            + view.subviews.flatMap { views(in: $0, identifier: identifier) }
    }

    private func buttons(_ inspector: InspectorWindowController) -> [NSButton] {
        let identity = inspector.splitController.attributesController.identityView
        identity.layoutSubtreeIfNeeded()
        return Self.views(in: identity, identifier: IdentityLinesView.openInXcodeIdentifier)
            .compactMap { $0 as? NSButton }
    }

    private func menu(of inspector: InspectorWindowController, for id: UInt64) -> NSMenu {
        let menu = NSMenu()
        inspector.splitController.hierarchyController.layerMenu.fill(menu, for: id)
        return menu
    }

    private func openItem(_ menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.identifier == LayerContextMenu.openInXcodeIdentifier }
    }

    private func menuItem() -> NSMenuItem {
        NSMenuItem(title: "", action: #selector(InspectorWindowController.openInXcode(_:)), keyEquivalent: "o")
    }

    func test_C_SRC_03_aViewControllerFoundOnceOpensAtItsLine() async throws {
        let (inspector, recorder) = try await linkedInspector()
        // Layer 2 backs a system view and is the root view of HomeViewController.
        inspector.store.select(2)
        let buttons = buttons(inspector)
        XCTAssertEqual(buttons.count, 1, "only the view controller's class is the app's")
        buttons.first?.performClick(nil)
        XCTAssertEqual(recorder.runs.last?.arguments.prefix(2), ["--line", "3"])
        XCTAssertEqual(recorder.runs.last?.arguments.last?.hasSuffix("Demo/Home/HomeViewController.swift"), true)

        // The row's menu, and File › Open in Xcode.
        let item = try XCTUnwrap(openItem(menu(of: inspector, for: 2)))
        XCTAssertEqual(item.title, "Open in Xcode")
        XCTAssertNil(item.submenu)
        XCTAssertTrue(inspector.validateMenuItem(menuItem()))
        inspector.openInXcode(nil)
        XCTAssertEqual(recorder.runs.count, 2)
    }

    func test_C_SRC_03_twoDeclarationsAreAChoice() async throws {
        let (inspector, recorder) = try await linkedInspector()
        var offered: [[SourceLocation]] = []
        inspector.project.presentChoices = { locations, _ in offered.append(locations) }
        // Layer 4 backs a CardView, declared in two files.
        inspector.store.select(4)
        let button = try XCTUnwrap(buttons(inspector).first)
        button.performClick(nil)
        XCTAssertEqual(offered.last?.map(\.folder), ["Demo/Cards", "Legacy"])
        XCTAssertEqual(offered.last?.map(\.line), [1, 3])
        XCTAssertEqual(recorder.runs, [], "nothing opens before a choice")

        // The row's menu has the choice as a submenu, by file and line.
        let item = try XCTUnwrap(openItem(menu(of: inspector, for: 4)))
        let choices = try XCTUnwrap(item.submenu).items
        XCTAssertEqual(choices.map(\.title), ["CardView.swift:1", "CardView.swift:3"])
        let project = try XCTUnwrap(choices.last?.target as? ProjectLookup)
        project.openChosenPlace(try XCTUnwrap(choices.last))
        XCTAssertEqual(recorder.runs.last?.arguments.prefix(2), ["--line", "3"])
        XCTAssertEqual(recorder.runs.last?.arguments.last?.hasSuffix("Legacy/CardView.swift"), true)

        // ⌥⌘O offers the same choice.
        inspector.openInXcode(nil)
        XCTAssertEqual(offered.count, 2)
    }

    func test_C_SRC_03_systemClassesHaveNoOpenInXcode() async throws {
        let (inspector, _) = try await linkedInspector()
        // Layer 3 is a label: its view and its layer are the system's, though the project
        // declares classes of those names.
        inspector.store.select(3)
        XCTAssertEqual(buttons(inspector), [])
        XCTAssertNil(openItem(menu(of: inspector, for: 3)))
        XCTAssertFalse(inspector.validateMenuItem(menuItem()))
    }

    func test_C_SRC_03_theButtonShowsOnceTheIndexIsBuilt() async throws {
        let sources = try sources()
        let project = try project()
        let inspector = try inspector(sources)
        inspector.showWindow(nil)
        inspector.store.select(4)
        XCTAssertEqual(buttons(inspector), [])
        XCTAssertFalse(inspector.validateMenuItem(menuItem()))

        // Linked while the layer is selected: the button comes without selecting again.
        sources.link(project.root, bundleID: "dev.cutaway.demo", appName: "Demo")
        await sources.waitForIndex(bundleID: "dev.cutaway.demo")
        XCTAssertEqual(buttons(inspector).count, 1)
        XCTAssertTrue(inspector.validateMenuItem(menuItem()))
    }

    func test_C_SRC_03_aDisconnectedWindowOpensNothing() async throws {
        let (inspector, _) = try await linkedInspector()
        inspector.store.select(4)
        inspector.store.connectionLost()
        XCTAssertFalse(inspector.validateMenuItem(menuItem()))
        XCTAssertEqual(menu(of: inspector, for: 4).items, [])
    }

    func test_C_SRC_03_theMenusOpenTheViewBeforeTheViewController() {
        let index = ProjectIndex(
            root: URL(fileURLWithPath: "/Project", isDirectory: true),
            declarations: [
                "HomeView": [TypeDeclaration(name: "HomeView", kind: .swift, file: "HomeView.swift", line: 1)],
                "HomeViewController": [
                    TypeDeclaration(name: "HomeViewController", kind: .swift, file: "Home.swift", line: 1),
                ],
                "HomeLayer": [TypeDeclaration(name: "HomeLayer", kind: .swift, file: "HomeLayer.swift", line: 1)],
            ])
        var node = LayerNode(
            id: 1, parentID: 0, className: "HomeLayer", displayClassName: "Demo.HomeLayer",
            viewClassName: "HomeView", viewDisplayClassName: "Demo.HomeView", bounds: nil, position: nil,
            anchorPoint: nil, transform: nil, zPosition: 0, isHidden: false, opacity: 1, masksToBounds: false,
            viewControllerClassName: "HomeViewController", viewControllerDisplayClassName: "Demo.HomeViewController",
            layerClassOrigin: .app, viewClassOrigin: .app, viewControllerClassOrigin: .app)
        XCTAssertEqual(OpenableClasses(node, in: index).first.map(\.file.lastPathComponent), ["HomeView.swift"])
        node.viewClassOrigin = .system
        XCTAssertEqual(OpenableClasses(node, in: index).first.map(\.file.lastPathComponent), ["Home.swift"])
        node.viewControllerClassOrigin = .system
        XCTAssertEqual(OpenableClasses(node, in: index).first.map(\.file.lastPathComponent), ["HomeLayer.swift"])
        // Without an origin, as from a 1.0 server, a class is looked for.
        node.layerClassOrigin = .unknown
        XCTAssertFalse(OpenableClasses(node, in: index).isEmpty)
        XCTAssertTrue(OpenableClasses(node, in: nil).isEmpty)
    }
}
