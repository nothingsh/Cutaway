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
///
/// A template is filed under one of its literals, which a text it matches must hold: its
/// first when that is not empty, which the text starts with; else its last, which the text
/// ends with; else its longest, somewhere in the text. A look-up takes the text's prefixes,
/// suffixes and parts as long as some literal filed so, and compares the text only with the
/// templates filed under them: what it costs follows the text's length, not the tables'.
public struct StringKeyLookup: Sendable {
    /// Values without placeholders, as they read.
    private var exact: [String: Keys] = [:]
    /// Templates by their first literal.
    private var byFirst = Shelf()
    /// Templates with an empty first literal, by their last.
    private var byLast = Shelf()
    /// Templates with empty first and last literals, by their longest literal between.
    private var byMiddle = Shelf()

    /// The keys of a value: almost always one, kept without an allocation of its own.
    private enum Keys: Sendable {
        case one(StringKeyMatch)
        /// Several, each once.
        case several([StringKeyMatch])

        func adding(_ match: StringKeyMatch) -> Self {
            switch self {
            case .one(let first): first == match ? self : .several([first, match])
            case .several(let all): all.contains(match) ? self : .several(all + [match])
            }
        }

        var all: [StringKeyMatch] {
            switch self {
            case .one(let match): [match]
            case .several(let all): all
            }
        }
    }

    private struct Template: Sendable {
        var template: StringTemplate
        var match: StringKeyMatch
    }

    /// Templates by a literal, with the literals' lengths in characters, shortest first. Keyed
    /// by substrings, so that a part of a text is looked up without being copied.
    private struct Shelf: Sendable {
        var templates: [Substring: [Template]] = [:]
        var lengths: [Int] = []

        mutating func add(_ template: Template, under literal: String) {
            templates[Substring(literal), default: []].append(template)
        }

        mutating func close() {
            lengths = Set(templates.keys.map(\.count)).sorted()
        }
    }

    public init(_ strings: [LocalizedString] = []) {
        for string in strings {
            let match = StringKeyMatch(table: string.table, key: string.key)
            let template = StringTemplate(string.value)
            let literals = template.literals
            if template.placeholderCount == 0 {
                // `%%` reads as one percent sign, as the template does.
                exact[literals[0]] = exact[literals[0]].map { $0.adding(match) } ?? .one(match)
            } else if template.hasLiteralText {
                let filed = Template(template: template, match: match)
                // swiftlint:disable:next force_unwrapping
                let first = literals.first!, last = literals.last!
                if !first.isEmpty {
                    byFirst.add(filed, under: first)
                } else if !last.isEmpty {
                    byLast.add(filed, under: last)
                } else {
                    // Some literal has text that is not white space: one in the middle.
                    // swiftlint:disable:next force_unwrapping
                    let longest = literals.max { $0.count < $1.count }!
                    byMiddle.add(filed, under: longest)
                }
            }
        }
        byFirst.close()
        byLast.close()
        byMiddle.close()
    }

    /// The keys `value` is a value of, by table and key; none for a text that is empty or
    /// only white space. A key matched in several languages counts once.
    public func matches(_ value: String) -> [StringKeyMatch] {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var found = Set(exact[value]?.all ?? [])
        // Where each character starts, and the end: the text's parts by their bounds.
        let bounds = Array(value.indices) + [value.endIndex]
        let count = bounds.count - 1
        func compare(_ candidates: [Template]?) {
            for candidate in candidates ?? []
                where !found.contains(candidate.match) && candidate.template.matches(value, count: count)
            {
                found.insert(candidate.match)
            }
        }
        for length in byFirst.lengths {
            guard length <= count else { break }
            compare(byFirst.templates[value[..<bounds[length]]])
        }
        for length in byLast.lengths {
            guard length <= count else { break }
            compare(byLast.templates[value[bounds[count - length]...]])
        }
        // A part may be found at several places, or under several lengths: its templates are
        // compared once.
        var compared: Set<Substring> = []
        for length in byMiddle.lengths {
            guard length <= count else { break }
            for start in 0...(count - length) {
                let part = value[bounds[start]..<bounds[start + length]]
                guard let candidates = byMiddle.templates[part], compared.insert(part).inserted else { continue }
                compare(candidates)
            }
        }
        return found.sorted()
    }
}
