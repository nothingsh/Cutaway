import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The clusters and slots protocol 1.2 adds to P-ATTR-12's table (C-ATTR-27): which attributes
/// make a row, what the row says, and what is left on its own. The fixtures have only `font`'s
/// new slots; the rest are made in `Protocol12Extras`.
@MainActor
final class NewClusterTests: XCTestCase {
    /// What a section lists: each item's cluster and slots, or the attribute's ID.
    private static func items(
        _ groups: [AttributeGroup], _ kind: AttributesViewModel.Listing.Kind = .content
    ) -> [String] {
        let section = AttributesViewModel.listing(of: groups).section(kind)
        return (section?.parts ?? []).flatMap(\.listed).map { item in
            switch item {
            case .single(let attribute): attribute.id ?? ""
            case .cluster(let row): "[\(row.kind.rawValue): \(row.order.joined(separator: ", "))]"
            }
        }
    }

    private static func group(_ attributes: [Attribute], className: String = "UIView") -> [AttributeGroup] {
        [AttributeGroup(id: "g", title: "G", attributes: attributes, className: className)]
    }

    /// The compound row of a cluster, read-only, as a layer whose view's base class is
    /// `viewBase` would show it.
    private static func row(
        _ attributes: [Attribute], _ kind: AttributesViewModel.Listing.Kind = .content,
        viewBase: String? = nil
    ) throws -> CompoundRowView {
        let section = try XCTUnwrap(AttributesViewModel.listing(of: group(attributes)).section(kind))
        let cluster = try XCTUnwrap(section.parts.flatMap(\.listed).compactMap { item -> AttributeClusters.Row? in
            if case .cluster(let row) = item { return row }
            return nil
        }.first)
        let factory = CompoundFactory(
            editor: { attribute, options in
                AttributeEditorView(attribute: attribute, isReadOnly: true, options: options)
            },
            sender: { _ in nil }, words: ClusterText.Words(viewBaseClassName: viewBase))
        let row = CompoundRowView(cluster, factory: factory)
        for (attribute, cell) in row.cells { cell.show(attribute.value, names: .none) }
        return row
    }

    // MARK: - Font

    func test_C_ATTR_27_theFixturesFontTakesItsTextStyleAndScaling() throws {
        let three = try Fixtures.attributes(of: 3, scenario: "layer-details")
        XCTAssertEqual(Self.items(three), [
            "label.text", "[font: size, textStyle, scalable]", "[lines: count]", "label.textAlignment",
        ])
        let font = try XCTUnwrap(three.flatMap(\.attributes).filter { $0.cluster?.name == "font" })
        let row = try Self.row(font)
        XCTAssertEqual(row.texts, ["Body"])
        XCTAssertEqual(row.attributeCount, 3)
        let scalable = try XCTUnwrap(AppListViewTests.descendants(
            of: row, identifier: AttributeRowView.checkboxIdentifier).first as? NSButton)
        XCTAssertEqual(scalable.state, .on)
        let titles = AppListViewTests.descendants(of: row) { $0 is WrappingTitleField }
            .compactMap { ($0 as? WrappingTitleField)?.title }
        XCTAssertTrue(titles.contains("Dynamic Type"), "\(titles)")
    }

    func test_C_ATTR_27_aTextStyleIsNamedAsUIKitNamesIt() {
        XCTAssertEqual(ClusterText.textStyle("body"), "Body")
        XCTAssertEqual(ClusterText.textStyle("UICTFontTextStyleBody"), "Body")
        XCTAssertEqual(ClusterText.textStyle("largeTitle"), "Large Title")
        XCTAssertEqual(ClusterText.textStyle("UICTFontTextStyleTitle1"), "Title 1")
        XCTAssertEqual(ClusterText.textStyle("caption2"), "Caption 2")
        XCTAssertEqual(ClusterText.textStyle("extraLargeTitle2"), "Extra Large Title 2")
        XCTAssertEqual(ClusterText.textStyle("customStyle"), "customStyle", "unknown: as it came")
    }

    // MARK: - One row each

    func test_C_ATTR_27_eachNewClusterIsOneRow() throws {
        let lines = Protocol12Extras.lines()
        let image = Protocol12Extras.image()
        let indexPath = Protocol12Extras.indexPath()
        let counts = Protocol12Extras.listCounts()
        XCTAssertEqual(Self.items(Self.group(lines + image + indexPath + counts)), [
            "[lines: count, drawn, truncated]",
            "[image: name, size, scale, renderingMode, symbolConfiguration]",
            "[indexPath: section, item]", "[listCounts: sections, items]",
        ])

        let linesRow = try Self.row(lines)
        XCTAssertEqual(linesRow.title, "Lines")
        XCTAssertEqual(linesRow.texts, ["Drawn 2 of 3", "Truncated"])
        XCTAssertEqual(linesRow.attributeCount, 3)
        XCTAssertTrue(linesRow.truncationIsMarked)

        let imageRow = try Self.row(image)
        XCTAssertEqual(imageRow.title, "Image")
        XCTAssertEqual(imageRow.texts, ["person.crop.circle.fill", "28 × 27 pt · @3x · alwaysTemplate", "Body, Medium"])
        XCTAssertEqual(imageRow.attributeCount, 5)

        let indexRow = try Self.row(indexPath)
        XCTAssertEqual(indexRow.title, "Index Path")
        XCTAssertEqual(indexRow.texts, ["Section 0 · Item 3"])

        let countsRow = try Self.row(counts)
        XCTAssertEqual(countsRow.title, "Counts")
        XCTAssertEqual(countsRow.texts, ["3 sections · 16 items"])
        XCTAssertEqual(try Self.row(Protocol12Extras.listCounts(sections: 1, items: 1)).texts, ["1 section · 1 item"])
    }

