import XCTest

@testable import CutawayUI

/// The restart the settings window's General page offers after a new language is chosen
/// (C-LOC-01).
@MainActor
final class LanguageSettingsPageTests: XCTestCase {
    func test_C_LOC_01_theRestartWaitsForTheAppToEndThenOpensIt() {
        let arguments = Relaunch.arguments(waitingFor: 4321, thenOpening: "/Applications/Cut away.app")
        XCTAssertEqual(arguments.first, "-c")
        XCTAssertEqual(Array(arguments.suffix(2)), ["4321", "/Applications/Cut away.app"])
        let script = arguments[1]
        XCTAssertTrue(script.contains(#"kill -0 "$1""#))
        XCTAssertTrue(script.hasSuffix(#"open "$2""#))
        XCTAssertFalse(script.contains("Cut away"), "the path is a parameter, not part of the script")
    }
}
