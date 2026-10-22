import Foundation

/// Finds the types a Swift file declares (C-SRC-03): `class`, `struct`, `enum` and `actor`,
/// with the types they are declared inside. Not a parser: it reads the words between the
/// comments and the string literals, and the braces that open and close the types' bodies.
/// An `extension` declares nothing itself, but a type declared inside it is inside the type it
/// extends. A type declared in a function's body, a closure or an accessor is local and is
/// left out.
enum SwiftDeclarationScanner {
    struct Found: Equatable {
        var name: String
        var enclosingTypes: [String]
        var line: Int
    }

    static func declarations(in source: Data) -> [Found] {
        source.withUnsafeBytes { raw in
            var scanner = SwiftScanner(bytes: raw.bindMemory(to: UInt8.self))
            return scanner.declarations()
        }
    }
}

private struct SwiftScanner {
    enum Token: Equatable {
        /// The bytes of a word, and whether it was written in backticks, which makes even a
        /// keyword a name.
        case word(Range<Int>, escaped: Bool)
        case openBrace, closeBrace, dot, other, end
    }

    enum Scope {
        /// A type's body, or an extension's: the names from the outermost type in.
        case type([String])
        /// Any other body: a function's, a closure's, an accessor's.
        case other
    }

    let bytes: UnsafeBufferPointer<UInt8>
    private var position = 0
    private var line = 1
    /// Tokens read ahead and put back, the last first.
    private var putBack: [(Token, Int)] = []

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func declarations() -> [SwiftDeclarationScanner.Found] {
        var found: [SwiftDeclarationScanner.Found] = []
        var scopes: [Scope] = []
        // The names of the type whose header is being read, for the body its brace opens.
        var pending: [String]?
        while true {
            let (token, _) = next()
            switch token {
            case .end:
                return found
            case .openBrace:
                scopes.append(pending.map(Scope.type) ?? .other)
                pending = nil
            case .closeBrace:
                if !scopes.isEmpty { scopes.removeLast() }
                pending = nil
            case .word(let range, escaped: false):
                switch keyword(range) {
                case .type:
                    guard let (name, nameLine) = nameAfterKeyword() else { continue }
                    let enclosing = Self.enclosingTypes(scopes)
                    if let enclosing {
                        found.append(.init(name: name, enclosingTypes: enclosing, line: nameLine))
                    }
                    pending = (enclosing ?? []) + [name]
                case .protocol:
                    guard let (name, _) = nameAfterKeyword() else { continue }
                    pending = (Self.enclosingTypes(scopes) ?? []) + [name]
                case .extension:
                    pending = extendedType()
                case nil:
                    continue
                }
            default:
                continue
            }
        }
    }

    /// The types around a declaration, or nil when it is inside a body that is not a type's.
    private static func enclosingTypes(_ scopes: [Scope]) -> [String]? {
        var names: [String] = []
        for scope in scopes {
            guard case .type(let chain) = scope else { return nil }
            names = chain
        }
        return names
    }

    // MARK: - Words

    private enum Keyword {
        case type, `protocol`, `extension`
    }

    private static let typeKeywords: [[UInt8]] = ["class", "struct", "enum", "actor"].map { Array($0.utf8) }
    private static let protocolKeyword = Array("protocol".utf8)
    private static let extensionKeyword = Array("extension".utf8)
    /// Words that follow `class` used as a modifier (`class func`), or that cannot be a
    /// type's name.
    private static let notNames: Set<String> = [
        "func", "var", "let", "subscript", "init", "deinit", "override", "final", "static",
        "private", "fileprivate", "internal", "public", "open", "package", "mutating",
        "nonmutating", "dynamic", "convenience", "required", "lazy", "weak", "unowned",
        "indirect", "nonisolated", "async", "typealias", "associatedtype", "class", "struct",
        "enum", "protocol", "extension", "actor", "case", "operator", "prefix", "postfix",
        "infix", "where", "in", "is", "as", "throws", "rethrows", "some", "any",
    ]

