import Foundation

/// Which language the interface's text is in (C-LOC-01).
///
/// The text follows the language macOS chose for the app's main bundle, from the system's list
/// or the language picked for Cutaway in System Settings, so that it agrees with the text
/// AppKit writes itself (the Services menu, Enter Full Screen). A language this package has no
/// table for falls back to English. Under `swift test` the main bundle is `xctest`, which has
/// only English, so the package's tests always run in English.
enum Localization {
    /// The languages the interface is written in; the first is the development language.
    static let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]

    /// For tests only: a language to use instead of the app's.
    nonisolated(unsafe) static var override: String?

    /// The language in use.
    static var language: String {
        if let override { return override }
        let chosen = Bundle.main.preferredLocalizations.first ?? "en"
        return Bundle.preferredLocalizations(from: languages, forPreferences: [chosen]).first ?? "en"
    }

    /// The table of `language`.
    static var bundle: Bundle { table(for: language) }

    /// The table of one language; the package's own bundle when it has none.
    static func table(for language: String) -> Bundle {
        let lock = tablesLock
        lock.lock()
        defer { lock.unlock() }
        if let table = tables[language] { return table }
        let table = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            ?? Bundle.module
        tables[language] = table
        return table
    }

    private nonisolated(unsafe) static var tables: [String: Bundle] = [:]
    private static let tablesLock = NSLock()
}

/// The text for `key` in the interface's language, with `arguments` put into its placeholders.
///
/// The key is a literal so that the test that matches the source against the table finds every
/// key. Numbers are written without a locale: an ID or a value reads the same everywhere
/// (C-LOC-02). A count that follows the region is formatted first and passed as text.
func localized(_ key: StaticString, _ arguments: any CVarArg...) -> String {
    let format = Localization.bundle.localizedString(forKey: "\(key)", value: nil, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: nil, arguments: arguments)
}
