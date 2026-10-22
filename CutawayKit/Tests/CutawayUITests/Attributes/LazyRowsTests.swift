import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-SCALE-03, untimed: a layer with very many attributes is built page by page. Every
/// item is in its place, a row being typed in or changed stays, what is seen stays where it is,
/// the filter keeps what it kept when every row was built, and a layer of 200 items or fewer is
/// built at once, as before.
@MainActor
final class LazyRowsTests: XCTestCase {
    /// The titles in the order of the list: the most specific group first (C-ATTR-10).
    private static func titles(_ groups: Int, of perGroup: Int) -> [String] {
        (0..<groups).reversed().flatMap { group in (0..<perGroup).map { "Attribute \(group).\($0)" } }
    }

    func test_C_SCALE_03_aLayerOfTwoHundredItemsIsBuiltAtOnce() async throws {
        let panel = try await ManyAttributes(groups: ManyAttributes.groups(2, of: 100))
        let selected = await panel.select()
        XCTAssertTrue(selected)
        XCTAssertTrue(panel.controller.lazyParts.isEmpty)
        XCTAssertEqual(panel.controller.attributeRows.count, 200)
        await panel.close()

        let more = try await ManyAttributes(
            groups: ManyAttributes.groups(2, of: 100) + ManyAttributes.groups(1, of: 1).map {
                AttributeGroup(id: "one", title: "One", attributes: $0.attributes)
            })
        let shown = await more.select()
        XCTAssertTrue(shown)
        XCTAssertFalse(more.controller.lazyParts.isEmpty, "201 items: page by page")
        XCTAssertLessThan(more.controller.attributeRows.count, 201)
        await more.close()
    }

    /// Every one of 1,000 attributes can be scrolled to and has its row there (C-ATTR-09), in
    /// the list's order.
    func test_C_SCALE_03_scrollingShowsEveryItemInItsOrderWithoutJumps() async throws {
        let panel = try await ManyAttributes(groups: ManyAttributes.groups(10, of: 100))
        let selected = await panel.select()
        XCTAssertTrue(selected)
        XCTAssertLessThan(panel.controller.attributeRows.count, 1_000, "built page by page")
        let order = Self.titles(10, of: 100)
        var seen = Set<String>()
        var lastIndex = 0
        var y: CGFloat = 0
        while y + panel.visible.height < panel.document.frame.height {
            let titles = panel.titlesInView
            seen.formUnion(titles)
            let first = try XCTUnwrap(titles.first, "nothing in view at \(y)")
            let index = try XCTUnwrap(order.firstIndex(of: first))
            // What is in view is a run of the list, in its order.
            XCTAssertEqual(Array(order[index..<min(index + titles.count, order.count)]), titles, "at \(y)")
            // Scrolling by 50 points moves the list by a row or two, never more.
            XCTAssertGreaterThanOrEqual(index, lastIndex, "at \(y)")
            XCTAssertLessThanOrEqual(index - lastIndex, 3, "at \(y)")
            lastIndex = index
            y += 50
            panel.scroll(to: y)
        }
        XCTAssertGreaterThan(lastIndex, 950)
        seen.formUnion(panel.titlesInView)
        XCTAssertEqual(seen, Set(order), "every attribute was in view")
        await panel.close()
    }