    private func keyword(_ range: Range<Int>) -> Keyword? {
        let length = range.count
        guard length >= 4, length <= 9 else { return nil }
        if Self.typeKeywords.contains(where: { matches(range, $0) }) { return .type }
        if matches(range, Self.protocolKeyword) { return .protocol }
        if matches(range, Self.extensionKeyword) { return .extension }
        return nil
    }

    private func matches(_ range: Range<Int>, _ word: [UInt8]) -> Bool {
        guard range.count == word.count else { return false }
        var index = range.lowerBound
        for byte in word {
            if bytes[index] != byte { return false }
            index += 1
        }
        return true
    }

    /// A word's text; nil for one that is not UTF-8, which is no name.
    private func text(_ range: Range<Int>) -> String? {
        String(bytes: UnsafeBufferPointer(rebasing: bytes[range]), encoding: .utf8)
    }

    /// The name a type keyword declares, or nil when the keyword is a modifier or the word
    /// after it is not a name; that token is then read again.
    private mutating func nameAfterKeyword() -> (String, Int)? {
        let (token, tokenLine) = next()
        if case .word(let range, let escaped) = token, let name = text(range),
           escaped || !Self.notNames.contains(name)
        {
            return (name, tokenLine)
        }
        putBack.append((token, tokenLine))
        return nil
    }

    /// The type an `extension` extends, as its names: `A.B` is `["A", "B"]`.
    private mutating func extendedType() -> [String]? {
        var names: [String] = []
        while true {
            let (token, tokenLine) = next()
            guard case .word(let range, _) = token, let name = text(range) else {
                putBack.append((token, tokenLine))
                return names.isEmpty ? nil : names
            }
            names.append(name)
            let (after, afterLine) = next()
            guard after == .dot else {
                putBack.append((after, afterLine))
                return names
            }
        }
    }

    // MARK: - Tokens

    private static let newline = UInt8(ascii: "\n")
    private static let quote = UInt8(ascii: "\"")
    private static let hash = UInt8(ascii: "#")
    private static let slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*")
    private static let backslash = UInt8(ascii: "\\")
    private static let backtick = UInt8(ascii: "`")

    private func byte(at index: Int) -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func isWordStart(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || byte == 0x5F || byte >= 0x80
    }

    private static func isWordPart(_ byte: UInt8) -> Bool {
        isWordStart(byte) || (byte >= 0x30 && byte <= 0x39)
    }

    /// The next token and its line.
    private mutating func next() -> (Token, Int) {
        if let token = putBack.popLast() { return token }
        while position < bytes.count {
            let current = bytes[position]
            switch current {
            case Self.newline:
                line += 1
                position += 1
            case 0x20, 0x09, 0x0D, 0x0C, 0x0B:
                position += 1
            case Self.slash where byte(at: position + 1) == Self.slash:
                while position < bytes.count, bytes[position] != Self.newline { position += 1 }
            case Self.slash where byte(at: position + 1) == Self.star:
                skipBlockComment()
            case Self.quote:
                skipString(hashes: 0)
                return (.other, line)
            case Self.hash:
                var end = position
                while byte(at: end) == Self.hash { end += 1 }
                let hashes = end - position
                if byte(at: end) == Self.quote {
                    position = end
                    skipString(hashes: hashes)
                } else if byte(at: end) == Self.slash {
                    position = end + 1
                    skipRegex(hashes: hashes)
                } else {
                    position = end
                }
                return (.other, line)
            case Self.backtick:
                let start = position + 1
                var end = start
                while end < bytes.count, bytes[end] != Self.backtick, bytes[end] != Self.newline { end += 1 }
                position = min(end + 1, bytes.count)
                return (.word(start..<end, escaped: true), line)
            case UInt8(ascii: "{"):
                position += 1
                return (.openBrace, line)
            case UInt8(ascii: "}"):
                position += 1
                return (.closeBrace, line)
            case UInt8(ascii: "."):
                position += 1
                return (.dot, line)
            default:
                if Self.isWordStart(current) {
                    let start = position
                    while position < bytes.count, Self.isWordPart(bytes[position]) { position += 1 }
                    return (.word(start..<position, escaped: false), line)
                }
                if Self.isWordPart(current) {
                    // A number.
                    while position < bytes.count, Self.isWordPart(bytes[position]) { position += 1 }
                } else {
                    position += 1
                }
                return (.other, line)
            }
        }
        return (.end, line)
    }

