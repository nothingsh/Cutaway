import CutawayTestSupport
import Foundation
import XCTest
@testable import CutawayModel

/// C-SRC-03: the declarations the scanners find in the sample project, and the words that
/// only look like them.
final class DeclarationScannerTests: XCTestCase {
    private func swift(_ file: String) -> [SwiftDeclarationScanner.Found] {
        SwiftDeclarationScanner.declarations(in: Data((SampleProject.files[file] ?? "").utf8))
    }

    private func objectiveC(_ file: String) -> [ObjectiveCDeclarationScanner.Found] {
        ObjectiveCDeclarationScanner.declarations(in: Data((SampleProject.files[file] ?? "").utf8))
    }

    func test_C_SRC_03_aSwiftClassIsFoundAtItsLine() {
        let found = swift(SampleProject.homeViewController)
        XCTAssertEqual(found, [
            .init(
                name: "HomeViewController", enclosingTypes: [],
                line: SampleProject.place(SampleProject.homeViewController, "final class HomeViewController").line),
        ])
    }

    func test_C_SRC_03_commentsStringsModifiersAndLocalTypesAreNotDeclarations() {
        // Everything else in the file is a comment, a string, a regular expression, `class`
        // as a modifier or a type in a body that is not a type's.
        let names = swift(SampleProject.homeViewController).map(\.name)
        for name in [
            "NotInAComment", "NotInABlock", "StillNotInABlock", "NotInAString", "NotInAMultilineString",
            "NotInARawString", "NotInAnInterpolation", "NotInARegex", "func", "var", "override",
            "LocalType", "LocalInAClosure", "LocalInAnAccessor",
        ] {
            XCTAssertFalse(names.contains(name), name)
        }
    }

    func test_C_SRC_03_nestedTypesKnowTheTypesTheyAreIn() {
        let found = swift(SampleProject.outer)
        let file = SampleProject.outer
        XCTAssertEqual(found, [
            .init(name: "Outer", enclosingTypes: [], line: SampleProject.place(file, "enum Outer").line),
            .init(name: "Inner", enclosingTypes: ["Outer"], line: 2),
            .init(name: "Other", enclosingTypes: [], line: SampleProject.place(file, "struct Other").line),
            .init(name: "Inner", enclosingTypes: ["Other"], line: 6),
            // Inside an extension: inside the type it extends, whose names it gives in full.
            .init(name: "Worker", enclosingTypes: ["Outer"], line: SampleProject.place(file, "actor Worker").line),
            .init(
                name: "Deep", enclosingTypes: ["Outer", "Inner"],
                line: SampleProject.place(file, "class Deep").line),
        ])
    }

    func test_C_SRC_03_aGenericClassIsFoundByItsName() {
        XCTAssertEqual(swift(SampleProject.listCell).map(\.name), ["ListCell"])
        XCTAssertEqual(swift(SampleProject.listCell).first?.line, 3)
    }

    func test_C_SRC_03_anExtensionAndAProtocolDeclareNoType() {
        XCTAssertEqual(swift("Shop/Lists/ExtensionOnly.swift"), [])
    }

    func test_C_SRC_03_bothBranchesOfAnIfAreRead() {
        XCTAssertEqual(swift(SampleProject.legacyHeaderView).map(\.name), ["HomeHeaderView"])
    }

    func test_C_SRC_03_anUnclosedStringOrCommentEndsTheFileQuietly() {
        for text in ["class A {} \"open", "class A {} /* open", "class A {} #\"open", "class"] {
            let found = SwiftDeclarationScanner.declarations(in: Data(text.utf8))
            XCTAssertEqual(found.map(\.name), text == "class" ? [] : ["A"], text)
        }
    }

    func test_C_SRC_03_aBacktickedNameIsAName() {
        let found = SwiftDeclarationScanner.declarations(in: Data("struct `Type` {}\nenum E { case `class` }".utf8))
        XCTAssertEqual(found.map(\.name), ["Type", "E"])
    }

    func test_C_SRC_03_anObjectiveCHeaderGivesItsInterface() {
        XCTAssertEqual(objectiveC(SampleProject.cardViewHeader), [
            .init(
                name: "LegacyCardView", isInterface: true,
                line: SampleProject.place(SampleProject.cardViewHeader, "@interface LegacyCardView : UIView").line),
            .init(
                name: "Box", isInterface: true,
                line: SampleProject.place(SampleProject.cardViewHeader, "@interface Box").line),
        ])
    }