    func test_C_SCALE_03_aRowBeingTypedInOrChangedIsNotTakenDown() async throws {
        let panel = try await ManyAttributes(groups: ManyAttributes.groups(10, of: 100))
        let selected = await panel.select()
        XCTAssertTrue(selected)
        let typed = try XCTUnwrap(panel.controller.attributeRows.first { $0.row.title == "Attribute 9.2" })
        let field = try XCTUnwrap(
            AppListViewTests
                .descendants(of: typed.row) { $0 is NSTextField && ($0 as? NSTextField)?.isEditable == true }
                .first)
        panel.window.makeFirstResponder(field)
        let changed = try XCTUnwrap(panel.controller.attributeRows.first { $0.row.title == "Attribute 9.5" })
        let key = try XCTUnwrap(panel.controller.viewModel.key(of: changed.attribute))
        panel.model.attributes.set(key, to: .double(1), continuous: false)
        XCTAssertNotNil(panel.model.attributes.edits[key], "on its way")

        panel.scroll(to: panel.document.frame.height - panel.visible.height)
        let built = Set(panel.controller.attributeRows.map(\.row.title))
        XCTAssertTrue(built.contains("Attribute 9.2"), "typed in")
        XCTAssertTrue(built.contains("Attribute 9.5"), "being changed")
        XCTAssertTrue(built.contains("Attribute 9.10"), "the whole page stays with them")
        XCTAssertFalse(built.contains("Attribute 8.0"), "far from what is seen: taken down")
        await panel.close()
    }

    func test_C_SCALE_03_theFilterKeepsWhatItKeptWhenEveryRowWasBuilt() async throws {
        let panel = try await ManyAttributes(groups: ManyAttributes.groups(10, of: 100))
        let selected = await panel.select()
        XCTAssertTrue(selected)
        // By title and by ID, as an attribute's own row matches (C-ATTR-14).
        for (filter, expected, byTitle) in [
            ("Attribute 3.4", ["Attribute 3.4"] + (40..<50).map { "Attribute 3.\($0)" }, true),
            ("a7.9", ["Attribute 7.9"] + (90..<100).map { "Attribute 7.\($0)" }, false),
            ("nothing", [], false),
        ] {
            panel.controller.setFilter(filter)
            panel.window.layoutIfNeeded()
            let kept = panel.controller.lazyParts.flatMap(\.items).map { item -> String in
                guard case .single(let attribute) = item else { return "" }
                return AttributeText.title(attribute.title, id: attribute.id)
            }
            XCTAssertEqual(kept, expected, filter)
            XCTAssertEqual(panel.controller.filterCounts?.shown, expected.count, filter)
            XCTAssertEqual(panel.controller.filterCounts?.total, 1_000, filter)
            // From the top, in their order, as many as there is room for.
            let titles = panel.titlesInView
            XCTAssertEqual(titles, Array(expected.prefix(titles.count)), filter)
            XCTAssertEqual(titles.isEmpty, expected.isEmpty, filter)
            // A match in the title is marked there (C-ATTR-14); one in the ID has nothing to mark.
            if byTitle {
                let marked = panel.controller.attributeRows.map(\.row).allSatisfy { row in
                    !AppListViewTests.descendants(of: row) { ($0 as? WrappingTitleField)?.showsMatch == true }.isEmpty
                }
                XCTAssertTrue(marked, "the built rows mark the match: \(filter)")
            }
        }
        panel.controller.setFilter("")
        panel.window.layoutIfNeeded()
        XCTAssertEqual(panel.titlesInView.first, "Attribute 9.0")
        XCTAssertNil(panel.controller.filterCounts)
        await panel.close()
    }

    func test_C_SCALE_03_newValuesComeInPlace() async throws {
        let panel = try await ManyAttributes(groups: ManyAttributes.groups(10, of: 100), editing: .apply)
        let selected = await panel.select()
        XCTAssertTrue(selected)
        let target = try XCTUnwrap(panel.controller.attributeRows.first { $0.row.title == "Attribute 9.3" })
        let row = target.row
        let key = try XCTUnwrap(panel.controller.viewModel.key(of: target.attribute))
        panel.controller.viewModel.setValue(for: key)(.double(42), false)
        let shown = await Wait.untilOnMain(within: .seconds(5)) {
            panel.controller.attributeRows.first { $0.row.title == "Attribute 9.3" }?.attribute.value == .double(42)
                && row.value == .double(42)
        }
        XCTAssertTrue(shown, "the same row, with the new value")
        XCTAssertTrue(panel.controller.attributeRows.contains { $0.row === row }, "not built again")
        await panel.close()
    }
}