    /// Past a `/* */` comment, which may hold others.
    private mutating func skipBlockComment() {
        position += 2
        var depth = 1
        while position < bytes.count {
            let byte = bytes[position]
            if byte == Self.newline {
                line += 1
                position += 1
            } else if byte == Self.slash, self.byte(at: position + 1) == Self.star {
                depth += 1
                position += 2
            } else if byte == Self.star, self.byte(at: position + 1) == Self.slash {
                depth -= 1
                position += 2
                if depth == 0 { return }
            } else {
                position += 1
            }
        }
    }

    /// Past a string literal whose opening quote is at the position, raw with `hashes` number
    /// signs around it; single or multi-line, interpolations included.
    private mutating func skipString(hashes: Int) {
        let multiline = byte(at: position + 1) == Self.quote && byte(at: position + 2) == Self.quote
        position += multiline ? 3 : 1
        while position < bytes.count {
            let byte = bytes[position]
            switch byte {
            case Self.newline:
                line += 1
                position += 1
                // An unclosed single-line string ends with its line.
                if !multiline { return }
            case Self.backslash:
                guard hashesFollow(position + 1, hashes) else {
                    position += 1
                    continue
                }
                let escaped = position + 1 + hashes
                if self.byte(at: escaped) == UInt8(ascii: "(") {
                    position = escaped + 1
                    skipInterpolation()
                } else {
                    if self.byte(at: escaped) == Self.newline { line += 1 }
                    position = escaped + 1
                }
            case Self.quote:
                if multiline {
                    if self.byte(at: position + 1) == Self.quote, self.byte(at: position + 2) == Self.quote,
                       hashesFollow(position + 3, hashes)
                    {
                        position += 3 + hashes
                        return
                    }
                    position += 1
                } else if hashesFollow(position + 1, hashes) {
                    position += 1 + hashes
                    return
                } else {
                    position += 1
                }
            default:
                position += 1
            }
        }
    }

    private func hashesFollow(_ index: Int, _ count: Int) -> Bool {
        for offset in 0..<count where byte(at: index + offset) != Self.hash {
            return false
        }
        return true
    }

    /// Past `\( … )` in a string, from just after its opening parenthesis.
    private mutating func skipInterpolation() {
        var depth = 1
        while position < bytes.count {
            let byte = bytes[position]
            switch byte {
            case UInt8(ascii: "("):
                depth += 1
                position += 1
            case UInt8(ascii: ")"):
                depth -= 1
                position += 1
                if depth == 0 { return }
            case Self.quote:
                skipString(hashes: 0)
            case Self.hash:
                var end = position
                while self.byte(at: end) == Self.hash { end += 1 }
                if self.byte(at: end) == Self.quote {
                    let hashes = end - position
                    position = end
                    skipString(hashes: hashes)
                } else {
                    position = end
                }
            case Self.newline:
                line += 1
                position += 1
            default:
                position += 1
            }
        }
    }

    /// Past an extended regular expression literal `#/ … /#`, from just after its slash.
    private mutating func skipRegex(hashes: Int) {
        while position < bytes.count {
            let byte = bytes[position]
            if byte == Self.newline { line += 1 }
            if byte == Self.slash, hashesFollow(position + 1, hashes) {
                position += 1 + hashes
                return
            }
            position += 1
        }
    }
}
