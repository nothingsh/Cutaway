import Foundation

/// Reads string tables (C-SRC-02): a String Catalog, every language and every variant of
/// each key; and a `.strings` file, in the language of the `.lproj` folder it is in.
enum StringTableReader {
    struct NotReadable: Error {}

    /// The values of a String Catalog (`.xcstrings`). A key with no value in the source
    /// language has the key itself as that value, as Xcode does.
    static func catalog(_ data: Data, table: String, file: String) throws -> [LocalizedString] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else { throw NotReadable() }
        let source = root["sourceLanguage"] as? String
        var values: [LocalizedString] = []
        for key in strings.keys.sorted() {
            let entry = strings[key] as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any] ?? [:]
            for language in localizations.keys.sorted() {
                for value in unitValues(localizations[language]) {
                    values.append(.init(table: table, key: key, language: language, value: value, file: file))
                }
            }
            if let source, localizations[source] == nil, !key.isEmpty {
                values.append(.init(table: table, key: key, language: source, value: key, file: file))
            }
        }
        return values
    }

    /// The values of a localization: its string unit, and those of its variations, which may
    /// hold variations of their own (by device, then by plural).
    private static func unitValues(_ object: Any?) -> [String] {
        guard let localization = object as? [String: Any] else { return [] }
        var values: [String] = []
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            values.append(value)
        }
        if let variations = localization["variations"] as? [String: Any] {
            for kind in variations.keys.sorted() {
                guard let cases = variations[kind] as? [String: Any] else { continue }
                for name in cases.keys.sorted() {
                    values += unitValues(cases[name])
                }
            }
        }
        return values
    }

    /// The values of a `.strings` file: old-style text, UTF-16 or binary.
    static func strings(_ data: Data, table: String, language: String?, file: String) throws -> [LocalizedString] {
        guard let pairs = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw NotReadable() }
        return pairs.keys.sorted().compactMap { key in
            (pairs[key] as? String).map {
                LocalizedString(table: table, key: key, language: language, value: $0, file: file)
            }
        }
    }
}
