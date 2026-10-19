import CutawayModel
import CutawayTestSupport
import Foundation
import XCTest

/// C-SRC-01: the folder linked to each app is kept, found again once moved, and read as none
/// once gone.
@MainActor
final class ProjectFoldersTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults()
    private var builders: [ProjectBuilder] = []

    override func setUp() async throws {
        suiteName = "ProjectFoldersTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        for builder in builders {
            builder.remove()
        }
    }

    private func folder(_ name: String = "Project") throws -> ProjectBuilder {
        let builder = try ProjectBuilder(name: name)
        builders.append(builder)
        return builder
    }

    func test_C_SRC_01_aLinkedFolderIsReadBackByANewModel() throws {
        let project = try folder()
        ProjectFolders(defaults: defaults).link(project.root, bundleID: "com.example.shop", appName: "Shop")

        let again = ProjectFolders(defaults: defaults)
        let link = try XCTUnwrap(again.link(for: "com.example.shop"))
        XCTAssertEqual(link.appName, "Shop")
        XCTAssertEqual(link.path, project.root.path)
        XCTAssertFalse(link.bookmark.isEmpty)
        XCTAssertEqual(again.locate(bundleID: "com.example.shop"), .found(project.root))
        XCTAssertNil(again.locate(bundleID: "com.example.other"))
    }

    func test_C_SRC_01_twoAppsKeepTheirOwnFolders() throws {
        let shop = try folder("Shop")
        let notes = try folder("Notes")
        let folders = ProjectFolders(defaults: defaults)
        folders.link(shop.root, bundleID: "com.example.shop", appName: "Shop")
        folders.link(notes.root, bundleID: "com.example.notes", appName: "Field Notes")
        XCTAssertEqual(folders.links.map(\.appName), ["Field Notes", "Shop"])

        // Linking again replaces only that app's folder.
        let other = try folder("Other")
        folders.link(other.root, bundleID: "com.example.shop", appName: "Shop 2")
        let again = ProjectFolders(defaults: defaults)
        XCTAssertEqual(again.link(for: "com.example.shop")?.path, other.root.path)
        XCTAssertEqual(again.link(for: "com.example.shop")?.appName, "Shop 2")
        XCTAssertEqual(again.link(for: "com.example.notes")?.path, notes.root.path)

        again.remove(bundleID: "com.example.shop")
        XCTAssertNil(ProjectFolders(defaults: defaults).link(for: "com.example.shop"))
        XCTAssertNotNil(ProjectFolders(defaults: defaults).link(for: "com.example.notes"))
    }

    func test_C_SRC_01_aRenamedFolderIsFoundByItsBookmark() throws {
        let project = try folder()
        let folders = ProjectFolders(defaults: defaults)
        folders.link(project.root, bundleID: "com.example.shop", appName: "Shop")
        let renamed = project.root.deletingLastPathComponent().appendingPathComponent("Renamed", isDirectory: true)
        try FileManager.default.moveItem(at: project.root, to: renamed)

        guard case .found(let found) = folders.locate(bundleID: "com.example.shop") else {
            XCTFail("the bookmark did not find the renamed folder")
            return
        }
        XCTAssertEqual(found.resolvingSymlinksInPath().path, renamed.resolvingSymlinksInPath().path)
        // Kept at its new path.
        XCTAssertEqual(
            ProjectFolders(defaults: defaults).link(for: "com.example.shop")?.path, found.path)
    }

    func test_C_SRC_01_aDeletedFolderReadsAsMissingAndTheLinkIsKept() throws {
        let project = try folder()
        let folders = ProjectFolders(defaults: defaults)
        folders.link(project.root, bundleID: "com.example.shop", appName: "Shop")
        try FileManager.default.removeItem(at: project.root)

        XCTAssertEqual(folders.locate(bundleID: "com.example.shop"), .missing(path: project.root.path))
        XCTAssertNotNil(ProjectFolders(defaults: defaults).link(for: "com.example.shop"))
    }

    func test_C_SRC_01_aLinkThatCannotBeReadIsNoneAndKept() throws {
        let project = try folder()
        defaults.set(
            [
                "com.example.number": 3,
                "com.example.nopath": ["name": "No Path"],
                "": ["name": "Empty", "path": "/"],
                "com.example.noname": ["path": project.root.path],
            ] as [String: Any],
            forKey: ProjectFolders.Key.folders)
        let folders = ProjectFolders(defaults: defaults)
        XCTAssertEqual(folders.links.map(\.bundleID), ["com.example.noname"])
        // Without a name, the bundle ID stands in; without a bookmark, the path still finds it.
        XCTAssertEqual(folders.links.first?.appName, "com.example.noname")
        XCTAssertEqual(folders.locate(bundleID: "com.example.noname"), .found(project.root))

        folders.link(project.root, bundleID: "com.example.shop", appName: "Shop")
        let kept = try XCTUnwrap(defaults.dictionary(forKey: ProjectFolders.Key.folders))
        XCTAssertEqual(kept["com.example.number"] as? Int, 3)
        XCTAssertNotNil(kept["com.example.nopath"])
    }

    func test_C_SRC_01_aWholeValueThatIsNotADictionaryReadsAsNoLinks() {
        defaults.set("folders", forKey: ProjectFolders.Key.folders)
        XCTAssertEqual(ProjectFolders(defaults: defaults).links, [])
    }
}

