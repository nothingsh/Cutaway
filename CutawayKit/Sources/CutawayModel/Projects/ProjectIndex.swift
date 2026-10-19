import Foundation

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
public struct ProjectIndex: Equatable, Sendable {
    public var root: URL
    /// The declarations, by the type's own name.
    public var declarations: [String: [TypeDeclaration]]
    public let colorSets: [ColorSet]
    public let strings: [LocalizedString]
    /// The colour sets by their colours (C-SRC-04), made with the index, in the background.
    public let colors: ColorAssetLookup
    /// The string tables' keys by their values (C-SRC-05), made with the index.
    public let keys: StringKeyLookup

    public init(
        root: URL, declarations: [String: [TypeDeclaration]] = [:], colorSets: [ColorSet] = [],
        strings: [LocalizedString] = []
    ) {
        self.root = root
        self.declarations = declarations
        self.colorSets = colorSets
        self.strings = strings
        colors = ColorAssetLookup(colorSets)
        keys = StringKeyLookup(strings)
    }

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
/// the last build as they had not changed, and how many could not be read or were too large.
public struct ProjectIndexReport: Equatable, Sendable {
    public var read: Int
    public var reused: Int
    public var skipped: Int

    public init(read: Int = 0, reused: Int = 0, skipped: Int = 0) {
        self.read = read
        self.reused = reused
        self.skipped = skipped
    }
}
