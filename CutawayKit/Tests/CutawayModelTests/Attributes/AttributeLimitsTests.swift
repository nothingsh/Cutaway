import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel

/// The limits an attribute states for what `SetAttribute` accepts (C-ATTR-13, P-ATTR-09,
/// P-ATTR-10), as rules: whether a number is within them, where a drag stops, and which
/// component of a value is outside.
final class AttributeLimitsTests: XCTestCase {
    private static let zeroToOne = NumberLimit(minimum: 0, maximum: 1)
    private static let atLeastZero = NumberLimit(minimum: 0)
    private static let moreThanZero = NumberLimit(minimum: 0, minimumIsExclusive: true)

    private static func layerThree() throws -> [Attribute] {
        try AttributesStoreTests.layerThree().flatMap(\.attributes)
    }

    private static func attribute(_ id: String) throws -> Attribute {
        try XCTUnwrap(try layerThree().first { $0.id == id })
    }

    private static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> AttributeValue {
        .rect(Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height)))
    }

    func test_C_ATTR_13_containsHonoursOpenAndClosedBounds() {
        XCTAssertTrue(Self.zeroToOne.contains(0))
        XCTAssertTrue(Self.zeroToOne.contains(1))
        XCTAssertTrue(Self.zeroToOne.contains(0.5))
        XCTAssertFalse(Self.zeroToOne.contains(-0.01))
        XCTAssertFalse(Self.zeroToOne.contains(1.4))
        XCTAssertFalse(Self.moreThanZero.contains(0))
        XCTAssertTrue(Self.moreThanZero.contains(0.001))
        let lessThanOne = NumberLimit(maximum: 1, maximumIsExclusive: true)
        XCTAssertFalse(lessThanOne.contains(1))
        XCTAssertTrue(lessThanOne.contains(-1e300))
        XCTAssertTrue(NumberLimit().contains(-20), "no bound leaves it free")
        XCTAssertFalse(Self.atLeastZero.contains(.nan))
    }

    func test_C_ATTR_13_oneEntryCoversEveryComponentOtherwiseOnePerComponent() throws {
        let one = [Self.atLeastZero]
        for index in 0..<4 { XCTAssertEqual(one.limit(forComponent: index), Self.atLeastZero) }
        let bounds = try XCTUnwrap(try Self.attribute("layer.bounds").limits)
        XCTAssertEqual(bounds.limit(forComponent: 0), NumberLimit())
        XCTAssertEqual(bounds.limit(forComponent: 2), Self.atLeastZero)

        var size = Attribute(
            id: "s", title: "S", value: .size(Size(width: 1, height: 1)), editable: true,
            valueKind: .size, limits: one)
        XCTAssertEqual(
            size.limitViolation(of: .size(Size(width: 1, height: -1))),
            LimitViolation(component: 1, reason: .outOfRange(Self.atLeastZero)))
        size.limits = [NumberLimit(), Self.atLeastZero]
        XCTAssertNil(size.limitViolation(of: .size(Size(width: -1, height: 1))))
    }

    func test_C_ATTR_13_anIntegerIsComparedAsADouble() throws {
        let lines = try Self.attribute("label.numberOfLines")
        XCTAssertNil(lines.limitViolation(of: .integer(0)))
        XCTAssertEqual(
            lines.limitViolation(of: .integer(-1)),
            LimitViolation(component: nil, reason: .outOfRange(Self.atLeastZero)))
        let small = Attribute(
            id: "i", title: "I", value: .integer(0), editable: true, valueKind: .integer,
            limits: [NumberLimit(maximum: 9_007_199_254_740_992)])
        XCTAssertNil(small.limitViolation(of: .integer(9_007_199_254_740_992)))
    }

    func test_C_ATTR_13_theFirstComponentOutsideIsNamed() throws {
        let bounds = try Self.attribute("layer.bounds")
        XCTAssertEqual(
            bounds.limitViolation(of: Self.rect(0, 0, -20, 24)),
            LimitViolation(component: 2, reason: .outOfRange(Self.atLeastZero)))
        XCTAssertEqual(
            bounds.limitViolation(of: Self.rect(-20, 0, -20, -1))?.component, 2,
            "x is free: the width is the first outside")
        XCTAssertNil(bounds.limitViolation(of: Self.rect(-20, -5, 0, 0)), "on the bound")
        XCTAssertEqual(bounds.componentsOutsideLimits(of: Self.rect(-20, 0, -20, -1)), [2, 3])
        XCTAssertEqual(bounds.componentsOutsideLimits(of: Self.rect(0, 0, 10, 10)), [])

        let opacity = try Self.attribute("view.alpha")
        XCTAssertEqual(
            opacity.limitViolation(of: .double(1.4)),
            LimitViolation(component: nil, reason: .outOfRange(Self.zeroToOne)))
        XCTAssertNil(opacity.limitViolation(of: .double(1)))
        XCTAssertNil(opacity.limitViolation(of: nil), "nil has no numbers")
        XCTAssertNil(opacity.limitViolation(of: .string("half")), "not a number: the app says")
        XCTAssertEqual(
            try Self.attribute("label.fontSize").limitViolation(of: .double(0)),
            LimitViolation(component: nil, reason: .outOfRange(Self.moreThanZero)))
    }

    func test_C_ATTR_13_noLimitsSendsEverything() throws {
        let groups = try AttributesStoreTests.layerThree()
        let stripped = Fixtures.withoutProtocol11(groups).flatMap(\.attributes)
        for attribute in stripped {
            XCTAssertNil(attribute.limitViolation(of: .double(1.4)))
            XCTAssertNil(attribute.limitViolation(of: Self.rect(0, 0, -20, -20)))
        }
    }

    func test_C_ATTR_13_theNumbersOfAValueAreInTheProtocolsOrder() {
        XCTAssertEqual(AttributeValue.integer(3).numericComponents, [3])
        XCTAssertEqual(AttributeValue.double(0.5).numericComponents, [0.5])
        XCTAssertEqual(Self.rect(1, 2, 3, 4).numericComponents, [1, 2, 3, 4])
        XCTAssertEqual(
            AttributeValue.insets(Insets(top: 1, left: 2, bottom: 3, right: 4)).numericComponents,
            [1, 2, 3, 4])
        XCTAssertEqual(AttributeValue.transform(.identity).numericComponents?.count, 16)
        XCTAssertNil(AttributeValue.bool(true).numericComponents)
        XCTAssertNil(AttributeValue.string("1").numericComponents)
    }
}
