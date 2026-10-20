import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// Compound rows (C-ATTR-19): which attributes make one, what each draws, and that each part
/// edits its own attribute. What a part sends is caught where the panel would hand it to the
/// model.
final class CompoundRowTests: XCTestCase {
    // MARK: - Listing

    private static func attribute(
        _ id: String, _ value: AttributeValue?, _ kind: AttributeValueKind, cluster: String? = nil,
        slot: String? = nil, section: AttributeSection = .appearance, limits: [NumberLimit]? = nil,
        unit: AttributeUnit = .unspecified
    ) -> Attribute {
        Attribute(
            id: id, title: id, value: value, editable: true, valueKind: kind, section: section,
            limits: limits, cluster: cluster.map { AttributeCluster(name: $0, slot: slot ?? "") }, unit: unit)
    }

    private static func layer(_ scenario: String, _ id: UInt64) throws -> [AttributeGroup] {
        try Fixtures.attributes(of: id, scenario: scenario)
    }

    /// What a section lists: each item's cluster name, or the attribute's ID.
    private static func items(
        _ kind: AttributesViewModel.Listing.Kind, of groups: [AttributeGroup]
    ) -> [String] {
        let section = AttributesViewModel.listing(of: groups).section(kind)
        return (section?.parts ?? []).flatMap(\.listed).map { item in
            switch item {
            case .single(let attribute): attribute.id ?? ""
            case .cluster(let row): "[\(row.kind.rawValue): \(row.order.joined(separator: ", "))]"
            }
        }
    }

    func test_C_ATTR_19_theFixturesClustersAreRowsWhereTheirFirstMembersAre() throws {
        let three = try Self.layer("layer-details", 3)
        XCTAssertEqual(Self.items(.appearance, of: three), [
            "[visibility: hidden, opacity]", "view.backgroundColor", "view.tintColor",
            "[shadow: opacity, offset]", "[border: width, color]",
        ])
        XCTAssertEqual(Self.items(.accessibility, of: three), ["view.accessibilityLabel"])
        XCTAssertEqual(Self.items(.layout, of: three), [
            "view.layoutMargins", "[geometry: frame, bounds, position, transform]",
        ])
        XCTAssertEqual(Self.items(.content, of: three), [
            "label.text", "[font: size, textStyle, scalable]", "[lines: count]", "label.textAlignment",
        ])
        // Every attribute once.
        let listed = AttributesViewModel.listing(of: three).attributes.compactMap(\.id)
        XCTAssertEqual(listed.count, three.flatMap(\.attributes).count)
        XCTAssertEqual(Set(listed).count, listed.count)
    }

    /// As in layer 4 of the `set-attribute` replies: the radius is the layer's, the clip the
    /// view's.
    func test_C_ATTR_19_aClusterGathersItsMembersFromEveryGroup() {
        let layer = AttributeGroup(id: "layer", title: "Layer", attributes: [
            Self.attribute("layer.cornerRadius", .double(12), .double, cluster: "corners", slot: "radius"),
            Self.attribute("layer.borderWidth", .double(0), .double),
        ])
        let view = AttributeGroup(id: "view", title: "View", attributes: [
            Self.attribute("view.alpha", .double(1), .double),
            Self.attribute("view.clipsToBounds", .bool(true), .bool, cluster: "corners", slot: "clip"),
        ])
        // The view's group is listed first, so the row is where the clip is.
        XCTAssertEqual(Self.items(.appearance, of: [layer, view]), [
            "view.alpha", "[corners: clip, radius]", "layer.borderWidth",
        ])
    }

    @MainActor
    func test_C_ATTR_19_withoutClustersEveryAttributeHasItsRow() throws {
        let three = try Self.layer("layer-details", 3).map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                attribute.cluster = nil
                return attribute
            }
            return group
        }
        for kind in AttributesViewModel.Listing.Kind.allCases {
            XCTAssertFalse(Self.items(kind, of: three).contains { $0.hasPrefix("[") }, "\(kind)")
        }
    }

    func test_C_ATTR_19_whatDoesNotFitGoesOnItsOwnAfterTheRow() {
        let group = AttributeGroup(id: "g", title: "G", attributes: [
            Self.attribute("w", .double(1), .double, cluster: "border", slot: "width"),
            Self.attribute("odd", .double(1), .double, cluster: "border", slot: "glow"),
            Self.attribute("c", .bool(true), .bool, cluster: "border", slot: "color"),
            Self.attribute("w2", .double(2), .double, cluster: "border", slot: "width"),
            Self.attribute("x", .double(1), .double, cluster: "sparkle", slot: "amount"),
            Self.attribute("y", .double(1), .double),
        ])
        XCTAssertEqual(Self.items(.appearance, of: [group]), [
            "[border: width]", "odd", "c", "w2", "x", "y",
        ], "an unknown slot, a value of another kind, a second width and an unknown cluster")
    }

    // MARK: - Rows

    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> AttributeValue {
        .rect(Rect(origin: Point(x: x, y: y), size: Size(width: w, height: h)))
    }

    // MARK: - Transform

    func test_C_ATTR_19_aTransformSaysWhatItDoes() {
        func t(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ tx: Double = 0, _ ty: Double = 0) -> Transform3D {
            var t = Transform3D.identity
            t.m11 = a
            t.m12 = b
            t.m21 = c
            t.m22 = d
            t.m41 = tx
            t.m42 = ty
            return t
        }
        let angle = -4 * Double.pi / 180
        XCTAssertEqual(AttributeText.summary(of: .identity), "Identity")
        XCTAssertEqual(
            AttributeText.summary(of: t(cos(angle) * 1.02, sin(angle) * 1.02, -sin(angle) * 1.02, cos(angle) * 1.02)),
            "Rotate -4° · Scale 1.02")
        XCTAssertEqual(AttributeText.summary(of: t(1.02, 0, 0, 0.9)), "Scale 1.02 × 0.9")
        XCTAssertEqual(AttributeText.summary(of: t(1, 0, 0, 1, 10, -4)), "Move 10, -4")
        XCTAssertEqual(AttributeText.summary(of: t(1, 0, 0.5, 1)), "Custom", "shear")
        var threeD = Transform3D.identity
        threeD.m34 = -1 / 500
        XCTAssertEqual(AttributeText.summary(of: threeD), "Custom", "perspective")
    }
}
