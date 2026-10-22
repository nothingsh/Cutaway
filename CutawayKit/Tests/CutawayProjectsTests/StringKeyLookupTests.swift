import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayProjects

/// C-SRC-05: the values of string tables as templates, and the keys a text is a value of.
final class StringKeyLookupTests: XCTestCase {
    private func matches(_ template: String, _ value: String) -> Bool {
        StringTemplate(template).matches(value)
    }

    func test_C_SRC_05_aValueWithoutPlaceholdersMatchesOnlyItself() {
        XCTAssertTrue(matches("Welcome back", "Welcome back"))
        XCTAssertFalse(matches("Welcome back", "Welcome back!"))
        XCTAssertFalse(matches("Welcome back", "welcome back"))
    }

    func test_C_SRC_05_placeholdersStandForSomeText() {
        XCTAssertTrue(matches("Hello, %@!", "Hello, Ann!"))
        XCTAssertFalse(matches("Hello, %@!", "Hello, !"), "a placeholder is never empty")
        XCTAssertTrue(matches("%lld items", "12 items"))
        XCTAssertTrue(matches("%@ has %lld items", "Ann has 3 items"))
        XCTAssertTrue(matches("%1$@ and %2$lld", "Ann and 3"))
        XCTAssertTrue(matches("%2$@ owes %1$.2f", "Ann owes 1.50"))
        XCTAssertTrue(matches("%#@items@ left", "3 items left"))
        XCTAssertTrue(matches("%-08.3f|%*d", "1|2"))
        // Two placeholders side by side.
        XCTAssertTrue(matches("%@%@", "ab"))
        XCTAssertFalse(matches("%@%@", "a"))
    }

    func test_C_SRC_05_aPercentSignIsText() {
        XCTAssertTrue(matches("100%%", "100%"))
        XCTAssertTrue(matches("%d%% done", "50% done"))
        XCTAssertFalse(matches("100%%", "100%%"))
        // A percent sign this does not read as a placeholder stays text.
        XCTAssertTrue(matches("50% off", "50% off"))
    }

    func test_C_SRC_05_middleLiteralsAreTakenAtTheirLeftmostPlace() {
        XCTAssertTrue(matches("%@ and %@", "a and b and c"))
        XCTAssertTrue(matches("from %@ to %@ at %@", "from a to b to c at d"))
        XCTAssertFalse(matches("from %@ to %@ at %@", "from a at b to c"))
    }

    /// A literal is found only as whole characters, which may be written composed or not.
    func test_C_SRC_05_aLiteralIsFoundOnlyAsWholeCharacters() {
        XCTAssertTrue(matches("%@e%@", "aeb"))
        XCTAssertFalse(matches("%@e%@", "ae\u{301}b"), "an e with a combining accent is another character")
        XCTAssertTrue(matches("%@e%@", "ae\u{301}eb"))
        XCTAssertTrue(matches("%@\u{E9}%@", "ae\u{301}b"), "composed and decomposed are the same character")
        XCTAssertTrue(matches("%@e\u{301}%@", "a\u{E9}b"))
        XCTAssertFalse(matches("%@a%@", "x\u{1F469}\u{200D}\u{1F469}y"))
    }

    func test_C_SRC_05_templatesOfPlaceholdersAloneAreNotCompared() {
        // They would match any text.
        let lookup = StringKeyLookup([
            value("any", "%@"), value("pair", "%1$@ %2$@"), value("named", "Hi %@"),
        ])
        XCTAssertEqual(lookup.matches("Hi Ann"), [StringKeyMatch(table: "Localizable", key: "named")])
        XCTAssertEqual(lookup.matches("Something"), [])
    }

    private func value(
        _ key: String, _ text: String, language: String = "en", table: String = "Localizable"
    ) -> LocalizedString {
        LocalizedString(table: table, key: key, language: language, value: text, file: "\(table).xcstrings")
    }

