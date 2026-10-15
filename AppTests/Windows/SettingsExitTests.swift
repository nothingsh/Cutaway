import AppKit
import CutawayModel
import CutawayUI
import XCTest

/// End to end in the running app: Cutaway › Settings… (⌘,) opens the one
/// settings window (C-PREF-01), and the tests' settings are their own, at the defaults.
final class SettingsExitTests: XCTestCase {
    @MainActor
    func test_C_PREF_01_theTestsSettingsAreNotTheUsers() throws {
        let settings = try AppWindows.coordinator().settings
        XCTAssertEqual(settings.inspectionStart, InspectionStart())
        let key = AppSettings.Key.newInspectionMode
        let users = UserDefaults.standard.object(forKey: key) as? String
        settings.newInspectionMode = .threeD
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? String, users)
        settings.restorePreviewDefaults()
    }

    /// The language chosen in the tests' settings is kept in their own domain, not the app's,
    /// where macOS would read it at the next launch (C-LOC-01).
    @MainActor
    func test_C_LOC_01_theTestsLanguageChoiceIsNotTheApps() throws {
        let language = try AppWindows.coordinator().language
        XCTAssertNil(language.choice)
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let apps = UserDefaults.standard.persistentDomain(forName: domain)?[LanguageSetting.key] as? [String]
        language.choose("ko")
        XCTAssertEqual(
            UserDefaults.standard.persistentDomain(forName: domain)?[LanguageSetting.key] as? [String], apps)
        language.choose(nil)
    }
}
