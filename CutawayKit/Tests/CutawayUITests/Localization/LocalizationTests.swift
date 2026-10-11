import Foundation
import XCTest

@testable import CutawayUI

/// The compiled tables and the choice of language (C-LOC-01).
final class LocalizationTests: XCTestCase {
    override func tearDown() {
        Localization.override = nil
        super.tearDown()
    }

    func test_C_LOC_01_thePackageIsBuiltWithTheFiveLanguages() {
        XCTAssertEqual(Set(Bundle.module.localizations), Set(Localization.languages))
        XCTAssertEqual(Localization.languages.first, "en")
    }

    func test_C_LOC_01_everyLanguageFindsEveryKey() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try StringCatalog(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/CutawayUI/Resources/Localizable.xcstrings"))
        for language in Localization.languages {
            let table = Localization.table(for: language)
            XCTAssertNotEqual(table, Bundle.module, "no table for \(language)")
            for key in catalog.entries.keys {
                let text = table.localizedString(forKey: key, value: "\u{0}missing", table: nil)
                XCTAssertNotEqual(text, "\u{0}missing", "\(key) in \(language)")
            }
        }
    }

    /// The language the app's main bundle was given decides; one without a table is English.
    func test_C_LOC_01_theLanguageFollowsTheSystemAndFallsBackToEnglish() {
        let expected = [
            "en-US": "en", "en-GB": "en", "zh-Hans-CN": "zh-Hans", "zh-Hans-SG": "zh-Hans",
            "zh-CN": "zh-Hans", "zh-Hant-TW": "zh-Hant", "zh-TW": "zh-Hant", "zh-HK": "zh-Hant",
            "ja-JP": "ja", "ko-KR": "ko", "fr-FR": "en", "de": "en",
        ]
        for (chosen, language) in expected {
            XCTAssertEqual(
                Bundle.preferredLocalizations(from: Localization.languages, forPreferences: [chosen])
                    .first, language, chosen)
        }
    }

    func test_C_LOC_01_thePackageTestsRunInEnglish() {
        XCTAssertEqual(Localization.language, "en")
    }

    func test_C_LOC_01_anOverrideChangesTheLanguage() {
        Localization.override = "ja"
        XCTAssertEqual(Localization.language, "ja")
        XCTAssertEqual(Localization.bundle, Localization.table(for: "ja"))
    }
}
