import Foundation
import os

/// Where a type is declared in a project folder (C-SRC-03).
public struct TypeDeclaration: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        /// A Swift `class`, `struct`, `enum` or `actor`.
        case swift
        /// An Objective-C `@interface`, which is preferred to the `@implementation`.
        case objectiveCInterface
        case objectiveCImplementation
    }

    public var name: String
    /// The types it is declared inside, outermost first; empty at the top level and in
    /// Objective-C.
    public var enclosingTypes: [String]
    public var kind: Kind
    /// The file, relative to the project folder.
    public var file: String
    /// The line of its name, from 1.
    public var line: Int

    public init(name: String, enclosingTypes: [String] = [], kind: Kind, file: String, line: Int) {
        self.name = name
        self.enclosingTypes = enclosingTypes
        self.kind = kind
        self.file = file
        self.line = line
    }
}

/// A color set of an asset catalog, as its `Contents.json` writes it (C-SRC-02). How the
/// components read is left to whoever compares colours.
public struct ColorSet: Equatable, Sendable {
    /// One of the set's colours: for an idiom and a set of appearances.
    public struct Entry: Equatable, Sendable {
        /// An appearance the entry is for, such as `luminosity` `dark`.
        public struct Appearance: Equatable, Sendable {
            public var appearance: String
            public var value: String

            public init(appearance: String, value: String) {
                self.appearance = appearance
                self.value = value
            }
        }

        public var idiom: String?
        /// Empty for any appearance.
        public var appearances: [Appearance]
        public var colorSpace: String?
        /// The components as written, by name (`red`, `green`, `blue`, `alpha`, `white`).
        public var components: [String: String]
        /// The system colour the entry refers to instead of components, such as
        /// `systemBlueColor`.
        public var systemReference: String?

        public init(
            idiom: String?, appearances: [Appearance], colorSpace: String?,
            components: [String: String], systemReference: String?
        ) {
            self.idiom = idiom
            self.appearances = appearances
            self.colorSpace = colorSpace
            self.components = components
            self.systemReference = systemReference
        }
    }

    /// The set's name, with the folders that provide a namespace before it: `Brand/Blue`.
    public var name: String
    /// The set's `Contents.json`, relative to the project folder.
    public var file: String
    public var entries: [Entry]

    public init(name: String, file: String, entries: [Entry]) {
        self.name = name
        self.file = file
        self.entries = entries
    }
}

/// One value of a string table: a key in a language (C-SRC-02).
public struct LocalizedString: Equatable, Sendable {
    /// The table, the file's name without its extension.
    public var table: String
    public var key: String
    /// The language, or nil for a `.strings` file outside an `.lproj` folder.
    public var language: String?
    public var value: String
    /// The file, relative to the project folder.
    public var file: String

    public init(table: String, key: String, language: String?, value: String, file: String) {
        self.table = table
        self.key = key
        self.language = language
        self.value = value
        self.file = file
    }
}

/// A place a class is declared, ready to open (C-SRC-03).
public struct SourceLocation: Equatable, Hashable, Sendable {
    public var file: URL
    public var line: Int
    /// The folder the file is in, relative to the project folder; empty at its top.
    public var folder: String

    public init(file: URL, line: Int, folder: String) {
        self.file = file
        self.line = line
        self.folder = folder
    }
}

/// What a project folder holds, as last read (C-SRC-02): built in the background, never
/// changed once made.
///
/// Not compared by what it holds, which for a large app takes far longer than a frame: each
/// index made has a generation of its own, and the same generation is the same index.
public struct ProjectIndex: Sendable {
    /// Which index this is: a number no other index made in this process has.
    public let generation: UInt64
    public let root: URL
    /// The declarations, by the type's own name.
    public let declarations: [String: [TypeDeclaration]]
    public let colorSets: [ColorSet]
    /// The colour sets by their colours (C-SRC-04), made with the index, in the background.
    public let colors: ColorAssetLookup
    /// The string tables' keys by their values (C-SRC-05), made with the index. The values
    /// themselves are not kept here.
    public let keys: StringKeyLookup

    public init(
        root: URL, declarations: [String: [TypeDeclaration]] = [:], colorSets: [ColorSet] = [],
        strings: [LocalizedString] = []
    ) {
        generation = Self.generations.withLock { last in
            last += 1
            return last
        }
        self.root = root
        self.declarations = declarations
        self.colorSets = colorSets
        colors = ColorAssetLookup(colorSets)
        keys = StringKeyLookup(strings)
    }

    private static let generations = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    /// Where a class named as the server names it is declared (C-SRC-03), in the order to
    /// offer them.
    public func locations(ofClass displayName: String) -> [SourceLocation] {
        ClassDeclarationLookup.declarations(of: displayName, in: self).map { declaration in
            let folder = (declaration.file as NSString).deletingLastPathComponent
            return SourceLocation(
                file: root.appendingPathComponent(declaration.file), line: declaration.line,
                folder: folder)
        }
    }
}

/// What building an index did (C-SRC-02): how many files were read, how many were kept from
/// the last build as they had not changed, how many were too large to be the app's own or
/// could not be read, and whether the walk stopped at the most files it takes.
public struct ProjectIndexReport: Equatable, Sendable {
    public var read: Int
    public var reused: Int
    /// Larger than the most its kind is read at: most likely generated.
    public var tooLarge: Int
    /// Could not be opened or parsed.
    public var unreadable: Int
    /// The folder holds more files to index than are taken; those past it were left out.
    public var reachedFileLimit: Bool

    /// The files left out, too large or unreadable.
    public var skipped: Int { tooLarge + unreadable }

    public init(
        read: Int = 0, reused: Int = 0, tooLarge: Int = 0, unreadable: Int = 0, reachedFileLimit: Bool = false
    ) {
        self.read = read
        self.reused = reused
        self.tooLarge = tooLarge
        self.unreadable = unreadable
        self.reachedFileLimit = reachedFileLimit
    }
}
