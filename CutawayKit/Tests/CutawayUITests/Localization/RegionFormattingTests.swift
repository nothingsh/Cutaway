import CutawayModel
import CutawayTestSupport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayUI

/// What follows the region and what does not (C-LOC-02): the values a developer reads against
/// code are written the same everywhere; dates and counts are written as the region writes
/// them.
///
/// A process cannot change its region once it runs, so the comparison runs this test bundle
/// again in a child `xctest` with `-AppleLocale`, once per region, and compares what the
/// child wrote.
final class RegionFormattingTests: XCTestCase {
    private static let outputVariable = "CUTAWAY_REGION_PROBE_OUTPUT"
    private static let probe = "CutawayUITests.RegionFormattingTests/test_C_LOC_02_probe"
    /// 2026-10-06 08:30 UTC.
    private static let savedAt = Date(timeIntervalSince1970: 1_791_275_400)
    private static let app = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")

    override func tearDown() {
        Localization.override = nil
        super.tearDown()
    }

    // MARK: - In the region's child process

    /// What the child writes: the region it ran in, the values that must not change, and the
    /// texts that follow the region. Skipped unless run as the child.
    func test_C_LOC_02_probe() throws {
        guard let output = ProcessInfo.processInfo.environment[Self.outputVariable] else {
            throw XCTSkip("run by the other tests, in a region of their choosing")
        }
        var values: [String] = []
        // Layer 3's attributes in `hierarchy` (C-ATTR-02) and its constraints.
        let detail = try Fixtures.panelDetail(of: 3)
        for group in detail.attributeGroups {
            for attribute in group.attributes {
                values.append(
                    "\(attribute.id ?? ""): " + AttributeText.text(of: attribute.value))
            }
        }
        let tree = try LayerTree(try Fixtures.hierarchy())
        for id in [UInt64(3), 4, 6] {
            for constraint in try Fixtures.constraints(of: id) {
                let row = ConstraintRow(constraint, selected: id, tree: tree)
                values.append("\(row.equation) \(row.details ?? "") \(row.guideOwners)")
            }
        }
        values += LayerSummary(tree, 3).map { [$0.size ?? ""] } ?? []
        // The measurement's readouts (C-PREV-10).
        values += [0, 0.04, 26.5, 68, 1234.56, -3.25].map(PreviewPaneText.distanceText)
        let probe: [String: Any] = [
            "region": Locale.current.identifier,
            "values": values,
            "count": PreviewPaneText.countText(1234, of: 5000),
            "subtitle": InspectorWindowTitle(
                archive: URL(fileURLWithPath: "/tmp/Demo.cutaway"), app: Self.app,
                savedAt: Self.savedAt
            ).subtitle,
            "archiveName": InspectorWindowTitle.archiveName(appName: "Demo", at: Self.savedAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: probe)
        try data.write(to: URL(fileURLWithPath: output))
    }

    // MARK: - Comparing regions

    func test_C_LOC_02_valuesReadTheSameWhereTheDecimalPointIsAComma() throws {
        let english = try probe(region: "en_US")
        let german = try probe(region: "de_DE")
        XCTAssertEqual(english["region"] as? String, "en_US")
        XCTAssertEqual(german["region"] as? String, "de_DE", "the child ran in the region")
        let values = try XCTUnwrap(english["values"] as? [String])
        XCTAssertGreaterThan(values.count, 20)
        XCTAssertEqual(german["values"] as? [String], values)
        XCTAssertTrue(values.contains("26.5"), "a point, not a comma")
        XCTAssertTrue(values.contains("1234.6"), "no thousands separator")
        XCTAssertEqual(german["archiveName"] as? String, english["archiveName"] as? String)
    }

    func test_C_LOC_02_datesAndCountsFollowTheRegion() throws {
        let english = try probe(region: "en_US")
        let german = try probe(region: "de_DE")
        XCTAssertEqual(english["count"] as? String, "1,234 / 5,000")
        XCTAssertEqual(german["count"] as? String, "1.234 / 5.000")
        let englishSubtitle = try XCTUnwrap(english["subtitle"] as? String)
        let germanSubtitle = try XCTUnwrap(german["subtitle"] as? String)
        XCTAssertNotEqual(englishSubtitle, germanSubtitle)
        XCTAssertTrue(germanSubtitle.contains("Okt"), germanSubtitle)
        XCTAssertTrue(englishSubtitle.contains("Saved Oct"), englishSubtitle)
    }

    /// Runs the probe in a child `xctest` in `region` and reads what it wrote.
    private func probe(region: String) throws -> [String: Any] {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutaway-region-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        // The region first: xctest takes the last argument as the bundle.
        process.arguments = [
            "-AppleLocale", region, "-XCTest", Self.probe, Bundle(for: Self.self).bundlePath,
        ]
        // Under xcodebuild the environment names the test session; a child inheriting it waits
        // ten minutes for that session's IDE and exits. The child runs as a plain xctest.
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("XCTest") }
        environment[Self.outputVariable] = output.path
        process.environment = environment
        let log = Pipe()
        process.standardOutput = log
        process.standardError = log
        try process.run()
        let said = log.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(bytes: said, encoding: .utf8) ?? ""
            XCTFail("the probe in \(region) failed:\n\(text.prefix(1500))")
            throw CancellationError()
        }
        let data = try Data(contentsOf: output)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - In this process

    func test_C_LOC_02_countsUseTheRegionsSeparators() {
        let germany = Locale(identifier: "de_DE")
        XCTAssertEqual(
            PreviewPaneText.countText(1234, of: 5000, locale: germany), "1.234 / 5.000")
        XCTAssertEqual(
            PreviewPaneText.progressText(DetailProgress(completed: 12, total: 40), locale: germany),
            "12 / 40")
    }

    func test_C_LOC_02_theSubtitleIsOneSentenceInTheInterfacesLanguage() {
        let url = URL(fileURLWithPath: "/tmp/Demo.cutaway")
        let china = Locale(identifier: "zh_Hans_CN")
        let date = Self.savedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, locale: china))
        Localization.override = "zh-Hans"
        let subtitle = InspectorWindowTitle(
            archive: url, app: Self.app, savedAt: Self.savedAt, locale: china
        ).subtitle
        XCTAssertTrue(subtitle.hasSuffix("存储于 \(date)"), subtitle)
    }
}
