import CutawayTestSupport
import FlatBuffers
import XCTest

@testable import CutawayWire

/// C-WIRE-10: what protocol 1.1 adds — addresses, sections and limits. The expected values come
/// from Protocol/fixtures/README.md and Protocol/fixtures/src.
final class Protocol11DecodingTests: XCTestCase {
    private struct UnexpectedBody: Error {}

    private func decode(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    private func nodes(_ scenario: String) throws -> [LayerNode] {
        guard case .hierarchy(let hierarchy) = try decode(scenario, "02-s2c-hierarchy.bin").body
        else { throw UnexpectedBody() }
        return hierarchy.nodes
    }

    private func layer3() throws -> [Attribute] {
        guard case .layerDetailsChunk(let chunk) = try decode("layer-details", "02-s2c-chunk-0.bin").body
        else { throw UnexpectedBody() }
        return chunk.details[0].attributeGroups.flatMap(\.attributes)
    }

    // MARK: - Addresses

    func test_C_WIRE_10_hierarchyNodesCarryTheirAddresses() throws {
        let nodes = try nodes("hierarchy")
        XCTAssertEqual(nodes.count, 9)
        for node in nodes {
            XCTAssertEqual(node.layerAddress, 0x6000_03B4_C000 + 0x40 * (node.id - 1), "node \(node.id)")
            if node.viewClassName == nil {
                XCTAssertNil(node.viewAddress, "node \(node.id) backs no view")
            } else {
                XCTAssertEqual(node.viewAddress, 0x1_0380_6800 + 0x200 * node.id, "node \(node.id)")
            }
            XCTAssertEqual(
                node.viewControllerAddress, node.id == 2 ? 0x1_0300_7A00 : nil, "node \(node.id)")
        }
        XCTAssertEqual(nodes.filter { $0.viewAddress == nil }.map(\.id), [5, 8])
    }

    func test_C_WIRE_10_aSubtreeCarriesTheSameAddresses() throws {
        let subtree = try nodes("subtree")
        let whole = try nodes("hierarchy")
        XCTAssertEqual(subtree.map(\.id), [4, 5])
        for node in subtree {
            let same = try XCTUnwrap(whole.first { $0.id == node.id })
            XCTAssertEqual(node.layerAddress, same.layerAddress)
            XCTAssertEqual(node.viewAddress, same.viewAddress)
            XCTAssertEqual(node.viewControllerAddress, same.viewControllerAddress)
        }
    }

    // MARK: - Sections and limits

    func test_C_WIRE_10_layerDetailsCarrySectionsAndLimits() throws {
        let attributes = try layer3()
        let sections = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id ?? "", $0.section) })
        XCTAssertEqual(sections["view.tag"], .identity)
        for id in ["layer.frame", "layer.bounds", "layer.position", "layer.transform", "view.layoutMargins"] {
            XCTAssertEqual(sections[id], .layout, id)
        }
        // The rest are in Content, Appearance or Behavior (C-WIRE-11), or Accessibility
        // (C-WIRE-12); none is General.
        XCTAssertEqual(
            Set(sections.filter { $0.value != .identity && $0.value != .layout }.keys),
            ["layer.shadowOpacity", "layer.shadowOffset", "layer.borderWidth",
             "layer.borderColor", "label.text", "label.fontSize", "label.fontTextStyle",
             "label.adjustsFontForContentSizeCategory", "label.numberOfLines",
             "label.textAlignment", "view.isHidden", "view.alpha", "view.backgroundColor",
             "view.tintColor", "view.isUserInteractionEnabled", "view.accessibilityLabel"])

        let limits = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id ?? "", $0.limits) })
        let atLeastZero = NumberLimit(minimum: 0)
        XCTAssertEqual(limits["layer.bounds"], [NumberLimit(), NumberLimit(), atLeastZero, atLeastZero])
        XCTAssertEqual(limits["view.alpha"], [NumberLimit(minimum: 0, maximum: 1)])
        XCTAssertEqual(limits["layer.shadowOpacity"], [NumberLimit(minimum: 0, maximum: 1)])
        XCTAssertEqual(limits["layer.borderWidth"], [atLeastZero])
        XCTAssertEqual(limits["label.numberOfLines"], [atLeastZero])
        XCTAssertEqual(limits["label.fontSize"], [NumberLimit(minimum: 0, minimumIsExclusive: true)])
        XCTAssertEqual(
            Set(limits.filter { $0.value != nil }.keys),
            ["layer.bounds", "view.alpha", "layer.shadowOpacity", "layer.borderWidth",
             "label.numberOfLines", "label.fontSize"],
            "no other attribute has limits")
    }

    func test_C_WIRE_10_setAttributeResultsCarrySectionsAndLimits() throws {
        let results = try Fixtures.setAttributeResults()
        let layer4 = try XCTUnwrap(results.first { $0.layerID == 4 })
        let attributes = layer4.attributeGroups.flatMap(\.attributes)
        XCTAssertTrue(attributes.allSatisfy { $0.section == .appearance })
        XCTAssertEqual(
            attributes.first { $0.id == "layer.cornerRadius" }?.limits, [NumberLimit(minimum: 0)])
        XCTAssertEqual(
            attributes.first { $0.id == "view.alpha" }?.limits, [NumberLimit(minimum: 0, maximum: 1)])
    }

    // MARK: - Without what 1.1 appended

    func test_C_WIRE_10_framesWithoutTheNewFieldsReadAsAbsent() throws {
        guard case .hierarchy(let hierarchy) = try decode("hierarchy", "02-s2c-hierarchy.bin").body
        else {
            XCTFail("not a Hierarchy")
            return
        }
        let old = Fixtures.withoutProtocol11(hierarchy)
        let readOld = try FrameCodec.decode(FrameCodec.encode(Frame(requestID: 2, body: .hierarchy(old))))
        XCTAssertEqual(readOld.body, .hierarchy(old))
        for node in old.nodes {
            XCTAssertNil(node.layerAddress)
            XCTAssertNil(node.viewAddress)
            XCTAssertNil(node.viewControllerAddress)
        }

        let groups = Fixtures.withoutProtocol11([AttributeGroup(id: "g", title: "G", attributes: try layer3())])
        let detail = LayerDetail(
            layerID: 3, status: .ok, solo: nil, group: nil, attributeGroups: groups)
        let frame = Frame(requestID: 3, body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: [detail])))
        guard case .layerDetailsChunk(let chunk) = try FrameCodec.decode(FrameCodec.encode(frame)).body
        else {
            XCTFail("not a chunk")
            return
        }
        let attributes = chunk.details[0].attributeGroups.flatMap(\.attributes)
        XCTAssertEqual(attributes.count, 22)
        XCTAssertTrue(attributes.allSatisfy { $0.section == .unspecified && $0.limits == nil })
    }

    func test_C_WIRE_10_zeroAddressesReadAsAbsent() throws {
        var builder = FlatBufferBuilder()
        let start = Cutaway_Wire_LayerNode.startLayerNode(&builder)
        Cutaway_Wire_LayerNode.add(id: 3, &builder)
        Cutaway_Wire_LayerNode.add(layerAddress: 0, &builder)
        Cutaway_Wire_LayerNode.add(viewAddress: 0, &builder)
        Cutaway_Wire_LayerNode.add(viewControllerAddress: 0, &builder)
        let end = Cutaway_Wire_LayerNode.endLayerNode(&builder, start: start)
        builder.finish(offset: end, fileId: "CTWY")
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_LayerNode = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        let node = LayerNode(wire)
        XCTAssertNil(node.layerAddress)
        XCTAssertNil(node.viewAddress)
        XCTAssertNil(node.viewControllerAddress)
    }

    func test_C_WIRE_10_aSectionThisClientDoesNotKnowReadsAsUnspecified() throws {
        var builder = FlatBufferBuilder()
        let id = builder.create(string: "x.y")
        let start = Cutaway_Wire_Attribute.startAttribute(&builder)
        Cutaway_Wire_Attribute.add(id: id, &builder)
        // `section` is the attribute's eighth field: its vtable slot is 4 + 2 × 7.
        builder.add(element: UInt8(9), def: UInt8(0), at: VOffset(4 + 2 * 7))
        let end = Cutaway_Wire_Attribute.endAttribute(&builder, start: start)
        builder.finish(offset: end, fileId: "CTWY")
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_Attribute = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        XCTAssertEqual(Attribute(wire).section, .unspecified)

        for (raw, section) in [(UInt8(1), AttributeSection.identity), (2, .general), (3, .layout)] {
            var builder = FlatBufferBuilder()
            let start = Cutaway_Wire_Attribute.startAttribute(&builder)
            builder.add(element: raw, def: UInt8(0), at: VOffset(4 + 2 * 7))
            let end = Cutaway_Wire_Attribute.endAttribute(&builder, start: start)
            builder.finish(offset: end, fileId: "CTWY")
            var buffer = builder.sizedBuffer
            let wire: Cutaway_Wire_Attribute = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
            XCTAssertEqual(Attribute(wire).section, section, "raw value \(raw)")
        }
    }

    // MARK: - Limits that break the rules

    private struct RawLimit {
        var minimum = 0.0, hasMinimum = false, minimumExclusive = false
        var maximum = 0.0, hasMaximum = false, maximumExclusive = false
    }

    /// An attribute as a server writes it, with these limits and no value.
    private func attribute(
        _ kind: Cutaway_Wire_AttributeValueKind, editable: Bool = true, limits: [RawLimit]
    ) throws -> Attribute {
        var builder = FlatBufferBuilder()
        let offsets = limits.map {
            Cutaway_Wire_NumberLimit.createNumberLimit(
                &builder, minimum: $0.minimum, hasMinimum: $0.hasMinimum,
                minimumExclusive: $0.minimumExclusive, maximum: $0.maximum,
                hasMaximum: $0.hasMaximum, maximumExclusive: $0.maximumExclusive)
        }
        let vector = builder.createVector(ofOffsets: offsets)
        let end = Cutaway_Wire_Attribute.createAttribute(
            &builder, editable: editable, valueKind: kind, limitsVectorOffset: vector)
        builder.finish(offset: end, fileId: "CTWY")
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_Attribute = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        return Attribute(wire)
    }

    private static let zeroToOne = RawLimit(hasMinimum: true, maximum: 1, hasMaximum: true)

    func test_C_WIRE_10_validLimitsAreKept() throws {
        XCTAssertEqual(
            try attribute(.doublevalue, limits: [Self.zeroToOne]).limits,
            [NumberLimit(minimum: 0, maximum: 1)])
        // One entry per component, or one for all of them.
        let free = RawLimit()
        let positive = RawLimit(hasMinimum: true, minimumExclusive: true)
        XCTAssertEqual(
            try attribute(.rectvalue, limits: [free, free, positive, positive]).limits,
            [NumberLimit(), NumberLimit(),
             NumberLimit(minimum: 0, minimumIsExclusive: true),
             NumberLimit(minimum: 0, minimumIsExclusive: true)])
        XCTAssertEqual(
            try attribute(.transformvalue, limits: [Self.zeroToOne]).limits?.count, 1)
        // A point where both bounds meet, inclusive.
        XCTAssertEqual(
            try attribute(.doublevalue, limits: [RawLimit(
                minimum: 2, hasMinimum: true, maximum: 2, hasMaximum: true)]).limits,
            [NumberLimit(minimum: 2, maximum: 2)])
        // An integer range with a whole number inside: (0, 2).
        XCTAssertEqual(
            try attribute(.intvalue, limits: [RawLimit(
                hasMinimum: true, minimumExclusive: true, maximum: 2, hasMaximum: true,
                maximumExclusive: true)]).limits?.count, 1)
        // The fields of a side that is not there are ignored.
        XCTAssertEqual(
            try attribute(.doublevalue, limits: [RawLimit(
                minimum: 5, minimumExclusive: true, maximum: 1, hasMaximum: true)]).limits,
            [NumberLimit(maximum: 1)])
    }

    func test_C_WIRE_10_limitsThatBreakTheRulesReadAsNone() throws {
        let cases: [(String, Cutaway_Wire_AttributeValueKind, Bool, [RawLimit])] = [
            ("empty", .doublevalue, true, []),
            ("not editable", .doublevalue, false, [Self.zeroToOne]),
            ("a colour", .colorvalue, true, [Self.zeroToOne]),
            ("a bool", .boolvalue, true, [Self.zeroToOne]),
            ("no kind", .none_, true, [Self.zeroToOne]),
            ("three entries for a rect", .rectvalue, true, [RawLimit(), RawLimit(), RawLimit()]),
            ("two entries for a number", .doublevalue, true, [RawLimit(), RawLimit()]),
            ("not finite", .doublevalue, true, [RawLimit(minimum: .infinity, hasMinimum: true)]),
            ("not a number", .doublevalue, true, [RawLimit(maximum: .nan, hasMaximum: true)]),
            ("minimum above maximum", .doublevalue, true,
             [RawLimit(minimum: 2, hasMinimum: true, maximum: 1, hasMaximum: true)]),
            ("nothing between", .doublevalue, true,
             [RawLimit(minimum: 1, hasMinimum: true, minimumExclusive: true, maximum: 1, hasMaximum: true)]),
            ("a fraction for an integer", .intvalue, true, [RawLimit(minimum: 0.5, hasMinimum: true)]),
            ("no whole number between", .intvalue, true,
             [RawLimit(hasMinimum: true, minimumExclusive: true, maximum: 1, hasMaximum: true,
                       maximumExclusive: true)]),
            ("one bad entry among good ones", .sizevalue, true,
             [Self.zeroToOne, RawLimit(minimum: .infinity, hasMinimum: true)]),
        ]
        for (name, kind, editable, limits) in cases {
            XCTAssertNil(try attribute(kind, editable: editable, limits: limits).limits, name)
        }
    }
}
