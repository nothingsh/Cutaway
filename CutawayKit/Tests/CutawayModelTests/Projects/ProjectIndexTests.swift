import CutawayTestSupport
import Foundation
import XCTest
@testable import CutawayModel

/// C-SRC-02: what the index reads, what it leaves out, and building it again.
final class ProjectIndexTests: XCTestCase {
    private var builder: ProjectBuilder?

    override func tearDown() {
        if let builder {
            // A file made unreadable is put back, so that it can be removed.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: builder.url("Shop/Locked.swift").path)
            builder.remove()
        }
    }

    private func sample() throws -> ProjectBuilder {
        let builder = try ProjectBuilder()
        self.builder = builder
        try SampleProject.write(into: builder)
        return builder
    }

    private func names(_ index: ProjectIndex) -> Set<String> {
        Set(index.declarations.keys)
    }

    func test_C_SRC_02_theFoldersOfBuildsThirdPartiesAndHiddenOnesAreLeftOut() async throws {
        let builder = try sample()
        let index = await ProjectIndexer(root: builder.root).build().0
        XCTAssertTrue(names(index).contains("HomeViewController"))
        for name in [
            "InPods", "InCarthage", "InDerivedData", "InBuild", "InDotBuild", "InSourcePackages", "InHidden",
        ] {
            XCTAssertFalse(names(index).contains(name), name)
        }
    }

    func test_C_SRC_02_symbolicLinksAreNotFollowed() async throws {
        let builder = try sample()
        let elsewhere = try ProjectBuilder(name: "Elsewhere")
        defer { elsewhere.remove() }
        try elsewhere.write("Linked/Linked.swift", "class InALinkedFolder {}")
        try elsewhere.write("LinkedFile.swift", "class InALinkedFile {}")
        let manager = FileManager.default
        try manager.createSymbolicLink(at: builder.url("Shop/Linked"), withDestinationURL: elsewhere.url("Linked"))
        try manager.createSymbolicLink(
            at: builder.url("Shop/LinkedFile.swift"), withDestinationURL: elsewhere.url("LinkedFile.swift"))
        // A link to the folder itself would never end if it were followed.
        try manager.createSymbolicLink(at: builder.url("Shop/Loop"), withDestinationURL: builder.root)

        let index = await ProjectIndexer(root: builder.root).build().0
        XCTAssertFalse(names(index).contains("InALinkedFolder"))
        XCTAssertFalse(names(index).contains("InALinkedFile"))
        XCTAssertEqual(index.declarations["HomeViewController"]?.count, 1)
    }

    func test_C_SRC_02_aFileThatCannotBeReadIsSkippedAndTheRestIsIndexed() async throws {
        let builder = try sample()
        let locked = try builder.write("Shop/Locked.swift", "class Locked {}")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        try builder.write("Shop/Broken.xcstrings", "{ not json")
        try builder.write("Shop/Assets.xcassets/Broken.colorset/Contents.json", "[1, 2")
        try builder.write("Shop/Large.swift", "class Large {}\n" + String(repeating: "// padding\n", count: 400_000))

        let (index, report) = await ProjectIndexer(root: builder.root).build()
        XCTAssertFalse(names(index).contains("Locked"))
        XCTAssertFalse(names(index).contains("Large"), "larger than \(ProjectIndexer.largestFile) bytes")
        XCTAssertEqual(report.skipped, 4)
        XCTAssertTrue(names(index).contains("HomeViewController"))
        XCTAssertTrue(index.strings.contains { $0.key == "home.title" })
        XCTAssertFalse(index.colorSets.contains { $0.name == "Broken" })
    }

    func test_C_SRC_02_changingOneFileReadsOnlyThatFileAgain() async throws {
        let builder = try sample()
        let indexer = ProjectIndexer(root: builder.root)
        let (_, first) = await indexer.build()
        XCTAssertEqual(first.reused, 0)
        let files = first.read

        let (_, unchanged) = await indexer.build()
        XCTAssertEqual(unchanged, ProjectIndexReport(read: 0, reused: files, skipped: 0))

        // Another size, so that a change within the same second counts too.
        try builder.write(SampleProject.listCell, "final class ListCell {}\nstruct Added {}\n")
        let (index, changed) = await indexer.build()
        XCTAssertEqual(changed, ProjectIndexReport(read: 1, reused: files - 1, skipped: 0))
        XCTAssertEqual(index.declarations["Added"]?.first?.line, 2)
        XCTAssertEqual(index.declarations["ListCell"]?.first?.line, 1)
    }

