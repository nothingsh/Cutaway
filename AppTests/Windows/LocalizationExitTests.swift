import AppKit
import XCTest

/// End to end in the built app (C-LOC-01): the app and the interface's
/// table carry the five languages, the Info.plist strings are translated, and the tests run in
/// English. How the app looks in each language is checked by a person.
final class LocalizationExitTests: XCTestCase {
    private static let languages: Set = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]

    func test_C_LOC_01_theAppHasTheFiveLanguages() {
        XCTAssertEqual(Set(Bundle.main.localizations).subtracting(["Base"]), Self.languages)
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
    }

    func test_C_LOC_01_theInterfacesTableIsInTheAppWithTheFiveLanguages() throws {
        let bundles = Bundle.main.urls(forResourcesWithExtension: "bundle", subdirectory: nil) ?? []
        let url = try XCTUnwrap(bundles.first { $0.lastPathComponent.contains("CutawayUI") })
        let table = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(Set(table.localizations), Self.languages)
    }

    func test_C_LOC_01_theInfoPlistStringsAreTranslated() throws {
        for language in Self.languages {
            let path = try XCTUnwrap(
                Bundle.main.path(
                    forResource: "InfoPlist", ofType: "strings", inDirectory: nil,
                    forLocalization: language),
                language)
            let strings = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            for key in ["NSHumanReadableCopyright", "Cutaway Archive"] {
                XCTAssertFalse((strings[key] ?? "").isEmpty, "\(key) in \(language)")
            }
        }
    }

    @MainActor
    func test_C_LOC_01_theTestsRunInEnglish() {
        XCTAssertEqual(Bundle.main.preferredLocalizations.first, "en")
        let titles = NSApp.mainMenu?.items.compactMap { $0.submenu?.title } ?? []
        XCTAssertEqual(titles.dropFirst(), ["File", "Edit", "View", "Window", "Help"])
    }
}
