import Foundation

/// Finds where a class is declared from the name the server gives it (C-SRC-03,
/// `display_class_name`, P-HIER-16).
///
/// The name loses its generic arguments and any part in parentheses; its last part is the
/// type's own name, the parts before it the types it is inside, the first of which may be the
/// module. A declaration counts when its own name is the same and the types it is inside are
/// those parts, with or without the first. An Objective-C class's `@interface` is preferred to
/// its `@implementation`.
enum ClassDeclarationLookup {
    /// The type's own name and the parts before it, or nil when nothing is left of the name.
    static func parts(of displayName: String) -> (name: String, qualifiers: [String])? {
        var kept = ""
        var angle = 0
        var round = 0
        for character in displayName {
            switch character {
            case "<": angle += 1
            case ">": angle = max(angle - 1, 0)
            case "(": round += 1
            case ")": round = max(round - 1, 0)
            default:
                if angle == 0, round == 0 { kept.append(character) }
            }
        }
        let parts = kept.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let name = parts.last else { return nil }
        return (name, Array(parts.dropLast()))
    }

    /// The declarations of the class, by file and then line.
    static func declarations(of displayName: String, in index: ProjectIndex) -> [TypeDeclaration] {
        guard let (name, qualifiers) = parts(of: displayName),
              let candidates = index.declarations[name]
        else { return [] }
        let withoutModule = Array(qualifiers.dropFirst())
        var found = candidates.filter { declaration in
            switch declaration.kind {
            case .swift:
                declaration.enclosingTypes == qualifiers || declaration.enclosingTypes == withoutModule
            case .objectiveCInterface, .objectiveCImplementation:
                // An Objective-C class is inside no type; a Swift module may still be named.
                qualifiers.count <= 1
            }
        }
        if found.contains(where: { $0.kind == .objectiveCInterface }) {
            found.removeAll { $0.kind == .objectiveCImplementation }
        }
        return found.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
    }
}
