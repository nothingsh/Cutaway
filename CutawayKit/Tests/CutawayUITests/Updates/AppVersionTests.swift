import Foundation
import XCTest

@testable import CutawayUI

/// The forms of the version and the build (C-DIST-01).
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
}
