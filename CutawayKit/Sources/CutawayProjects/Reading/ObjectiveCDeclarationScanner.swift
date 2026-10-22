import Foundation

/// Finds the classes an Objective-C file declares (C-SRC-03): each `@interface` and
/// `@implementation` of a class, outside comments and string literals. A category or a class
/// extension, `@interface Name (…)`, declares no class.
enum ObjectiveCDeclarationScanner {
    struct Found: Equatable {
        var name: String
        var isInterface: Bool
        var line: Int
    }

    static func declarations(in source: Data) -> [Found] {
        source.withUnsafeBytes { raw in
            var scanner = ObjectiveCScanner(bytes: raw.bindMemory(to: UInt8.self))
            return scanner.declarations()
        }
    }
}

private struct ObjectiveCScanner {
    let bytes: UnsafeBufferPointer<UInt8>
    private var position = 0
    private var line = 1

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    private static let interface = Array("interface".utf8)
    private static let implementation = Array("implementation".utf8)
    private static let newline = UInt8(ascii: "\n")
    private static let slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*")

    private func byte(at index: Int) -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func isWordPart(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || byte == 0x5F
            || (byte >= 0x30 && byte <= 0x39) || byte >= 0x80
    }

    mutating func declarations() -> [ObjectiveCDeclarationScanner.Found] {
        var found: [ObjectiveCDeclarationScanner.Found] = []
        while position < bytes.count {
            let byte = bytes[position]
            switch byte {
            case Self.newline:
                line += 1
                position += 1
            case Self.slash where self.byte(at: position + 1) == Self.slash:
                while position < bytes.count, bytes[position] != Self.newline { position += 1 }
            case Self.slash where self.byte(at: position + 1) == Self.star:
                position += 2
                while position < bytes.count,
                      !(bytes[position] == Self.star && self.byte(at: position + 1) == Self.slash)
                {
                    if bytes[position] == Self.newline { line += 1 }
                    position += 1
                }
                position += 2
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                skipLiteral(closedBy: byte)
            case UInt8(ascii: "@"):
                position += 1
                let word = readWord()
                let isInterface = matches(word, Self.interface)
                guard isInterface || matches(word, Self.implementation) else { continue }
                if let declared = declaredClass() {
                    found.append(.init(name: declared.name, isInterface: isInterface, line: declared.line))
                }
            default:
                position += 1
            }
        }
        return found
    }

    private mutating func readWord() -> Range<Int> {
        let start = position
        while position < bytes.count, Self.isWordPart(bytes[position]) { position += 1 }
        return start..<position
    }

    private func matches(_ range: Range<Int>, _ word: [UInt8]) -> Bool {
        guard range.count == word.count else { return false }
        return zip(range, word).allSatisfy { bytes[$0] == $1 }
    }

    private mutating func skipSpace() {
        while position < bytes.count {
            switch bytes[position] {
            case Self.newline:
                line += 1
                position += 1
            case 0x20, 0x09, 0x0D, 0x0C, 0x0B:
                position += 1
            default:
                return
            }
        }
    }

    /// The class after `@interface` or `@implementation`, or nil for a category or a class
    /// extension.
    private mutating func declaredClass() -> (name: String, line: Int)? {
        skipSpace()
        let nameLine = line
        let range = readWord()
        guard !range.isEmpty else { return nil }
        skipSpace()
        // Lightweight generics: `@interface Box<ObjectType> : NSObject`.
        if byte(at: position) == UInt8(ascii: "<") {
            var depth = 0
            while position < bytes.count {
                let byte = bytes[position]
                if byte == Self.newline { line += 1 }
                position += 1
                if byte == UInt8(ascii: "<") { depth += 1 }
                if byte == UInt8(ascii: ">") {
                    depth -= 1
                    if depth == 0 { break }
                }
            }
            skipSpace()
        }
        guard byte(at: position) != UInt8(ascii: "(") else { return nil }
        guard let name = String(bytes: UnsafeBufferPointer(rebasing: bytes[range]), encoding: .utf8) else { return nil }
        return (name, nameLine)
    }

    /// Past a string or character literal, which ends at its line's end if not before.
    private mutating func skipLiteral(closedBy quote: UInt8) {
        position += 1
        while position < bytes.count {
            let byte = bytes[position]
            if byte == Self.newline { return }
            position += byte == UInt8(ascii: "\\") ? 2 : 1
            if byte == quote { return }
        }
    }
}