    func test_C_SRC_05_everyLanguageAndVariantCountsAndAKeyOnce() {
        let lookup = StringKeyLookup([
            value("home.title", "Home"), value("home.title", "首页", language: "zh-Hans"),
            value("items.count", "%lld item"), value("items.count", "%lld items"),
            value("items.count", "%lld 件", language: "zh-Hans"),
            value("home.title", "Home", language: "en-GB"),
        ])
        XCTAssertEqual(lookup.matches("首页"), [StringKeyMatch(table: "Localizable", key: "home.title")])
        XCTAssertEqual(lookup.matches("Home"), [StringKeyMatch(table: "Localizable", key: "home.title")])
        XCTAssertEqual(lookup.matches("3 items"), [StringKeyMatch(table: "Localizable", key: "items.count")])
        XCTAssertEqual(lookup.matches("1 item"), [StringKeyMatch(table: "Localizable", key: "items.count")])
        XCTAssertEqual(lookup.matches("3 件"), [StringKeyMatch(table: "Localizable", key: "items.count")])
    }

    func test_C_SRC_05_emptyAndBlankTextsAreNotCompared() {
        let lookup = StringKeyLookup([value("blank", " "), value("empty", "")])
        XCTAssertEqual(lookup.matches(""), [])
        XCTAssertEqual(lookup.matches(" "), [])
        XCTAssertEqual(lookup.matches("\n\t"), [])
    }

    func test_C_SRC_05_severalKeysComeByTableThenKey() {
        let lookup = StringKeyLookup([
            value("b", "OK", table: "Main"), value("z", "OK"), value("a", "OK", table: "Main"),
            value("count", "%d OK"),
        ])
        XCTAssertEqual(lookup.matches("OK").map { "\($0.table) \($0.key)" }, ["Localizable z", "Main a", "Main b"])
    }