    func test_C_SRC_02_newAndRemovedFilesComeAndGo() async throws {
        let builder = try sample()
        let indexer = ProjectIndexer(root: builder.root)
        let files = await indexer.build().1.read
        try builder.write("Shop/New.swift", "struct New {}")
        try FileManager.default.removeItem(at: builder.url(SampleProject.listCell))
        let (index, report) = await indexer.build()
        XCTAssertEqual(report, ProjectIndexReport(read: 1, reused: files - 1, skipped: 0))
        XCTAssertNotNil(index.declarations["New"])
        XCTAssertNil(index.declarations["ListCell"])
    }

    func test_C_SRC_02_colorSetsAreReadWithTheirNamespaces() async throws {
        let builder = try sample()
        let index = await ProjectIndexer(root: builder.root).build().0
        XCTAssertEqual(index.colorSets.map(\.name), ["AccentColor", "Brand/Blue", "Gray"])
        let blue = try XCTUnwrap(index.colorSets.first { $0.name == "Brand/Blue" })
        XCTAssertEqual(blue.file, "Shop/Assets.xcassets/Brand/Blue.colorset/Contents.json")
        XCTAssertEqual(blue.entries.count, 2)
        XCTAssertEqual(blue.entries[0].appearances, [])
        XCTAssertEqual(blue.entries[0].colorSpace, "srgb")
        XCTAssertEqual(blue.entries[0].components["red"], "0x1E")
        XCTAssertEqual(blue.entries[1].appearances, [.init(appearance: "luminosity", value: "dark")])
        XCTAssertEqual(blue.entries[1].components["green"], "231")
        let gray = try XCTUnwrap(index.colorSets.first { $0.name == "Gray" })
        XCTAssertEqual(gray.entries.first?.systemReference, "systemGrayColor")
        XCTAssertEqual(gray.entries.first?.components, [:])
    }

    func test_C_SRC_02_stringTablesAreReadInEveryLanguageAndVariant() async throws {
        let builder = try sample()
        let index = await ProjectIndexer(root: builder.root).build().0
        func values(_ key: String) -> [String] {
            index.strings.filter { $0.key == key }.map { "\($0.table) \($0.language ?? "-") \($0.value)" }
        }
        XCTAssertEqual(values("home.title"), ["Localizable en Home", "Localizable zh-Hans 首页"])
        XCTAssertEqual(values("items.count"), ["Localizable en %lld item", "Localizable en %lld items"])
        // No value in the source language: the key itself.
        XCTAssertEqual(values("Sign In"), ["Localizable en Sign In"])
        XCTAssertEqual(
            values("CFBundleDisplayName").sorted(),
            ["InfoPlist en Demo Shop", "InfoPlist zh-Hans 演示商店"])
        XCTAssertEqual(
            index.strings.first { $0.key == "CFBundleDisplayName" && $0.language == "en" }?.file,
            "Shop/en.lproj/InfoPlist.strings")
    }
}

/// C-SRC-02: the generated project is indexed in time, without stalling the main thread.
@MainActor
final class ProjectIndexScaleTests: XCTestCase {
    func test_C_SRC_02_aGeneratedProjectIsIndexedWithinTwoSecondsWithoutStallingTheMainThread() async throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let builder = try ProjectBuilder()
        defer { builder.remove() }
        try GeneratedProject.write(into: builder)
        let suite = "ProjectIndexScaleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sources = ProjectSources(folders: ProjectFolders(defaults: defaults))

        let meter = MainThreadStallMeter()
        meter.start()
        let start = ContinuousClock.now
        sources.link(builder.root, bundleID: "com.example.generated", appName: "Generated")
        await sources.waitForIndex(bundleID: "com.example.generated")
        let elapsed = ContinuousClock.now - start
        let pause = meter.stop()

        let index = try XCTUnwrap(sources.indexes["com.example.generated"])
        print("C-SRC-02 indexed in \(elapsed), longest main thread pause \(Int(pause * 1000)) ms")
        // Each file: its class, a struct in it and an enum in its extension.
        XCTAssertEqual(index.declarations.values.map(\.count).reduce(0, +), GeneratedProject.swiftFileCount * 3)
        XCTAssertEqual(index.colorSets.count, GeneratedProject.colorSetCount)
        XCTAssertEqual(
            index.strings.count,
            GeneratedProject.catalogCount * GeneratedProject.keysPerCatalog * GeneratedProject.languages.count)
        XCTAssertEqual(sources.reports["com.example.generated"]?.skipped, 0)
        XCTAssertLessThanOrEqual(elapsed, .seconds(2))
        XCTAssertLessThanOrEqual(pause, 0.05)
    }
}