    func test_C_ATTR_27_noLimitAndNoTruncationSayLess() throws {
        XCTAssertEqual(try Self.row(Protocol12Extras.lines(count: 0, drawn: 4, truncated: false)).texts, ["Drawn 4"])
        let shown = try Self.row(Protocol12Extras.lines(count: 2, drawn: 2, truncated: false))
        XCTAssertEqual(shown.texts, ["Drawn 2 of 2"])
        XCTAssertFalse(shown.truncationIsMarked)
        XCTAssertEqual(try Self.row(Protocol12Extras.image(configuration: false)).texts.count, 2)
    }

    func test_C_ATTR_27_aTableCountsRows() throws {
        XCTAssertEqual(
            try Self.row(Protocol12Extras.indexPath(), viewBase: "UITableViewCell").texts, ["Section 0 · Row 3"])
        XCTAssertEqual(
            try Self.row(Protocol12Extras.listCounts(), viewBase: "UITableView").texts, ["3 sections · 16 rows"])
        XCTAssertEqual(
            try Self.row(Protocol12Extras.indexPath(), viewBase: "UICollectionViewCell").texts, ["Section 0 · Item 3"])
    }

    func test_C_ATTR_27_aMissingSlotIsNotDrawn() throws {
        XCTAssertEqual(
            try Self.row(Protocol12Extras.lines(count: nil, drawn: nil, truncated: true)).texts, ["Truncated"])
        XCTAssertEqual(try Self.row(Protocol12Extras.indexPath(section: nil, item: 3)).texts, ["Item 3"])
        XCTAssertEqual(try Self.row(Protocol12Extras.indexPath(section: 1, item: nil)).texts, ["Section 1"])
    }

    /// Reported by the user (2026-10-20): a cell out of its collection view has no index path;
    /// its row said nothing, and the Content section looked empty. A missing value reads as
    /// "None", as everywhere else (P-ATTR-03).
    func test_C_ATTR_27_aNilIndexPathReadsAsNone() throws {
        var indexPath = Protocol12Extras.indexPath()
        indexPath[0].value = nil
        indexPath[1].value = nil
        let row = try Self.row(indexPath)
        XCTAssertEqual(row.texts, ["None"])
        var counts = Protocol12Extras.listCounts()
        counts[0].value = nil
        counts[1].value = nil
        XCTAssertEqual(try Self.row(counts).texts, ["None"])
        // One of the two missing: the other alone.
        indexPath = Protocol12Extras.indexPath()
        indexPath[1].value = nil
        XCTAssertEqual(try Self.row(indexPath).texts, ["Section 0"])
    }

    // MARK: - What does not fit

    func test_C_ATTR_27_aMemberOfTheWrongKindIsOnItsOwn() {
        var indexPath = Protocol12Extras.indexPath()
        indexPath[1].value = .string("three")
        indexPath[1].valueKind = .string
        var image = Protocol12Extras.image()
        image[2].value = .bool(true)
        image[2].valueKind = .bool
        XCTAssertEqual(Self.items(Self.group(indexPath + image)), [
            "[indexPath: section]", "cell.indexPath.item",
            "[image: name, size, renderingMode, symbolConfiguration]", "imageView.imageScale",
        ])
    }

    func test_C_ATTR_27_anEditableReadOnlySlotKeepsItsEditor() {
        var lines = Protocol12Extras.lines()
        lines[1].editable = true
        XCTAssertEqual(Self.items(Self.group(lines)), ["[lines: count, truncated]", "label.drawnLineCount"])
        // A rendering mode can be changed in the row.
        var image = Protocol12Extras.image()
        image[3].editable = true
        XCTAssertEqual(Self.items(Self.group(image)), [
            "[image: name, size, scale, renderingMode, symbolConfiguration]",
        ])
    }

    func test_C_ATTR_27_withoutClustersEveryMemberIsOnItsOwn() {
        let all = Protocol12Extras.lines() + Protocol12Extras.image() + Protocol12Extras.indexPath()
            + Protocol12Extras.listCounts()
        let bare = Fixtures.withoutClusters(Self.group(all))
        XCTAssertEqual(Self.items(bare), all.compactMap(\.id))
    }

    // MARK: - Filtering

    func test_C_ATTR_27_filteringMatchesAMembersTitleOrIDNotTheValues() throws {
        let lines = try Self.row(Protocol12Extras.lines())
        XCTAssertTrue(lines.matches("truncated"), "a member's title")
        XCTAssertTrue(lines.matches("drawnLineCount"), "a member's ID")
        let image = try Self.row(Protocol12Extras.image())
        XCTAssertTrue(image.matches("scale"))
        XCTAssertFalse(image.matches("person"), "the symbol's name is a value")
        XCTAssertFalse(image.matches("Medium"))
    }
}