    /// Looking up a text costs about the same however many values the tables have: 20,000
    /// values in five languages, one in ten with placeholders, and 1,000 texts looked up.
    func test_C_SRC_05_lookingUpATextDoesNotGrowWithTheTables() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let languages = ["en", "zh-Hans", "ja", "ko", "de"]
        var strings: [LocalizedString] = []
        for key in 0..<4_000 {
            for language in languages {
                let text = key % 10 == 0 ? "Item \(key) in \(language): %lld of %@" : "Item \(key) in \(language)"
                strings.append(value("key.\(key)", text, language: language, table: key < 2_000 ? "A" : "B"))
            }
        }
        let lookup = StringKeyLookup(strings)
        let texts = (0..<1_000).map { $0 % 2 == 0 ? "Item \($0 * 4) in ja" : "Item \($0 * 4) in de: 3 of 9" }
        let start = ContinuousClock.now
        var found = 0
        for text in texts { found += lookup.matches(text).count }
        let elapsed = ContinuousClock.now - start
        // The even ones are values as they are, the odd ones fill in templates; one in five
        // of each is the other kind.
        XCTAssertEqual(found, 500)
        XCTAssertLessThan(elapsed, .milliseconds(50), "1,000 look-ups took \(elapsed)")
    }

    /// The same with templates that start with a placeholder (`%@ …`, `%1$@ …`, `%d items`),
    /// whose first literal is empty, and those that start and end with one: 20,000 values in
    /// five languages, one in five a template, and 1,000 texts looked up.
    func test_C_SRC_05_templatesThatStartWithAPlaceholderDoNotGrowTheLookUp() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let lookup = StringKeyLookup(Self.placeholderFirstStrings())
        let texts = Self.placeholderFirstTexts()
        let start = ContinuousClock.now
        var found = 0
        for text in texts { found += lookup.matches(text).count }
        let elapsed = ContinuousClock.now - start
        print("C-SRC-05 1,000 look-ups among templates that start with a placeholder took \(elapsed)")
        XCTAssertEqual(found, 750)
        XCTAssertLessThan(elapsed, .milliseconds(50), "1,000 look-ups took \(elapsed)")
    }

    /// Whichever literal a template is found by, the keys are those comparing the text with
    /// every value gives.
    func test_C_SRC_05_theKeysAreThoseOfComparingEveryValue() {
        var strings = Self.placeholderFirstStrings(keys: 400)
        for (key, text) in [
            "%@", "%@ %@", "%d items", "%1$@ owes %2$@", "%@ and %@", "%@%@ left", "Hi %@", "%@ at %@!",
            "x%@", "%@x", "%@ x %@ y %@", "%@ y %@", "100%%", "%@ 100%%", "%lld件", "%@ items",
            // A literal that is part of a character, composed or decomposed.
            "%@e%@", "%@\u{E9}%@", "%@e\u{301}%@", "e%@",
        ].enumerated() {
            strings.append(value("extra.\(key)", text))
        }
        let lookup = StringKeyLookup(strings)
        let texts = Self.placeholderFirstTexts(count: 200) + [
            "3 items", "Ann owes Bob", "a and b and c", "ab left", "Hi Ann", "a at b!", "xy", "yx", "a x b y c",
            "a y b", "100%", "x 100%", "3件", "Ann items", "x", " items", "a  at  b!", "",
            "aeb", "ae\u{301}b", "a\u{E9}b", "e\u{301}x", "ex", "ae\u{301}eb",
        ]
        let compared = strings
            .map { (template: StringTemplate($0.value), match: StringKeyMatch(table: $0.table, key: $0.key)) }
            .filter { $0.template.placeholderCount == 0 || $0.template.hasLiteralText }
        for text in texts {
            var expected: Set<StringKeyMatch> = []
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                for value in compared where value.template.matches(text) {
                    expected.insert(value.match)
                }
            }
            XCTAssertEqual(lookup.matches(text), expected.sorted(), text)
        }
    }

    /// Values of `keys` keys in five languages: one in five starts with a placeholder (one in
    /// ten ends with one too), the rest are plain.
    private static func placeholderFirstStrings(keys: Int = 4_000) -> [LocalizedString] {
        let languages = ["en", "zh-Hans", "ja", "ko", "de"]
        var strings: [LocalizedString] = []
        for key in 0..<keys {
            for language in languages {
                let text = switch key % 10 {
                case 0: "%lld of %@: item \(key) in \(language)"
                case 5: "%1$@ item \(key) in \(language) %2$@"
                default: "Item \(key) in \(language)"
                }
                strings.append(LocalizedString(
                    table: key < keys / 2 ? "A" : "B", key: "key.\(key)", language: language, value: text,
                    file: "Localizable.xcstrings"))
            }
        }
        return strings
    }

    /// A quarter plain values, a quarter templates that start with a placeholder, a quarter
    /// those that start and end with one, and a quarter that match nothing.
    private static func placeholderFirstTexts(count: Int = 1_000) -> [String] {
        (0..<count).map { number in
            let key = number / 4 * 10
            return switch number % 4 {
            case 0: "Item \(key + 1) in ja"
            case 1: "3 of 9: item \(key) in de"
            case 2: "Ann item \(key + 5) in ko !"
            default: "Nothing \(key) at all"
            }
        }
    }

    func test_C_SRC_05_theSampleProjectsTablesAreLookedUp() async throws {
        let builder = try ProjectBuilder()
        defer { builder.remove() }
        for (path, text) in SampleProject.files { try builder.write(path, text) }
        let index = try await ProjectIndexer(root: builder.root).build().0
        XCTAssertEqual(index.keys.matches("首页"), [StringKeyMatch(table: "Localizable", key: "home.title")])
        XCTAssertEqual(index.keys.matches("2 items"), [StringKeyMatch(table: "Localizable", key: "items.count")])
        XCTAssertEqual(index.keys.matches("Demo Shop"),
                       [StringKeyMatch(table: "InfoPlist", key: "CFBundleDisplayName")])
        XCTAssertEqual(index.colors.matches(Color(red: 30 / 255, green: 107 / 255, blue: 1, alpha: 1)).map(\.name),
                       ["Brand/Blue"])
    }
}
