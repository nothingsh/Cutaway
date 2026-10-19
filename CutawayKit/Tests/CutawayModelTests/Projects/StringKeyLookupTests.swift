import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel

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

    func test_C_SRC_05_theSampleProjectsTablesAreLookedUp() async throws {
        let builder = try ProjectBuilder()
        defer { builder.remove() }
        for (path, text) in SampleProject.files { try builder.write(path, text) }
        let index = await ProjectIndexer(root: builder.root).build().0
        XCTAssertEqual(index.keys.matches("首页"), [StringKeyMatch(table: "Localizable", key: "home.title")])
        XCTAssertEqual(index.keys.matches("2 items"), [StringKeyMatch(table: "Localizable", key: "items.count")])
        XCTAssertEqual(index.keys.matches("Demo Shop"),
                       [StringKeyMatch(table: "InfoPlist", key: "CFBundleDisplayName")])
        XCTAssertEqual(index.colors.matches(Color(red: 30 / 255, green: 107 / 255, blue: 1, alpha: 1)).map(\.name),
                       ["Brand/Blue"])
    }
}
