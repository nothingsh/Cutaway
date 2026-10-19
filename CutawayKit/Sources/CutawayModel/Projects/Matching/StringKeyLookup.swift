import Foundation

/// A key of a string table that a text is a value of (C-SRC-05).
public struct StringKeyMatch: Equatable, Hashable, Comparable, Sendable {
    /// The table, the file's name without its extension.
    public var table: String
    public var key: String

    public init(table: String, key: String) {
        self.table = table
        self.key = key
    }

    /// By table, then by key.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.table, lhs.key) < (rhs.table, rhs.key)
    }
}

/// The values of a project's string tables, every language and variant, by what they say
/// (C-SRC-05): made once when the index is built.
public struct StringKeyLookup: Equatable, Sendable {
    /// Values without placeholders, as they are.
    private var exact: [String: Set<StringKeyMatch>] = [:]
    /// Templates with placeholders, by their first literal: a text can only be a value of
    /// those whose first literal it starts with.
    private var templates: [String: [Template]] = [:]
    /// The lengths of those first literals, in characters, shortest first.
    private var firstLengths: [Int] = []

    private struct Template: Equatable, Sendable {
        var template: StringTemplate
        var match: StringKeyMatch
    }

    public init(_ strings: [LocalizedString] = []) {
        for string in strings {
            let match = StringKeyMatch(table: string.table, key: string.key)
            let template = StringTemplate(string.value)
            if template.placeholderCount == 0 {
                exact[string.value, default: []].insert(match)
            } else if template.hasLiteralText {
                templates[template.literals[0], default: []].append(Template(template: template, match: match))
            }
        }
        firstLengths = Set(templates.keys.map(\.count)).sorted()
    }

    /// The keys `value` is a value of, by table and key; none for a text that is empty or
    /// only white space. A key matched in several languages counts once.
    public func matches(_ value: String) -> [StringKeyMatch] {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var found = exact[value] ?? []
        // Each prefix of the text as long as some first literal, found in one pass.
        var index = value.startIndex
        var length = 0
        for wanted in firstLengths {
            while length < wanted, index < value.endIndex {
                index = value.index(after: index)
                length += 1
            }
            guard length == wanted else { break }
            for candidate in templates[String(value[..<index])] ?? []
                where !found.contains(candidate.match) && candidate.template.matches(value)
            {
                found.insert(candidate.match)
            }
        }
        return found.sorted()
    }
}
