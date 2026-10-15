import CutawayModel
import CutawayScene
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

    /// The chip of a view of the tree.
    private func view(_ id: UInt64, _ name: String) throws -> ConstraintRow.Piece {
        .end(ConstraintRow.End(
            name: name, kind: .view(LayerIcon(try tree().node(id))), layerID: id, mark: .layer(id)))
    }

    /// The chip of a layout guide.
    private func guideChip(
        _ name: String, owner: UInt64?, mark: SceneMark? = nil
    ) -> ConstraintRow.Piece {
        .end(ConstraintRow.End(name: name, kind: .guide, layerID: owner, mark: mark))
    }

    /// The fixture's safe area of layer 2, as the preview marks it.
    private static let safeArea = SceneMark.area(
        SceneRect(x: 0, y: 59, width: 393, height: 759), in: 2)

    // MARK: - The fixture

    func test_C_LAYOUT_02_layerThreesConstraintsAreWrittenInTheServersOrder() throws {
        let three = try texts(of: 3)
        XCTAssertEqual(three.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(three.map(\.plainEquation), [
            "self.centerX = HomeViewController.centerX",
            "self.top = Safe Area.top + 49",
            "self.width = 240",
            "cardView.top = self.bottom + 78",
        ])
        // A view by its short name (C-LAYOUT-06): a controller's root view by the controller,
        // a view a member holds by the member.
        XCTAssertEqual(three[0].equation, [
            .selfItem, .text(".centerX = "), try view(2, "HomeViewController"), .text(".centerX"),
        ])
        // A guide goes to its owner (C-LAYOUT-03), and says whose it is.
        XCTAssertEqual(three[1].equation, [
            .selfItem, .text(".top = "), guideChip("Safe Area", owner: 2, mark: Self.safeArea),
            .text(".top + 49"),
        ])
        XCTAssertEqual(three[1].guideOwners, ["Safe Area of UIView"])
        XCTAssertEqual(three[3].equation, [
            try view(4, "cardView"), .text(".top = "), .selfItem, .text(".bottom + 78"),
        ])
        XCTAssertEqual(
            three.map(\.details), [nil, nil, "Priority 250 · titleLabel.preferredWidth", nil])
        XCTAssertEqual(three.map(\.status), [.satisfied, .satisfied, .unsatisfied, .satisfied])
        XCTAssertEqual(three.map(\.generatedClassName), [nil, nil, nil, nil])
    }

    func test_C_LAYOUT_02_theSameConstraintSeenFromItsOtherEnd() throws {
        let four = try texts(of: 4)
        XCTAssertEqual(four.map(\.plainEquation), [
            "self.top = titleLabel.bottom + 78",
            "self.width = 300",
            "self.height = 180",
            "self.centerX = HomeViewController.centerX",
        ])
        XCTAssertEqual(four[0].equation.last, .text(".bottom + 78"))
        XCTAssertEqual(four[0].equation[2], try view(3, "titleLabel"))
    }

    // MARK: - The parts of an equation

    func test_C_LAYOUT_02_relationsMultipliersAndConstants() throws {
        let two = LayoutItem.view(layerID: 2)
        let cases: [(LayoutRelation, Double, Double, String)] = [
            (.lessThanOrEqual, 0.5, 0, "self.width ≤ HomeViewController.width × 0.5"),
            (.greaterThanOrEqual, 1, -8, "self.width ≥ HomeViewController.width − 8"),
            (.equal, 2, 12.25, "self.width = HomeViewController.width × 2 + 12.25"),
            (.equal, 1, 0, "self.width = HomeViewController.width"),
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

    // MARK: - C-LAYOUT-05

    func test_C_LAYOUT_05_theAutoresizingAttributesHaveUIKitsNames() throws {
        XCTAssertEqual(
            [LayoutAttribute.minX, .minY, .maxX, .maxY].map(ConstraintRow.name(of:)),
            ["minX", "minY", "maxX", "maxY"])

        let nine = try texts(of: 9)
        XCTAssertEqual(nine.map(\.plainEquation), [
            "HomeViewController.width = self.maxX + 93",
            "self.width = 0",
            "self.minY = 700",
            "self.height = 0",
        ])
        // The superview's end, written first, still goes to it (C-LAYOUT-03).
        XCTAssertEqual(nine[0].equation, [
            try view(2, "HomeViewController"), .text(".width = "), .selfItem, .text(".maxX + 93"),
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
        XCTAssertEqual(second.plainEquation, "HomeViewController.width = self.unknown + 93")
        XCTAssertEqual(second.equation.first, try view(2, "HomeViewController"))

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
        // A chip that goes nowhere and marks nothing (C-LAYOUT-03, C-LAYOUT-06).
        XCTAssertEqual(unknown.equation, [
            .selfItem, .text(".width = "),
            .end(ConstraintRow.End(
                name: "ID 42", kind: .view(LayerIcon(.container, .view, isAppClass: false)),
                layerID: nil, mark: nil)),
            .text(".width"),
        ])
        XCTAssertEqual(unknown.plainEquation, "self.width = ID 42.width")
        let other = try text(try constraint {
            $0.secondItem = .other(className: "Demo.Spacer", displayClassName: "Spacer")
            $0.secondAttribute = .width
            $0.constant = 0
        })
        XCTAssertEqual(other.plainEquation, "self.width = Spacer.width")
        XCTAssertFalse(other.equation.contains { if case .end = $0 { true } else { false } })
        let missing = try text(try constraint { $0.firstItem = nil })
        XCTAssertEqual(missing.plainEquation, "?.width = 240")
    }

    func test_C_LAYOUT_02_theServersOriginDecidesWhichConstraintsUIKitMade() throws {
        // The origin wins over the class either way (P-LAYOUT-09).
        let app = try text(try constraint {
            $0.className = "NSAutoresizingMaskLayoutConstraint"
            $0.origin = .app
        })
        XCTAssertNil(app.generatedClassName)
        let system = try text(try constraint {
            $0.className = "NSLayoutConstraint"
            $0.origin = .system
        })
        XCTAssertEqual(system.generatedClassName, "NSLayoutConstraint")
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
            XCTAssertEqual(written.equation[2], guideChip(name, owner: 2), "\(identifier ?? "nil")")
            XCTAssertEqual(written.guideOwners, ["\(name) of UIView"])
        }
        // The selected view's own guide: nowhere to go.
        let own = try text(try constraint {
            $0.secondItem = guide("UIViewSafeAreaLayoutGuide", owner: 3)
            $0.secondAttribute = .top
            $0.constant = 0
        })
        XCTAssertEqual(own.equation, [
            .selfItem, .text(".width = "), guideChip("Safe Area", owner: nil), .text(".top"),
        ])
        XCTAssertEqual(own.guideOwners, ["Safe Area of self"])
        let unknownOwner = try text(try constraint {
            $0.secondItem = guide("UIViewSafeAreaLayoutGuide", owner: 42)
            $0.secondAttribute = .top
            $0.constant = 0
        })
        XCTAssertEqual(unknownOwner.equation, [
            .selfItem, .text(".width = "), guideChip("Safe Area", owner: nil), .text(".top"),
        ])
        XCTAssertEqual(unknownOwner.guideOwners, ["Safe Area of ID 42"])
    }

    // MARK: - The lines below

    func test_C_LAYOUT_02_whichConstraintsUIKitMade() throws {
        // From a server that gives no origin, by the class.
        for (className, generated) in [
            ("NSLayoutConstraint", false), ("NSLayoutAnchorConstraint", false),
            ("NSAutoresizingMaskLayoutConstraint", true), ("NSContentSizeLayoutConstraint", true),
        ] {
            let written = try text(try constraint {
                $0.className = className
                $0.origin = .unknown
            })
            XCTAssertEqual(written.generatedClassName, generated ? className : nil)
        }
        XCTAssertNil(try text(try constraint {
            $0.className = nil
            $0.origin = .unknown
        }).generatedClassName)
        XCTAssertEqual(
            ConstraintRow.readableClassName("NSContentSizeLayoutConstraint"), "Content Size")
        XCTAssertEqual(
            ConstraintRow.readableClassName("_UILayoutSupportConstraint"), "Layout Support")
        XCTAssertNil(ConstraintRow.readableClassName("NSLayoutConstraint"))
    }

    // MARK: - C-LAYOUT-06: the chips

    func test_C_LAYOUT_06_layerThreesEndsAreChipsForTheirLayersAndMarks() throws {
        let three = try texts(of: 3)
        let ends = three.map { $0.equation.compactMap { piece -> ConstraintRow.End? in
            if case .end(let end) = piece { end } else { nil }
        } }
        // A view, the safe area, nothing but a constant, and the view the label sits above.
        XCTAssertEqual(ends.map { $0.map(\.name) }, [["HomeViewController"], ["Safe Area"], [], ["cardView"]])
        XCTAssertEqual(ends.map { $0.map(\.layerID) }, [[2], [2], [], [4]])
        // The chips mark what the preview marks for the constraints.
        let marks = try ConstraintEnd.ends(of: Fixtures.constraints(of: 3), selected: 3).map(\.mark)
        XCTAssertEqual(ends.flatMap { $0.compactMap(\.mark) }, marks)
        XCTAssertTrue(ends.joined().allSatisfy { $0.canSelect && $0.canHover })
    }

    func test_C_LAYOUT_06_anEndThatIsNotInTheTreeCannotBeChosen() throws {
        // Layer 3's constraints with layers 2 and 4 gone from the tree: 42 and 44.
        func gone(_ item: LayoutItem?) -> LayoutItem? {
            switch item {
            case .view(let id) where id != 3:
                return .view(layerID: id + 40)
            case .layoutGuide(var guide):
                guide.ownerLayerID += 40
                return .layoutGuide(guide)
            default:
                return item
            }
        }
        let rows = try Fixtures.constraints(of: 3).map { constraint in
            var constraint = constraint
            constraint.firstItem = gone(constraint.firstItem)
            constraint.secondItem = gone(constraint.secondItem)
            return try text(constraint)
        }
        let ends = rows.flatMap { $0.equation.compactMap { piece -> ConstraintRow.End? in
            if case .end(let end) = piece { end } else { nil }
        } }
        XCTAssertEqual(ends.map(\.name), ["ID 42", "Safe Area", "ID 44"])
        XCTAssertTrue(ends.allSatisfy { !$0.canSelect && !$0.canHover })
    }
}
