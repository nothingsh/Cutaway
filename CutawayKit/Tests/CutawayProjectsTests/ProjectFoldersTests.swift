import Combine
import CutawayTestSupport
import Foundation
import XCTest

@testable import CutawayProjects

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
        let files = try XCTUnwrap(sources.reports["com.example.shop"]).read
        try builder.write("Shop/First.swift", "class First {}")
        sources.update(bundleID: "com.example.shop")
        try builder.write("Shop/Second.swift", "class Second {}")
        sources.update(bundleID: "com.example.shop")
        sources.update(bundleID: "com.example.shop")
        var published = 0
        let counting = sources.$indexes.dropFirst().sink { _ in published += 1 }
        await sources.waitForIndex(bundleID: "com.example.shop")
        counting.cancel()
        // The first build read both files; the one more found nothing new, and published
        // nothing.
        XCTAssertEqual(sources.reports["com.example.shop"], ProjectIndexReport(read: 0, reused: files + 2))
        XCTAssertEqual(published, 1)
        XCTAssertNotNil(sources.indexes["com.example.shop"]?.declarations["Second"])
    }

    /// An index nothing follows any more is kept a while: until more apps than are kept were
    /// put aside after it. Then it is forgotten, and built again from the start once asked.
    func test_C_SRC_02_anIndexNoLongerFollowedIsForgottenOnceOthersArePutAsideAfterIt() async throws {
        let sources = ProjectSources(folders: ProjectFolders(defaults: defaults), keptAside: 1)
        var followers: [String: AnyCancellable] = [:]
        var projects: [ProjectBuilder] = []
        defer { projects.forEach { $0.remove() } }
        for app in ["a", "b", "c"] {
            let project = try ProjectBuilder(name: app)
            projects.append(project)
            try project.write("\(app).swift", "class In\(app.uppercased()) {}")
            sources.link(project.root, bundleID: app, appName: app)
            followers[app] = sources.index(for: app).sink { _ in }
            await sources.waitForIndex(bundleID: app)
        }
        XCTAssertEqual(Set(sources.indexes.keys), ["a", "b", "c"])

        // One put aside is kept; followed again, it is no longer aside.
        followers["a"] = nil
        XCTAssertNotNil(sources.indexes["a"])
        followers["a"] = sources.index(for: "a").sink { _ in }
        followers["b"] = nil
        followers["c"] = nil
        XCTAssertEqual(Set(sources.indexes.keys), ["a", "c"], "b was put aside before c")
        XCTAssertNil(sources.reports["b"])

        sources.update(bundleID: "b")
        await sources.waitForIndex(bundleID: "b")
        XCTAssertEqual(sources.reports["b"], ProjectIndexReport(read: 1))
        XCTAssertNotNil(sources.indexes["b"]?.declarations["InB"])
        // Built with nothing following it, it is the latest put aside.
        XCTAssertEqual(Set(sources.indexes.keys), ["a", "b"])
    }

    /// Each index is told of once, by its generation: built again unchanged, nothing; changed,
    /// the new one; the link removed, none.
    func test_C_SRC_02_aNewIndexIsToldOfByItsGeneration() async throws {
        let (sources, builder) = try await linkedSample()
        var received: [UInt64?] = []
        let following = sources.index(for: "com.example.shop").sink { received.append($0?.generation) }
        defer { following.cancel() }
        let first = try XCTUnwrap(sources.indexes["com.example.shop"]).generation
        sources.update(bundleID: "com.example.shop")
        await sources.waitForIndex(bundleID: "com.example.shop")
        try builder.write("Shop/New.swift", "class Added {}")
        sources.update(bundleID: "com.example.shop")
        await sources.waitForIndex(bundleID: "com.example.shop")
        let second = try XCTUnwrap(sources.indexes["com.example.shop"]).generation
        sources.remove(bundleID: "com.example.shop")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(received, [first, second, nil])
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

    /// The folder deleted while its index is being built, and the index asked for again
    /// meanwhile: no empty index is published, and the folder reads as missing.
    func test_C_SRC_02_aFolderDeletedWhileBuildingPublishesNoEmptyIndex() async throws {
        let (sources, builder) = try await linkedSample()
        let path = builder.root.path
        var published: [Int?] = []
        let watching = sources.$indexes.dropFirst().sink {
            published.append($0["com.example.shop"]?.declarations.count)
        }
        defer { watching.cancel() }
        try builder.write("Shop/New.swift", "class Added {}")
        sources.update(bundleID: "com.example.shop")
        try FileManager.default.removeItem(at: builder.root)
        sources.update(bundleID: "com.example.shop")
        await sources.waitForIndex(bundleID: "com.example.shop")
        XCTAssertFalse(published.contains(0), "published \(published)")
        XCTAssertNil(sources.indexes["com.example.shop"])
        XCTAssertEqual(sources.update(bundleID: "com.example.shop"), .missing(path: path))
    }

    /// The folder renamed while its index is being built, and the index asked for again
    /// meanwhile: the folder is found again, and indexed where it is now.
    func test_C_SRC_02_aFolderRenamedWhileBuildingIsFoundAgain() async throws {
        let (sources, builder) = try await linkedSample()
        let renamed = builder.root.deletingLastPathComponent().appendingPathComponent("Renamed", isDirectory: true)
        sources.update(bundleID: "com.example.shop")
        try FileManager.default.moveItem(at: builder.root, to: renamed)
        sources.update(bundleID: "com.example.shop")
        await sources.waitForIndex(bundleID: "com.example.shop")
        let index = try XCTUnwrap(sources.indexes["com.example.shop"])
        XCTAssertEqual(index.root.lastPathComponent, "Renamed")
        XCTAssertNotNil(index.declarations["HomeViewController"])
    }

    /// A following cancelled on another thread, as when what holds it is released there,
    /// counts once it reaches the main thread: nothing follows the index any more.
    func test_C_SRC_02_aFollowingCancelledOnAnotherThreadStopsFollowing() async throws {
        let sources = ProjectSources(folders: ProjectFolders(defaults: defaults), keptAside: 0)
        let builder = try ProjectBuilder()
        self.builder = builder
        try builder.write("A.swift", "class InA {}")
        let following = sources.index(for: "a").sink { _ in }
        sources.link(builder.root, bundleID: "a", appName: "A")
        await sources.waitForIndex(bundleID: "a")
        XCTAssertNotNil(sources.indexes["a"])

        Self.cancelOnAnotherThread(following)
        // What was sent to the main thread arrives.
        for _ in 0..<100 where sources.indexes["a"] != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(sources.indexes["a"], "followed by nothing, and none kept aside")
    }

    /// Cancels on a thread of its own while the main thread waits, so that whatever the cancel
    /// sends to the main thread arrives only after.
    private static func cancelOnAnotherThread(_ cancellable: AnyCancellable) {
        nonisolated(unsafe) let cancellable = cancellable
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            cancellable.cancel()
            done.signal()
        }
        thread.start()
        done.wait()
    }
}
