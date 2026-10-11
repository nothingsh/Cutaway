import Foundation
import XCTest

@testable import CutawayUI

/// The interface's table of text, as it is in the source tree (C-LOC-01): every key in every
/// language, the translations' placeholders the same as the English, and the keys the same as
/// the ones the source uses.
final class StringCatalogTests: XCTestCase {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Localization
        .deletingLastPathComponent()  // CutawayUITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/CutawayUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    private func catalog() throws -> StringCatalog {
        try StringCatalog(contentsOf: Self.catalogURL)
    }

    func test_C_LOC_01_everyKeyHasEveryLanguageTranslated() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.sourceLanguage, "en")
        XCTAssertFalse(catalog.entries.isEmpty)
        for (key, entry) in catalog.entries.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(
                entry.languages, Set(Localization.languages), "\(key) has other languages")
            for language in Localization.languages {
                let texts = entry.texts(in: language)
                XCTAssertFalse(texts.isEmpty, "\(key) has no \(language)")
                for text in texts {
                    XCTAssertEqual(text.state, "translated", "\(key) in \(language)")
                    XCTAssertFalse(
                        text.value.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(key) in \(language) is empty")
                }
            }
        }
    }

    func test_C_LOC_01_translationsHaveTheEnglishPlaceholders() throws {
        for (key, entry) in try catalog().entries.sorted(by: { $0.key < $1.key }) {
            let english = try entry.placeholders(in: "en")
            for language in Localization.languages.dropFirst() {
                XCTAssertEqual(
                    try entry.placeholders(in: language), english, "\(key) in \(language)")
            }
        }
    }

    func test_C_LOC_01_theSourceUsesExactlyTheKeysOfTheTable() throws {
        let used = try Self.keysInSource()
        let table = Set(try catalog().entries.keys)
        XCTAssertEqual(used.subtracting(table).sorted(), [], "used but not in the table")
        XCTAssertEqual(table.subtracting(used).sorted(), [], "in the table but not used")
    }

    /// Every `localized("…"` in CutawayUI's source.
    private static func keysInSource() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: #"\blocalized\(\s*"([^"]+)""#)
        var keys = Set<String>()
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                if let key = Range(match.range(at: 1), in: text) { keys.insert(String(text[key])) }
            }
        }
        return keys
    }
}

/// A `.xcstrings` file, read as far as these tests need.
struct StringCatalog {
    struct Text {
        var state: String
        var value: String
    }

    struct Entry {
        var localizations: [String: Any]

        var languages: Set<String> { Set(localizations.keys) }

        /// The texts of one language: its single value, or each plural variation, and the
        /// variations of its substitutions.
        func texts(in language: String) -> [Text] {
            guard let localization = localizations[language] as? [String: Any] else { return [] }
            var texts = Self.texts(of: localization)
            let substitutions = localization["substitutions"] as? [String: [String: Any]] ?? [:]
            for substitution in substitutions.values { texts += Self.texts(of: substitution) }
            return texts
        }

        /// The placeholders of one language: for each argument, its number and its type, across
        /// all the language's texts. A substitution (`%#@name@`) stands for its own argument.
        func placeholders(in language: String) throws -> Set<String> {
            guard let localization = localizations[language] as? [String: Any] else { return [] }
            let substitutions = localization["substitutions"] as? [String: [String: Any]] ?? [:]
            var found = Set<String>()
            for text in texts(in: language) {
                found.formUnion(try Placeholders.of(text.value, substitutions: substitutions))
            }
            return found
        }

        private static func texts(of node: [String: Any]) -> [Text] {
            if let unit = node["stringUnit"] as? [String: Any] {
                return [Text(state: unit["state"] as? String ?? "", value: unit["value"] as? String ?? "")]
            }
            let plural = (node["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]]
            return (plural ?? [:]).sorted { $0.key < $1.key }.flatMap { texts(of: $0.value) }
        }
    }

    var sourceLanguage: String
    var entries: [String: Entry]

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        sourceLanguage = root["sourceLanguage"] as? String ?? ""
        let strings = try XCTUnwrap(root["strings"] as? [String: [String: Any]])
        entries = strings.mapValues {
            Entry(localizations: $0["localizations"] as? [String: Any] ?? [:])
        }
    }
}

/// The format placeholders of a text, as "argument:type".
enum Placeholders {
    private static let pattern = try? NSRegularExpression(
        pattern: #"%(?:(\d+)\$)?(?:#@(\w+)@|[-+ 0#']*\d*(?:\.\d+)?(lld|ld|d|@|f|%))"#)

    static func of(_ text: String, substitutions: [String: [String: Any]]) throws -> Set<String> {
        let pattern = try XCTUnwrap(pattern)
        var found = Set<String>()
        var next = 1
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            let position = Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
            if let name = Range(match.range(at: 2), in: text).map({ String(text[$0]) }) {
                let substitution = try XCTUnwrap(substitutions[name], "no substitution \(name)")
                let argument = try XCTUnwrap(substitution["argNum"] as? Int)
                let type = try XCTUnwrap(substitution["formatSpecifier"] as? String)
                found.insert("\(argument):\(type)")
                continue
            }
            let type = Range(match.range(at: 3), in: text).map { String(text[$0]) } ?? ""
            if type == "%" { continue }
            let argument = position ?? next
            next = argument + 1
            found.insert("\(argument):\(type)")
        }
        return found
    }
}
