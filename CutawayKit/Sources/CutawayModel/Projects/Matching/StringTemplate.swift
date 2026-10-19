import Foundation

/// A value of a string table as a template (C-SRC-05): literal text between format
/// placeholders, each of which stands for some non-empty text.
struct StringTemplate: Equatable, Sendable {
    /// The literal text around the placeholders: one more than there are placeholders.
    private(set) var literals: [String]

    var placeholderCount: Int { literals.count - 1 }

    /// Whether some literal text is not white space. A template without any would match every
    /// text, so it is not compared.
    var hasLiteralText: Bool {
        literals.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    init(_ text: String) {
        var literals = [""]
        var characters = Substring(text)
        while let first = characters.first {
            guard first == "%" else {
                literals[literals.count - 1].append(first)
                characters.removeFirst()
                continue
            }
            let rest = characters.dropFirst()
            if rest.first == "%" {
                literals[literals.count - 1].append("%")
                characters = rest.dropFirst()
            } else if let end = Self.placeholderEnd(rest) {
                literals.append("")
                characters = rest[end...]
            } else {
                // Not a placeholder this reads: the percent sign is text.
                literals[literals.count - 1].append("%")
                characters = rest
            }
        }
        self.literals = literals
    }

    /// Where a placeholder that starts after its `%` ends, or nil when none does: printf's
    /// form with `%@` (`%1$@`, `%-08.3lld`, `%*d`), or a String Catalog substitution
    /// (`%#@items@`).
    private static func placeholderEnd(_ text: Substring) -> Substring.Index? {
        var index = text.startIndex
        func skip(while condition: (Character) -> Bool) {
            while index < text.endIndex, condition(text[index]) { index = text.index(after: index) }
        }
        func next(_ character: Character) -> Bool {
            guard index < text.endIndex, text[index] == character else { return false }
            index = text.index(after: index)
            return true
        }
        if text.hasPrefix("#@") {
            index = text.index(index, offsetBy: 2)
            let name = index
            skip { $0.isLetter || $0.isNumber || $0 == "_" }
            guard index > name, next("@") else { return nil }
            return index
        }
        // A position: digits and "$".
        let digits = index
        skip { $0.isASCII && $0.isNumber }
        if !next("$") { index = digits }
        skip { "-+ #0'".contains($0) }
        if !next("*") { skip { $0.isASCII && $0.isNumber } }
        if next(".") {
            if !next("*") { skip { $0.isASCII && $0.isNumber } }
        }
        for length in ["hh", "ll", "h", "l", "q", "L", "z", "t", "j"] where text[index...].hasPrefix(length) {
            index = text.index(index, offsetBy: length.count)
            break
        }
        guard index < text.endIndex, "@dDiuUxXoOfFeEgGaAcCsSp".contains(text[index]) else { return nil }
        return text.index(after: index)
    }

    /// Whether `value` is this template with some non-empty text for each placeholder. With
    /// only wildcards between the literals, taking each middle literal at its leftmost place
    /// is enough: no backtracking.
    func matches(_ value: String) -> Bool {
        guard placeholderCount > 0 else { return value == literals[0] }
        let first = literals[0]
        let last = literals[literals.count - 1]
        guard value.hasPrefix(first), value.hasSuffix(last),
              value.count >= literals.reduce(0) { $0 + $1.count } + placeholderCount
        else { return false }
        // Where the last literal starts; the placeholder before it needs a character.
        let end = value.index(value.endIndex, offsetBy: -last.count)
        var position = value.index(value.startIndex, offsetBy: first.count)
        for literal in literals.dropFirst().dropLast() {
            // The placeholder before it takes at least one character.
            guard position < end else { return false }
            let from = value.index(after: position)
            // Two placeholders side by side: the first takes one character, the next the rest.
            if literal.isEmpty {
                position = from
                continue
            }
            guard from <= end, let found = value.range(of: literal, options: .literal, range: from..<end)
            else { return false }
            position = found.upperBound
        }
        return position < end
    }
}