/// C-SRC-02: when an app's index is built, and what is forgotten.
@MainActor
final class ProjectSourcesTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults()
    private var builder: ProjectBuilder?

    override func setUp() async throws {
        suiteName = "ProjectSourcesTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        builder?.remove()
    }

    private func linkedSample() async throws -> (ProjectSources, ProjectBuilder) {
        let builder = try ProjectBuilder()
        self.builder = builder
        try SampleProject.write(into: builder)
        let sources = ProjectSources(folders: ProjectFolders(defaults: defaults))
        sources.link(builder.root, bundleID: "com.example.shop", appName: "Shop")
        await sources.waitForIndex(bundleID: "com.example.shop")
        return (sources, builder)
    }

    func test_C_SRC_02_linkingBuildsTheIndex() async throws {
        let (sources, _) = try await linkedSample()
        XCTAssertNotNil(sources.indexes["com.example.shop"]?.declarations["HomeViewController"])
        XCTAssertEqual(sources.reports["com.example.shop"]?.reused, 0)
    }

    func test_C_SRC_02_updatingReadsOnlyWhatChanged() async throws {
        let (sources, builder) = try await linkedSample()
        let files = try XCTUnwrap(sources.reports["com.example.shop"]).read
        try builder.write("Shop/New.swift", "class Added {}")
        XCTAssertEqual(sources.update(bundleID: "com.example.shop"), .updating)
        await sources.waitForIndex(bundleID: "com.example.shop")
        XCTAssertEqual(sources.reports["com.example.shop"], ProjectIndexReport(read: 1, reused: files))
        XCTAssertNotNil(sources.indexes["com.example.shop"]?.declarations["Added"])
    }

    func test_C_SRC_02_askedAgainWhileBuildingBuildsOnceMore() async throws {
        let (sources, builder) = try await linkedSample()
        try builder.write("Shop/First.swift", "class First {}")
        sources.update(bundleID: "com.example.shop")
        try builder.write("Shop/Second.swift", "class Second {}")
        sources.update(bundleID: "com.example.shop")
        sources.update(bundleID: "com.example.shop")
        var builds = 0
        let counting = sources.$indexes.dropFirst().sink { _ in builds += 1 }
        await sources.waitForIndex(bundleID: "com.example.shop")
        counting.cancel()
        XCTAssertEqual(builds, 2)
        XCTAssertNotNil(sources.indexes["com.example.shop"]?.declarations["Second"])
    }

    func test_C_SRC_02_removingTheLinkForgetsTheIndex() async throws {
        let (sources, _) = try await linkedSample()
        sources.remove(bundleID: "com.example.shop")
        XCTAssertNil(sources.indexes["com.example.shop"])
        XCTAssertEqual(sources.update(bundleID: "com.example.shop"), .notLinked)
    }

    func test_C_SRC_02_aMissingFolderHasNoIndexAndIsToldOfOnce() async throws {
        let (sources, builder) = try await linkedSample()
        let path = builder.root.path
        try FileManager.default.removeItem(at: builder.root)
        XCTAssertEqual(sources.update(bundleID: "com.example.shop"), .missing(path: path))
        XCTAssertNil(sources.indexes["com.example.shop"])
        XCTAssertTrue(sources.shouldTellOfMissingFolder(bundleID: "com.example.shop"))
        XCTAssertFalse(sources.shouldTellOfMissingFolder(bundleID: "com.example.shop"))
        XCTAssertTrue(sources.shouldTellOfMissingFolder(bundleID: "com.example.other"))
    }

    func test_C_SRC_02_anotherFolderStartsAFreshIndex() async throws {
        let (sources, _) = try await linkedSample()
        let other = try ProjectBuilder(name: "Other")
        defer { other.remove() }
        try other.write("Other.swift", "class OnlyInOther {}")
        sources.link(other.root, bundleID: "com.example.shop", appName: "Shop")
        await sources.waitForIndex(bundleID: "com.example.shop")
        let index = try XCTUnwrap(sources.indexes["com.example.shop"])
        XCTAssertEqual(Set(index.declarations.keys), ["OnlyInOther"])
        XCTAssertEqual(sources.reports["com.example.shop"], ProjectIndexReport(read: 1))
    }
}
