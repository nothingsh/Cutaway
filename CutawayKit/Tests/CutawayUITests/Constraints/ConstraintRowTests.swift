import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// How the panel writes a constraint (C-LAYOUT-02), by the `layout-constraints` fixture on the
/// layers of `hierarchy`.
final class ConstraintRowTests: XCTestCase {
    private func tree() throws -> LayerTree {
        try LayerTree(try Fixtures.hierarchy())
    }

    private func texts(of id: UInt64) throws -> [ConstraintRow] {
        let tree = try tree()
        return try Fixtures.constraints(of: id).map { ConstraintRow($0, selected: id, tree: tree) }
    }

    /// `3.width == 240` of the fixture, changed by `change`.
    private func constraint(_ change: (inout LayoutConstraint) -> Void) throws -> LayoutConstraint {
        var constraint = try Fixtures.constraints(of: 3)[2]
        constraint.identifier = nil
        constraint.priority = 1000
        constraint.status = .satisfied
        change(&constraint)
        return constraint
    }

    private func text(_ constraint: LayoutConstraint, selected: UInt64 = 3) throws -> ConstraintRow {
        ConstraintRow(constraint, selected: selected, tree: try tree())
    }

    // MARK: - The fixture

    func test_C_LAYOUT_02_layerThreesConstraintsAreWrittenInTheServersOrder() throws {
        let three = try texts(of: 3)
        XCTAssertEqual(three.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(three.map(\.plainEquation), [
            "self.centerX = UIView.centerX",
            "self.top = Safe Area.top + 49",
            "self.width = 240",
            "CardView.top = self.bottom + 78",
        ])
        XCTAssertEqual(three[0].equation, [
            .selfItem, .text(".centerX = "), .link("UIView", layerID: 2), .text(".centerX"),
        ])
        // A guide goes to its owner (C-LAYOUT-03), and says whose it is.
        XCTAssertEqual(three[1].equation, [
            .selfItem, .text(".top = "), .link("Safe Area", layerID: 2), .text(".top + 49"),
        ])
        XCTAssertEqual(three[1].guideOwners, ["Safe Area of UIView"])
        XCTAssertEqual(three[3].equation, [
            .link("CardView", layerID: 4), .text(".top = "), .selfItem, .text(".bottom + 78"),
        ])
        XCTAssertEqual(
            three.map(\.details), [nil, nil, "Priority 250 · titleLabel.preferredWidth", nil])
        XCTAssertEqual(three.map(\.status), [.satisfied, .satisfied, .unsatisfied, .satisfied])
        XCTAssertEqual(three.map(\.generatedClassName), [nil, nil, nil, nil])
    }

    func test_C_LAYOUT_02_theSameConstraintSeenFromItsOtherEnd() throws {
        let four = try texts(of: 4)
        XCTAssertEqual(four.map(\.plainEquation), [
            "self.top = UILabel.bottom + 78",
            "self.width = 300",
            "self.height = 180",
            "self.centerX = UIView.centerX",
        ])
        XCTAssertEqual(four[0].equation.last, .text(".bottom + 78"))
        XCTAssertEqual(four[0].equation[2], .link("UILabel", layerID: 3))
    }

    func test_C_LAYOUT_02_constraintsUIKitMadeNameTheirClass() throws {
        let nine = try texts(of: 9)
        XCTAssertEqual(nine.count, 4)
        XCTAssertEqual(
            nine.map(\.generatedClassName),
            Array(repeating: "NSAutoresizingMaskLayoutConstraint", count: 4))
        XCTAssertEqual(
            ConstraintRow.readableClassName("NSAutoresizingMaskLayoutConstraint"),
            "Autoresizing Mask")
    }

    // MARK: - The parts of an equation

    func test_C_LAYOUT_02_relationsMultipliersAndConstants() throws {
        let two = LayoutItem.view(layerID: 2)
        let cases: [(LayoutRelation, Double, Double, String)] = [
            (.lessThanOrEqual, 0.5, 0, "self.width ≤ UIView.width × 0.5"),
            (.greaterThanOrEqual, 1, -8, "self.width ≥ UIView.width − 8"),
            (.equal, 2, 12.25, "self.width = UIView.width × 2 + 12.25"),
            (.equal, 1, 0, "self.width = UIView.width"),
        ]
        for (relation, multiplier, constant, expected) in cases {
            let written = try text(try constraint {
                $0.relation = relation
                $0.secondItem = two
                $0.secondAttribute = .width
                $0.multiplier = multiplier
                $0.constant = constant
            })
            XCTAssertEqual(written.plainEquation, expected)
        }
        // Without a second item: the constant alone, whatever the multiplier.
        let negative = try text(try constraint {
            $0.constant = -4
            $0.multiplier = 3
        })
        XCTAssertEqual(negative.plainEquation, "self.width = −4")
    }

    func test_C_LAYOUT_02_everyAttributeHasItsUIKitName() {
        let names = (1...20).compactMap(LayoutAttribute.init(rawValue:))
            .map(ConstraintRow.name(of:))
        XCTAssertEqual(names, [
            "left", "right", "top", "bottom", "leading", "trailing", "width", "height", "centerX",
            "centerY", "lastBaseline", "firstBaseline", "leftMargin", "rightMargin", "topMargin",
            "bottomMargin", "leadingMargin", "trailingMargin", "centerXWithinMargins",
            "centerYWithinMargins",
        ])
    }

    // MARK: - C-LAYOUT-05

    func test_C_LAYOUT_05_theAutoresizingAttributesHaveUIKitsNames() throws {
        XCTAssertEqual(
            [LayoutAttribute.minX, .minY, .maxX, .maxY].map(ConstraintRow.name(of:)),
            ["minX", "minY", "maxX", "maxY"])

        let nine = try texts(of: 9)
        XCTAssertEqual(nine.map(\.plainEquation), [
            "UIView.width = self.maxX + 93",
            "self.width = 0",
            "self.minY = 700",
            "self.height = 0",
        ])
        // The superview's end, written first, still goes to it (C-LAYOUT-03).
        XCTAssertEqual(nine[0].equation, [
            .link("UIView", layerID: 2), .text(".width = "), .selfItem, .text(".maxX + 93"),
        ])
    }

    /// P-LAYOUT-08: an end whose attribute the server could not name.
    func test_C_LAYOUT_05_anEndWithoutANamedAttributeSaysUnknown() throws {
        XCTAssertEqual(ConstraintRow.name(of: .notAnAttribute), "unknown")

        let first = try text(try constraint { $0.firstAttribute = .notAnAttribute })
        XCTAssertEqual(first.plainEquation, "self.unknown = 240")

        let second = try text(try constraint {
            $0.firstItem = .view(layerID: 2)
            $0.firstAttribute = .width
            $0.secondItem = .view(layerID: 3)
            $0.secondAttribute = .notAnAttribute
            $0.constant = 93
        })
        XCTAssertEqual(second.plainEquation, "UIView.width = self.unknown + 93")
        XCTAssertEqual(second.equation.first, .link("UIView", layerID: 2))

        // Without a second item there is no second attribute to name (P-LAYOUT-05).
        let alone = try text(try constraint {
            $0.secondItem = nil
            $0.secondAttribute = .top
        })
        XCTAssertEqual(alone.plainEquation, "self.width = 240")
    }

    // MARK: - The ends

    func test_C_LAYOUT_02_endsThatAreNotLayersOfTheTree() throws {
        let unknown = try text(try constraint {
            $0.secondItem = .view(layerID: 42)
            $0.secondAttribute = .width
            $0.constant = 0
        })
        XCTAssertEqual(
            unknown.equation, [.selfItem, .text(".width = ID 42.width")], "not a link (C-LAYOUT-03)")
        let other = try text(try constraint {
            $0.secondItem = .other(className: "Demo.Spacer", displayClassName: "Spacer")
            $0.secondAttribute = .width
            $0.constant = 0
        })
        XCTAssertEqual(other.plainEquation, "self.width = Spacer.width")
        XCTAssertFalse(other.equation.contains { if case .link = $0 { true } else { false } })
        let missing = try text(try constraint { $0.firstItem = nil })
        XCTAssertEqual(missing.plainEquation, "?.width = 240")
    }

    func test_C_LAYOUT_02_layoutGuidesAreNamed() throws {
        func guide(_ identifier: String?, owner: UInt64 = 2) -> LayoutItem {
            .layoutGuide(LayoutGuide(
                ownerLayerID: owner, guideID: 7, className: "UILayoutGuide",
                displayClassName: "LayoutGuide", identifier: identifier, frame: nil))
        }
        let named: [(String?, String)] = [
            ("UIViewSafeAreaLayoutGuide", "Safe Area"),
            ("UIViewLayoutMarginsGuide", "Layout Margins"),
            ("UIViewReadableContentGuide", "Readable Content"),
            ("UIKeyboardLayoutGuide", "Keyboard"),
            ("contentGuide", "contentGuide"),
            (nil, "LayoutGuide"),
            ("", "LayoutGuide"),
        ]
        for (identifier, name) in named {
            let written = try text(try constraint {
                $0.secondItem = guide(identifier)
                $0.secondAttribute = .top
                $0.constant = 0
            })
            XCTAssertEqual(written.equation[2], .link(name, layerID: 2), "\(identifier ?? "nil")")
            XCTAssertEqual(written.guideOwners, ["\(name) of UIView"])
        }
        // The selected view's own guide: nowhere to go.
        let own = try text(try constraint {
            $0.secondItem = guide("UIViewSafeAreaLayoutGuide", owner: 3)
            $0.secondAttribute = .top
            $0.constant = 0
        })
        XCTAssertEqual(own.equation, [.selfItem, .text(".width = Safe Area.top")])
        XCTAssertEqual(own.guideOwners, ["Safe Area of self"])
        let unknownOwner = try text(try constraint {
            $0.secondItem = guide("UIViewSafeAreaLayoutGuide", owner: 42)
            $0.secondAttribute = .top
            $0.constant = 0
        })
        XCTAssertEqual(unknownOwner.equation, [.selfItem, .text(".width = Safe Area.top")])
        XCTAssertEqual(unknownOwner.guideOwners, ["Safe Area of ID 42"])
    }

    // MARK: - The lines below

    func test_C_LAYOUT_02_priorityAndIdentifier() throws {
        let cases: [(Float, String?, String?)] = [
            (1000, nil, nil),
            (999, nil, "Priority 999"),
            (750.5, nil, "Priority 750.5"),
            (1000, "card.top", "card.top"),
            (1000, "", nil),
            (250, "a", "Priority 250 · a"),
        ]
        for (priority, identifier, details) in cases {
            let written = try text(try constraint {
                $0.priority = priority
                $0.identifier = identifier
            })
            XCTAssertEqual(written.details, details)
        }
    }

    func test_C_LAYOUT_02_whichConstraintsUIKitMade() throws {
        for (className, generated) in [
            ("NSLayoutConstraint", false), ("NSAutoresizingMaskLayoutConstraint", true),
            ("NSContentSizeLayoutConstraint", true),
        ] {
            let written = try text(try constraint { $0.className = className })
            XCTAssertEqual(written.generatedClassName, generated ? className : nil)
        }
        XCTAssertNil(try text(try constraint { $0.className = nil }).generatedClassName)
        XCTAssertEqual(
            ConstraintRow.readableClassName("NSContentSizeLayoutConstraint"), "Content Size")
        XCTAssertEqual(
            ConstraintRow.readableClassName("_UILayoutSupportConstraint"), "Layout Support")
        XCTAssertNil(ConstraintRow.readableClassName("NSLayoutConstraint"))
    }
}
