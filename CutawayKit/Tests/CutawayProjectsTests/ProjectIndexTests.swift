import Combine
import CutawayTestSupport
import Foundation
import os
import XCTest
@testable import CutawayProjects

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

    /// The folders of builds, third parties and hidden ones, node modules, frameworks and
    /// bundles.
    func test_C_SRC_02_excludedFoldersAreLeftOut() async throws {
        let builder = try sample()
        try builder.write("Web/node_modules/kit/Kit.swift", "class InNodeModules {}")
        try builder.write("Vendor/Kit.framework/Headers/Kit.h", "@interface InFramework : NSObject\n@end")
        try builder.write(
            "Vendor/Kit.xcframework/ios-arm64/Kit.framework/Headers/Kit.h", "@interface InXCFramework : NSObject\n@end")
        try builder.write("Shop/Resources.bundle/InBundle.swift", "class InBundle {}")
        try builder.write("Shop/Resources.bundle/en.lproj/Bundle.strings", #""bundle.key" = "In a bundle";"#)

        let indexer = ProjectIndexer(root: builder.root)
        let index = try await indexer.build().0
        XCTAssertTrue(names(index).contains("HomeViewController"))
        for name in [
            "InPods", "InCarthage", "InDerivedData", "InBuild", "InDotBuild", "InSourcePackages", "InHidden",
            "InNodeModules", "InFramework", "InXCFramework", "InBundle",
        ] {
            XCTAssertFalse(names(index).contains(name), name)
        }
        let strings = await indexer.strings()
        XCTAssertFalse(strings.contains { $0.key == "bundle.key" })
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

        let index = try await ProjectIndexer(root: builder.root).build().0
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

        let indexer = ProjectIndexer(root: builder.root)
        let (index, report) = try await indexer.build()
        XCTAssertFalse(names(index).contains("Locked"))
        XCTAssertFalse(
            names(index).contains("Large"), "larger than \(ProjectIndexer.Limits.standard.largestSourceFile) bytes")
        XCTAssertEqual(report.tooLarge, 1)
        XCTAssertEqual(report.unreadable, 3)
        XCTAssertEqual(report.skipped, 4)
        XCTAssertTrue(names(index).contains("HomeViewController"))
        let strings = await indexer.strings()
        XCTAssertTrue(strings.contains { $0.key == "home.title" })
        XCTAssertFalse(index.colorSets.contains { $0.name == "Broken" })

        // Built again, only those that cannot be read are tried again: the same index.
        let (again, second) = try await indexer.build()
        XCTAssertEqual(again.generation, index.generation)
        XCTAssertEqual(second, ProjectIndexReport(reused: report.read, tooLarge: 1, unreadable: 3))
    }

    /// One file more than four for each processor: the reading shares them out with the last
    /// ones included.
    func test_C_SRC_02_oneFileMoreThanFourPerProcessorIsRead() async throws {
        let builder = try ProjectBuilder()
        self.builder = builder
        let count = ProcessInfo.processInfo.activeProcessorCount * 4 + 1
        for number in 0..<count {
            try builder.write("App/F\(number).swift", "class F\(number) {}")
        }
        let (index, report) = try await ProjectIndexer(root: builder.root).build()
        XCTAssertEqual(report, ProjectIndexReport(read: count))
        XCTAssertEqual(index.declarations.count, count)
    }

    /// However many files and processors, the shares cover every file once, in order, none is
    /// empty, and there are at most four for each processor.
    func test_C_SRC_02_theSharesCoverEveryFileOnceAndNoneIsEmpty() {
        XCTAssertEqual(ProjectIndexer.shares(of: 0, processors: 8), [])
        for processors in [0, 1, 2, 3, 4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32, 64] {
            for count in 1...5000 {
                let shares = ProjectIndexer.shares(of: count, processors: processors)
                var next = 0
                for share in shares {
                    guard share.lowerBound == next, !share.isEmpty else {
                        XCTFail("\(count) files, \(processors) processors: \(share) after \(next)")
                        return
                    }
                    next = share.upperBound
                }
                XCTAssertEqual(next, count, "\(count) files, \(processors) processors")
                XCTAssertLessThanOrEqual(shares.count, max(processors, 1) * 4)
            }
        }
    }

    /// Large files are read at most two at a time, whatever the processors; every file is
    /// read, into its own place.
    func test_C_SRC_02_largeFilesAreReadAtMostTwoAtATime() {
        let reading = OSAllocatedUnfairLock(initialState: (now: 0, most: 0))
        let items = Array(0..<64)
        let read = { (item: Int) -> Int? in
            guard item.isMultiple(of: 2) else { return item }
            reading.withLock { $0.now += 1; $0.most = max($0.most, $0.now) }
            Thread.sleep(forTimeInterval: 0.005)
            reading.withLock { $0.now -= 1 }
            return item
        }
        let contents = ProjectIndexer.read(
            items, processors: 16, isLarge: { $0.isMultiple(of: 2) }, ProjectIndexer.Cancellation(), content: read)
        XCTAssertEqual(contents, items)
        XCTAssertLessThanOrEqual(reading.withLock { $0.most }, 2)
    }

    /// A folder that cannot be listed any more is not an empty project: the build says so,
    /// and gives no index.
    func test_C_SRC_02_aFolderThatCannotBeListedIsNotIndexedAsEmpty() async throws {
        let builder = try sample()
        let indexer = ProjectIndexer(root: builder.root)
        _ = try await indexer.build()
        try FileManager.default.removeItem(at: builder.root)
        do {
            let (index, _) = try await indexer.build()
            XCTFail("built an index of \(index.declarations.count) declarations")
        } catch {
            XCTAssertTrue(error is ProjectIndexer.FolderUnreadable, "\(error)")
        }
    }

    func test_C_SRC_02_theWalkStopsAtTheMostFilesAndSaysSo() async throws {
        let builder = try sample()
        let all = try await ProjectIndexer(root: builder.root).build().1
        XCTAssertFalse(all.reachedFileLimit)
        XCTAssertGreaterThan(all.read, 3)

        func limits(mostFiles: Int) -> ProjectIndexer.Limits {
            ProjectIndexer.Limits(largestSourceFile: 1 << 20, largestStringTable: 1 << 20, mostFiles: mostFiles)
        }
        let few = try await ProjectIndexer(root: builder.root, limits: limits(mostFiles: 3)).build().1
        XCTAssertEqual(few, ProjectIndexReport(read: 3, reachedFileLimit: true))
        // As many as there are: none left out.
        let exactly = try await ProjectIndexer(root: builder.root, limits: limits(mostFiles: all.read)).build().1
        XCTAssertEqual(exactly, ProjectIndexReport(read: all.read))
    }

    /// A String Catalog of thousands of keys in 40 languages is far larger than a source file
    /// may be, and is read; a source file as large is not.
    func test_C_SRC_02_largeStringTablesAreReadAndLargeSourceFilesAreNot() async throws {
        let builder = try sample()
        let keys = (0..<2000).map { key in
            let localizations = (0..<40).map { language in
                #""l\#(language)":{"stringUnit":{"state":"translated","value":"Value \#(key) in l\#(language)"}}"#
            }
            return #""key.\#(key)":{"localizations":{\#(localizations.joined(separator: ","))}}"#
        }
        let catalog = try builder.write(
            "Shop/Large.xcstrings",
            #"{"sourceLanguage":"l0","strings":{\#(keys.joined(separator: ","))},"version":"1.0"}"#)
        let large = String(repeating: "// padding\n", count: 400_000)
        try builder.write("Shop/Large.swift", "class Large {}\n" + large)
        let size = try XCTUnwrap(catalog.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertGreaterThan(size, ProjectIndexer.Limits.standard.largestSourceFile)

        let (index, report) = try await ProjectIndexer(root: builder.root).build()
        XCTAssertEqual(index.keys.matches("Value 1999 in l39"), [StringKeyMatch(table: "Large", key: "key.1999")])
        XCTAssertFalse(names(index).contains("Large"))
        XCTAssertEqual(report.tooLarge, 1)
        XCTAssertEqual(report.unreadable, 0)

        // Past the most a table is read at, it is too large as well.
        let limits = ProjectIndexer.Limits(
            largestSourceFile: ProjectIndexer.Limits.standard.largestSourceFile, largestStringTable: size - 1,
            mostFiles: 1000)
        let smaller = try await ProjectIndexer(root: builder.root, limits: limits).build()
        XCTAssertEqual(smaller.0.keys.matches("Value 1999 in l39"), [])
        XCTAssertEqual(smaller.1.tooLarge, 2)
    }

    func test_C_SRC_02_changingOneFileReadsOnlyThatFileAgain() async throws {
        let builder = try sample()
        let indexer = ProjectIndexer(root: builder.root)
        let (_, first) = try await indexer.build()
        XCTAssertEqual(first.reused, 0)
        let files = first.read

        let (_, unchanged) = try await indexer.build()
        XCTAssertEqual(unchanged, ProjectIndexReport(read: 0, reused: files))

        // Another size, so that a change within the same second counts too.
        try builder.write(SampleProject.listCell, "final class ListCell {}\nstruct Added {}\n")
        let (index, changed) = try await indexer.build()
        XCTAssertEqual(changed, ProjectIndexReport(read: 1, reused: files - 1))
        XCTAssertEqual(index.declarations["Added"]?.first?.line, 2)
        XCTAssertEqual(index.declarations["ListCell"]?.first?.line, 1)
    }

    func test_C_SRC_02_newAndRemovedFilesComeAndGo() async throws {
        let builder = try sample()
        let indexer = ProjectIndexer(root: builder.root)
        let files = try await indexer.build().1.read
        try builder.write("Shop/New.swift", "struct New {}")
        try FileManager.default.removeItem(at: builder.url(SampleProject.listCell))
        let (index, report) = try await indexer.build()
        XCTAssertEqual(report, ProjectIndexReport(read: 1, reused: files - 1))
        XCTAssertNotNil(index.declarations["New"])
        XCTAssertNil(index.declarations["ListCell"])
    }

    func test_C_SRC_02_colorSetsAreReadWithTheirNamespaces() async throws {
        let builder = try sample()
        let index = try await ProjectIndexer(root: builder.root).build().0
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
        let indexer = ProjectIndexer(root: builder.root)
        _ = try await indexer.build()
        let strings = await indexer.strings()
        func values(_ key: String) -> [String] {
            strings.filter { $0.key == key }.map { "\($0.table) \($0.language ?? "-") \($0.value)" }
        }
        XCTAssertEqual(values("home.title"), ["Localizable en Home", "Localizable zh-Hans 首页"])
        XCTAssertEqual(values("items.count"), ["Localizable en %lld item", "Localizable en %lld items"])
        // No value in the source language: the key itself.
        XCTAssertEqual(values("Sign In"), ["Localizable en Sign In"])
        XCTAssertEqual(
            values("CFBundleDisplayName").sorted(),
            ["InfoPlist en Demo Shop", "InfoPlist zh-Hans 演示商店"])
        XCTAssertEqual(
            strings.first { $0.key == "CFBundleDisplayName" && $0.language == "en" }?.file,
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
        for catalog in 0..<GeneratedProject.catalogCount {
            let last = GeneratedProject.keysPerCatalog - 1
            for language in GeneratedProject.languages {
                XCTAssertEqual(
                    index.keys.matches("\(language) text \(catalog).\(last) Ann").map(\.key),
                    ["key.\(catalog).\(last)"])
            }
        }
        XCTAssertEqual(sources.reports["com.example.generated"]?.skipped, 0)
        XCTAssertLessThanOrEqual(elapsed, .seconds(2))
        XCTAssertLessThanOrEqual(pause, 0.05)
    }

    /// Built again with nothing changed, the index is the one built before: the folder is
    /// walked, but no declaration, colour set or string is gathered again, so it takes a
    /// fraction of the first build. String tables in 40 languages, 200,000 values.
    func test_C_SRC_02_buildingAgainUnchangedGivesTheSameIndexInAFractionOfTheTime() async throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let builder = try ProjectBuilder()
        defer { builder.remove() }
        try GeneratedProject.write(into: builder)
        try Self.writeTables(into: builder)
        let indexer = ProjectIndexer(root: builder.root)

        var start = ContinuousClock.now
        let (first, _) = try await indexer.build()
        let firstTime = ContinuousClock.now - start
        start = ContinuousClock.now
        let (again, report) = try await indexer.build()
        let againTime = ContinuousClock.now - start
        print("C-SRC-02 built in \(firstTime), again unchanged in \(againTime)")
        XCTAssertEqual(report, ProjectIndexReport(reused: GeneratedProject.fileCount + 40))
        XCTAssertEqual(again.generation, first.generation)
        XCTAssertLessThan(againTime, firstTime / 5)
    }

    /// A build cancelled stops within a fraction of the time a build takes, keeps nothing of
    /// what it read, and the next build reads every file.
    func test_C_SRC_02_aBuildCanBeCancelled() async throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let builder = try ProjectBuilder()
        defer { builder.remove() }
        try GeneratedProject.write(into: builder)
        try Self.writeTables(into: builder)
        let indexer = ProjectIndexer(root: builder.root)

        var start = ContinuousClock.now
        let build = Task { try await indexer.build() }
        try await Task.sleep(for: .milliseconds(20))
        build.cancel()
        let cancelledAfter = ContinuousClock.now - start
        let stopped: Result<ProjectIndexReport, any Error> = await build.result.map(\.1)
        let stoppedIn = ContinuousClock.now - start - cancelledAfter

        start = ContinuousClock.now
        let (_, report) = try await indexer.build()
        let wholeBuild = ContinuousClock.now - start
        print("C-SRC-02 cancelled after \(cancelledAfter), stopped in \(stoppedIn); a whole build \(wholeBuild)")
        XCTAssertThrowsError(try stopped.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(report, ProjectIndexReport(read: GeneratedProject.fileCount + 40))
        XCTAssertLessThan(stoppedIn, wholeBuild / 5)
    }

    /// 40 `.strings` tables of 5,000 values each, as a large app has.
    private static func writeTables(into builder: ProjectBuilder) throws {
        for language in 0..<40 {
            try writeTable(language, into: builder)
        }
    }

    private static func writeTable(_ language: Int, into builder: ProjectBuilder, last: String? = nil) throws {
        var lines = (0..<5000).map { #""key\#($0)" = "Value \#($0) in language \#(language)";"# }
        if let last { lines[4999] = #""key4999" = "\#(last)";"# }
        try builder.write("App/l\(language).lproj/Localizable.strings", lines.joined(separator: "\n"))
    }

    /// ⌘R builds the index again: what follows it, as an inspector window does twice, is not
    /// held up by the new index, whether anything changed or not. String tables in 40
    /// languages, 200,000 values, as a large app has: comparing two such indexes takes the
    /// main thread far longer than a frame.
    func test_C_SRC_02_buildingAgainDoesNotStallWhatFollowsTheIndex() async throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let builder = try ProjectBuilder()
        defer { builder.remove() }
        try GeneratedProject.write(into: builder)
        try Self.writeTables(into: builder)
        let suite = "ProjectIndexScaleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sources = ProjectSources(folders: ProjectFolders(defaults: defaults))
        let bundleID = "com.example.generated"
        sources.link(builder.root, bundleID: bundleID, appName: "Generated")
        await sources.waitForIndex(bundleID: bundleID)

        var received: [[ProjectIndex?]] = [[], []]
        let followers = (0..<2).map { follower in
            sources.index(for: bundleID).sink { received[follower].append($0) }
        }
        defer { followers.forEach { $0.cancel() } }
        var published = 0
        let publishing = sources.$indexes.dropFirst().sink { _ in published += 1 }
        defer { publishing.cancel() }
        XCTAssertEqual(received.map(\.count), [1, 1])

        // Nothing changed: nothing new to follow.
        let meter = MainThreadStallMeter()
        meter.start()
        sources.update(bundleID: bundleID)
        await sources.waitForIndex(bundleID: bundleID)
        var pause = meter.stop()
        print("C-SRC-02 built again unchanged, longest main thread pause \(Int(pause * 1000)) ms")
        XCTAssertEqual(published, 0)
        XCTAssertEqual(received.map(\.count), [1, 1])
        XCTAssertLessThanOrEqual(pause, 0.05)

        // One value changed, deep in the tables.
        try Self.writeTable(39, into: builder, last: "Changed")
        meter.start()
        sources.update(bundleID: bundleID)
        await sources.waitForIndex(bundleID: bundleID)
        pause = meter.stop()
        print("C-SRC-02 built again with one value changed, longest main thread pause \(Int(pause * 1000)) ms")
        XCTAssertEqual(published, 1)
        XCTAssertEqual(received.map(\.count), [2, 2])
        XCTAssertEqual(received[0].last??.keys.matches("Changed").map(\.key), ["key4999"])
        XCTAssertLessThanOrEqual(pause, 0.05)
    }
}
