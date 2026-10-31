import AppKit
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-SCALE-03 and C-SCALE-06 in the test configuration: a layer with 1,000 attributes shows in the panel
/// within half a second, a filter of one character updates it within a tenth, and scrolling
/// through it stays as quick, with at most so many rows built. The times are printed.
@MainActor
final class ScaleAttributesTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
    }

    func test_C_SCALE_03_aThousandAttributesShowWithinHalfASecond() async throws {
        let panel = try await ManyAttributes(groups: ManyAttributes.groups(10, of: 100))
        let start = ContinuousClock.now
        let shown = await panel.select()
        let elapsed = ContinuousClock.now - start
        print("C-SCALE-03: 1,000 attributes shown in \(elapsed)")
        XCTAssertTrue(shown)
        XCTAssertLessThanOrEqual(elapsed, .milliseconds(500))
        // The most specific group first (C-ATTR-10): the last one made.
        XCTAssertEqual(panel.titlesInView.first, "Attribute 9.0")
        await panel.close()
    }

    func test_C_SCALE_03_aFilterOfOneCharacterUpdatesWithinATenth() async throws {
        let panel = try await ManyAttributes(groups: ManyAttributes.groups(10, of: 100))
        let selected = await panel.select()
        XCTAssertTrue(selected)
        for text in ["7", "", "9", "x", ""] {
            let start = ContinuousClock.now
            panel.controller.setFilter(text)
            panel.window.layoutIfNeeded()
            let elapsed = ContinuousClock.now - start
            print("C-SCALE-03: the filter \"\(text)\" took \(elapsed)")
            XCTAssertLessThanOrEqual(elapsed, .milliseconds(100), "\"\(text)\"")
            XCTAssertEqual(panel.unbuiltInView, 0, "\"\(text)\"")
        }
        await panel.close()
    }

    func test_C_SCALE_03_scrollingToTheEndStaysQuickAndBuildsSoMany() async throws {
        let panel = try await ManyAttributes(groups: ManyAttributes.groups(10, of: 100))
        let selected = await panel.select()
        XCTAssertTrue(selected)
        var slowest = Duration.zero
        var y: CGFloat = 0
        while y + panel.visible.height < panel.document.frame.height {
            y += panel.visible.height
            let start = ContinuousClock.now
            panel.scroll(to: y)
            slowest = max(slowest, ContinuousClock.now - start)
            XCTAssertEqual(panel.unbuiltInView, 0, "at \(y)")
            XCTAssertLessThan(panel.controller.attributeRows.count, 300, "at \(y)")
        }
        print("C-SCALE-03: the slowest screen of scrolling took \(slowest)")
        XCTAssertLessThanOrEqual(slowest, .milliseconds(100))
        XCTAssertEqual(panel.titlesInView.last, "Attribute 0.99")
        await panel.close()
    }

    /// About 100 attributes each: one group that both have, others that differ, as two classes
    /// of view share most of what a view has.
    private static func groups(_ name: String) -> [AttributeGroup] {
        var groups = ManyAttributes.groups(4, of: 20)
        for index in groups.indices where index > 0 {
            groups[index].id = "\(name)\(index)"
        }
        groups[3].attributes.append(contentsOf: ManyAttributes.groups(1, of: 20)[0].attributes.map {
            var attribute = $0
            attribute.id = "\(name)-\(attribute.id ?? "")"
            return attribute
        })
        return groups
    }

    func test_C_SCALE_06_goingFromOneLayerToAnotherTakesUnderTheLimit() async throws {
        let panel = try await ManyAttributes(groups: Self.groups("a"), others: Self.groups("b"))
        let first = await panel.select(3)
        XCTAssertTrue(first)
        var slowest = Duration.zero
        for id: UInt64 in [8, 3, 8, 3, 8, 3] {
            let start = ContinuousClock.now
            let shown = await panel.select(id)
            panel.window.layoutIfNeeded()
            let elapsed = ContinuousClock.now - start
            XCTAssertTrue(shown)
            slowest = max(slowest, elapsed)
            print("C-SCALE-06: layer \(id) shown in \(elapsed)")
        }
        XCTAssertLessThanOrEqual(slowest, .milliseconds(Self.switchLimit))
        await panel.close()
    }

    /// C-SCALE-06: about four tenths over the slowest measured, the first time, 105 ms.
    private static let switchLimit = 150
}
