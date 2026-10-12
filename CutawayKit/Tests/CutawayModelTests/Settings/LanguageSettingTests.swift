import CutawayModel
import Foundation
import XCTest

/// C-LOC-01: the language chosen in the settings is kept where macOS keeps the language picked
/// for an app, read back from there, and resolved as the app will resolve it at its next start.
@MainActor
final class LanguageSettingTests: XCTestCase {
    private static let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]

    private var suiteName = ""
    private var defaults = UserDefaults()

    override func setUp() async throws {
        suiteName = "LanguageSettingTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func setting() -> LanguageSetting {
        LanguageSetting(defaults: defaults, domain: suiteName, languages: Self.languages)
    }

    private var kept: Any? {
        defaults.persistentDomain(forName: suiteName)?[LanguageSetting.key]
    }

    func test_C_LOC_01_aChoiceIsKeptAsTheAppsLanguagesAndReadBack() {
        let setting = setting()
        setting.choose("ja")
        XCTAssertEqual(setting.choice, "ja")
        XCTAssertEqual(kept as? [String], ["ja"])
        XCTAssertEqual(self.setting().choice, "ja")

        setting.choose(nil)
        XCTAssertNil(setting.choice)
        XCTAssertNil(kept)
        XCTAssertNil(self.setting().choice)
    }

    func test_C_LOC_01_aLanguageTheInterfaceIsNotWrittenInIsNotChosen() {
        let setting = setting()
        setting.choose("ko")
        setting.choose("fr")
        XCTAssertEqual(setting.choice, "ko")
        XCTAssertEqual(kept as? [String], ["ko"])
    }

    func test_C_LOC_01_whatSystemSettingsKeptReadsAsOneOfTheLanguages() {
        for (stored, expected) in [
            (["zh-Hant-TW"], "zh-Hant"), (["zh-Hans-CN", "en"], "zh-Hans"), (["ko-KR"], "ko"),
            (["fr"], "en"),
        ] {
            defaults.set(stored, forKey: LanguageSetting.key)
            XCTAssertEqual(setting().choice, expected, "\(stored)")
        }
    }

    func test_C_LOC_01_theNextLanguageIsTheChoiceOrTheSystems() {
        let setting = setting()
        XCTAssertEqual(setting.resolved(systemPreferences: ["ja-JP", "en-US"]), "ja")
        XCTAssertEqual(setting.resolved(systemPreferences: ["fr-FR", "ko-KR"]), "ko")
        XCTAssertEqual(setting.resolved(systemPreferences: ["fr-FR"]), "en")
        setting.choose("zh-Hant")
        XCTAssertEqual(setting.resolved(systemPreferences: ["ja-JP"]), "zh-Hant")
    }
}