    func test_C_SRC_03_categoriesClassExtensionsAndStringsDeclareNoClass() {
        let file = SampleProject.cardViewImplementation
        XCTAssertEqual(objectiveC(file), [
            .init(
                name: "LegacyCardView", isInterface: false,
                line: SampleProject.place(file, "@implementation LegacyCardView").line),
            .init(
                name: "LegacyOnlyImplemented", isInterface: false,
                line: SampleProject.place(file, "@implementation LegacyOnlyImplemented").line),
        ])
    }
}

/// C-SRC-03: from the name the server gives a class to where it is declared.
final class ClassDeclarationLookupTests: XCTestCase {
    private var builder: ProjectBuilder?
    private var index = ProjectIndex(root: URL(fileURLWithPath: "/"))

    override func setUp() async throws {
        let builder = try ProjectBuilder()
        self.builder = builder
        try SampleProject.write(into: builder)
        index = await ProjectIndexer(root: builder.root).build().0
    }

    override func tearDown() {
        builder?.remove()
    }

    private func places(_ name: String) -> [SampleProject.Place] {
        ClassDeclarationLookup.declarations(of: name, in: index).map {
            SampleProject.Place(file: $0.file, line: $0.line)
        }
    }

    func test_C_SRC_03_theSampleProjectsFourDeclarationsAreFound() throws {
        XCTAssertEqual(
            places("HomeViewController"),
            [SampleProject.place(SampleProject.homeViewController, "final class HomeViewController")])
        XCTAssertEqual(
            places("LegacyCardView"),
            [SampleProject.place(SampleProject.cardViewHeader, "@interface LegacyCardView : UIView")])
        XCTAssertEqual(places("Outer.Inner"), [SampleProject.Place(file: SampleProject.outer, line: 2)])
        XCTAssertEqual(places("ListCell<Item>"), [SampleProject.Place(file: SampleProject.listCell, line: 3)])
        // Each as a location to open.
        let location = try XCTUnwrap(index.locations(ofClass: "ListCell<Swift.String>").first)
        XCTAssertEqual(location.file.lastPathComponent, "ListCell.swift")
        XCTAssertEqual(location.line, 3)
        XCTAssertEqual(location.folder, "Shop/Lists")
    }

    func test_C_SRC_03_theModuleMayBeNamed() {
        XCTAssertEqual(places("Shop.HomeViewController").count, 1)
        XCTAssertEqual(places("Shop.Outer.Inner"), [SampleProject.Place(file: SampleProject.outer, line: 2)])
        XCTAssertEqual(places("Shop.Outer.Inner.Deep").count, 1)
        XCTAssertEqual(places("Outer.Worker").count, 1)
        // An Objective-C class may come with a Swift module too, but is inside no type.
        XCTAssertEqual(places("Shop.LegacyCardView").count, 1)
        XCTAssertEqual(places("Shop.Outer.LegacyCardView"), [])
    }

    func test_C_SRC_03_aTypeOfTheSameNameInsideAnotherTypeIsNotFound() {
        XCTAssertEqual(places("Other.Inner"), [SampleProject.Place(file: SampleProject.outer, line: 6)])
        XCTAssertEqual(places("Shop.Elsewhere.Outer.Inner"), [])
        // The top-level name alone is not a nested type.
        XCTAssertEqual(places("Inner"), [])
        XCTAssertEqual(places("Shop.Inner"), [])
    }

    func test_C_SRC_03_aTypeWithOnlyAnExtensionIsNotFound() {
        XCTAssertEqual(places("OnlyExtended"), [])
        XCTAssertEqual(places("Listing"), [])
        XCTAssertEqual(places("UIView"), [])
    }

    func test_C_SRC_03_twoDeclarationsGiveTwoPlacesByPathThenLine() {
        XCTAssertEqual(places("HomeHeaderView"), [
            SampleProject.place(SampleProject.headerView, "class HomeHeaderView"),
            SampleProject.place(SampleProject.legacyHeaderView, "class HomeHeaderView"),
        ])
    }

    func test_C_SRC_03_anImplementationIsGivenOnlyWithoutAnInterface() {
        XCTAssertEqual(places("LegacyOnlyImplemented").count, 1)
        XCTAssertEqual(places("LegacyCardView").map(\.file), [SampleProject.cardViewHeader])
    }

    func test_C_SRC_03_partsInParenthesesAndEmptyNamesAreLeftOut() {
        XCTAssertEqual(
            ClassDeclarationLookup.parts(of: "Shop.(unknown context at $1023).Local<Int>")?.name, "Local")
        XCTAssertEqual(
            ClassDeclarationLookup.parts(of: "Shop.(unknown context at $1023).Local")?.qualifiers, ["Shop"])
        XCTAssertNil(ClassDeclarationLookup.parts(of: ""))
        XCTAssertNil(ClassDeclarationLookup.parts(of: "<T>"))
        XCTAssertEqual(places(""), [])
    }
}
