import Foundation
import XCTest

@testable import CutawayUI

/// The version and the build: their forms, and the one place they are read from (C-DIST-01).
final class AppVersionTests: XCTestCase {
    func test_C_DIST_01_versionsAreSemanticWithAnOptionalBeta() {
        for version in ["1.0.0", "0.1.0", "1.0.0-beta.1", "10.20.30-beta.12"] {
            XCTAssertTrue(AppVersion.isValid(version: version), version)
        }
        for version in [
            "1.0", "1.0.0.0", "01.0.0", "1.00.0", "1.0.0-beta", "1.0.0-beta.0", "1.0.0-beta.01",
            "1.0.0-rc.1", "v1.0.0", "1.0.0 ", "", "١.٠.٠",
        ] {
            XCTAssertFalse(AppVersion.isValid(version: version), version)
        }
    }

    func test_C_DIST_01_buildsArePositiveIntegers() {
        for build in ["1", "42", "1000"] {
            XCTAssertTrue(AppVersion.isValid(build: build), build)
        }
        for build in ["0", "01", "1.2", "-1", "+1", " 1", "", "١"] {
            XCTAssertFalse(AppVersion.isValid(build: build), build)
        }
    }

    func test_C_DIST_01_theVersionIsReadFromTheBundle() throws {
        let complete = try bundle(info: [
            "CFBundleIdentifier": "dev.cutaway.versiontest.complete",
            "CFBundleShortVersionString": "1.0.0-beta.1", "CFBundleVersion": "7",
        ])
        XCTAssertEqual(AppVersion(bundle: complete).version, "1.0.0-beta.1")
        XCTAssertEqual(AppVersion(bundle: complete).build, "7")

        let empty = try bundle(info: ["CFBundleIdentifier": "dev.cutaway.versiontest.empty"])
        XCTAssertEqual(AppVersion(bundle: empty).version, "")
        XCTAssertEqual(AppVersion(bundle: empty).build, "")
    }

    @MainActor
    func test_C_DIST_01_theAboutPanelShowsTheVersionAndTheBuild() {
        let options = AboutPanel.options(
            info: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "9"], icon: nil)
        XCTAssertEqual(options[.applicationVersion] as? String, "1.2.3")
        XCTAssertEqual(options[.version] as? String, "9")
    }

    /// A bundle on disk with only an Info.plist.
    private func bundle(info: [String: String]) throws -> Bundle {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppVersionTests-\(UUID().uuidString).bundle")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let contents = folder.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: folder))
    }
}
