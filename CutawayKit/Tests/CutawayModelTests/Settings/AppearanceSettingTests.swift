import CutawayModel
import Foundation
import XCTest

/// C-PREF-03: the appearance is kept in the user defaults, read back and read forgivingly, and
/// is not one of the Preview page's settings.
@MainActor
final class AppearanceSettingTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults()

    override func setUp() async throws {
        suiteName = "AppearanceSettingTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_C_PREF_03_aChoiceIsKeptAndReadBack() {
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        XCTAssertEqual(defaults.string(forKey: AppSettings.Key.appearance), "dark")
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .dark)
        settings.appearance = .light
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .light)

        // The system's again: nothing is kept.
        settings.appearance = .system
        XCTAssertNil(defaults.object(forKey: AppSettings.Key.appearance))
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .system)
    }

    func test_C_PREF_03_whatCannotBeReadIsTheSystems() {
        for kept in ["sepia", "", "Dark"] as [Any] + [true, 1] {
            defaults.set(kept, forKey: AppSettings.Key.appearance)
            XCTAssertEqual(AppSettings(defaults: defaults).appearance, .system, "\(kept)")
        }
    }

    func test_C_PREF_03_thePreviewPagesDefaultsLeaveItAlone() {
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        XCTAssertTrue(settings.isShowingPreviewDefaults)
        settings.restorePreviewDefaults()
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .dark)
    }
}
