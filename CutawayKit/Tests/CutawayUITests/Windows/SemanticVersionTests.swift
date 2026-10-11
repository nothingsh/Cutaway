import Foundation
import XCTest

@testable import CutawayUI

/// Which published release is newer than the running app (C-DIST-02), by the versions of
/// C-DIST-01.
final class SemanticVersionTests: XCTestCase {
    private func version(_ string: String) throws -> SemanticVersion {
        try XCTUnwrap(SemanticVersion(string), string)
    }

    func test_C_DIST_02_versionsAreReadInTheFormOfTheVersionNumber() throws {
        let beta = try version("1.2.3-beta.4")
        XCTAssertEqual([beta.major, beta.minor, beta.patch], [1, 2, 3])
        XCTAssertEqual(beta.beta, 4)
        XCTAssertTrue(beta.isPrerelease)
        XCTAssertFalse(try version("1.2.3").isPrerelease)
        XCTAssertEqual(beta.description, "1.2.3-beta.4")
        for string in ["1.0", "01.0.0", "1.0.0-rc.1", "v1.0.0", "", "99999999999999999999.0.0"] {
            XCTAssertNil(SemanticVersion(string), string)
        }
    }

    func test_C_DIST_02_aTagIsTheVersionAfterAV() throws {
        XCTAssertEqual(SemanticVersion(tag: "v1.0.0-beta.2"), try version("1.0.0-beta.2"))
        for tag in ["1.0.0", "V1.0.0", "vv1.0.0", "v1.0", "release-1"] {
            XCTAssertNil(SemanticVersion(tag: tag), tag)
        }
    }

    func test_C_DIST_02_versionsAreOrderedAsSemanticVersions() throws {
        let ascending = [
            "0.1.0", "0.9.9", "1.0.0-beta.1", "1.0.0-beta.2", "1.0.0-beta.10", "1.0.0", "1.0.9", "1.0.10",
            "1.9.9", "2.0.0-beta.1", "2.0.0",
        ]
        let versions = try ascending.map(version)
        for (lower, higher) in zip(versions, versions.dropFirst()) {
            XCTAssertLessThan(lower, higher)
            XCTAssertGreaterThan(higher, lower)
        }
        XCTAssertEqual(try version("1.0.0"), try version("1.0.0"))
    }

    // MARK: - Choosing the release

    private func release(_ tag: String, draft: Bool = false) -> PublishedRelease {
        PublishedRelease(
            tag: tag, page: URL(string: "https://github.com/nothingsh/Cutaway/releases/tag/\(tag)")!,
            isDraft: draft)
    }

    private func newest(_ tags: [String], over current: String) throws -> String? {
        UpdateChoice.newest(in: tags.map { release($0) }, over: try version(current))?.release.tag
    }

    func test_C_DIST_02_aReleaseSeesOnlyReleases() throws {
        let tags = ["v1.0.0", "v1.1.0-beta.1", "v1.0.1"]
        XCTAssertEqual(try newest(tags, over: "1.0.0"), "v1.0.1")
        XCTAssertNil(try newest(["v1.0.0", "v2.0.0-beta.1"], over: "1.0.0"))
    }

    func test_C_DIST_02_aBetaSeesBetasAndReleases() throws {
        XCTAssertEqual(try newest(["v1.0.0-beta.1", "v1.0.0-beta.2"], over: "1.0.0-beta.1"), "v1.0.0-beta.2")
        XCTAssertEqual(try newest(["v1.0.0-beta.2", "v1.0.0"], over: "1.0.0-beta.1"), "v1.0.0")
        XCTAssertEqual(try newest(["v1.0.0", "v1.1.0-beta.1"], over: "1.0.0-beta.3"), "v1.1.0-beta.1")
    }

    func test_C_DIST_02_draftsAndOtherTagsAreSkipped() throws {
        let releases = [release("v2.0.0", draft: true), release("nightly"), release("v1.0"), release("v1.0.1")]
        XCTAssertEqual(UpdateChoice.newest(in: releases, over: try version("1.0.0"))?.release.tag, "v1.0.1")
    }

    func test_C_DIST_02_nothingNewerIsNoUpdate() throws {
        XCTAssertNil(try newest([], over: "1.0.0"))
        XCTAssertNil(try newest(["v0.9.0", "v1.0.0"], over: "1.0.0"))
        XCTAssertNil(try newest(["v1.0.0-beta.2"], over: "1.0.0-beta.2"))
        XCTAssertNil(try newest(["v1.0.0-beta.9"], over: "1.0.0"))
    }
}
