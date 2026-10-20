import CutawayTestSupport
import FlatBuffers
import XCTest

@testable import CutawayWire

/// C-WIRE-11: the fields of protocol 1.1 a server may leave out — class origins, base classes, view controller
/// visibility, clusters, inactive causes, units, system color names, the groups' classes,
/// guide kinds and constraint origins. The expected values come from
/// Protocol/fixtures/README.md and Protocol/fixtures/src.
final class Protocol11OptionalFieldsDecodingTests: XCTestCase {
    private struct UnexpectedBody: Error {}

    private func decode(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    private func hierarchy(_ scenario: String) throws -> Hierarchy {
        guard case .hierarchy(let hierarchy) = try decode(scenario, "02-s2c-hierarchy.bin").body
        else { throw UnexpectedBody() }
        return hierarchy
    }

    private func details(_ scenario: String) throws -> [LayerDetail] {
        guard case .layerDetailsChunk(let chunk) = try decode(scenario, "02-s2c-chunk-0.bin").body
        else { throw UnexpectedBody() }
        return chunk.details
    }

    private func attributes(_ detail: LayerDetail) -> [String: Attribute] {
        Dictionary(uniqueKeysWithValues: detail.attributeGroups.flatMap(\.attributes).map { ($0.id ?? "", $0) })
    }

    /// The frame encoded and decoded again.
    private func roundTrip(_ body: Body) throws -> Body? {
        try FrameCodec.decode(FrameCodec.encode(Frame(requestID: 2, body: body))).body
    }

    // MARK: - Hierarchy

    func test_C_WIRE_11_hierarchyNodesCarryOriginsBaseClassesAndVisibility() throws {
        let nodes = try hierarchy("hierarchy").nodes
        XCTAssertEqual(nodes.count, 14)
        for node in nodes {
            // A virtual node's type is the host app's (P-HIER-20, 1.2).
            XCTAssertEqual(
                node.layerClassOrigin, node.kind == .virtual ? .app : .system, "node \(node.id)")
            switch (node.viewClassName, node.id) {
            case (nil, _): XCTAssertEqual(node.viewClassOrigin, .unknown, "node \(node.id)")
            case (_, 4): XCTAssertEqual(node.viewClassOrigin, .app, "node 4 is Demo.CardView")
            case (_, 13): XCTAssertEqual(node.viewClassOrigin, .app, "node 13 is Demo.PaymentCardView")
            default: XCTAssertEqual(node.viewClassOrigin, .system, "node \(node.id)")
            }
            if node.id == 2 {
                XCTAssertEqual(node.viewControllerClassOrigin, .app)
                XCTAssertEqual(node.viewControllerVisibility, .shown)
            } else {
                XCTAssertEqual(node.viewControllerClassOrigin, .unknown, "node \(node.id)")
                XCTAssertEqual(node.viewControllerVisibility, .unknown, "node \(node.id)")
            }
        }
        let viewBases = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.viewBaseClassName) })
        XCTAssertEqual(
            viewBases,
            [1: "UIWindow", 2: nil, 3: "UILabel", 4: nil, 5: nil, 6: "UIScrollView", 7: "UILabel",
             8: nil, 9: nil, 10: nil, 11: nil, 12: nil, 13: nil, 14: "UILabel"])
        XCTAssertEqual(nodes.compactMap(\.layerBaseClassName), ["CAShapeLayer"])
        XCTAssertEqual(nodes.first { $0.layerBaseClassName != nil }?.id, 5)
    }

    func test_C_WIRE_11_aSubtreeCarriesTheSameFields() throws {
        let subtree = try hierarchy("subtree").nodes
        let whole = try hierarchy("hierarchy").nodes
        XCTAssertEqual(subtree.map(\.id), [4, 10, 11, 12, 5])
        for node in subtree {
            XCTAssertEqual(node, try XCTUnwrap(whole.first { $0.id == node.id }), "node \(node.id)")
        }
    }

    // MARK: - Attributes

    func test_C_WIRE_11_layer3CarriesClustersUnitsCausesAndAColorName() throws {
        let detail = try details("layer-details")[0]
        XCTAssertEqual(detail.layerID, 3)
        XCTAssertEqual(detail.attributeGroups.map(\.className), ["CALayer", "UILabel", "UIView"])
        let attributes = attributes(detail)
        XCTAssertEqual(attributes.count, 22)

        let clusters = attributes.compactMapValues(\.cluster)
        XCTAssertEqual(
            clusters,
            ["layer.frame": AttributeCluster(name: "geometry", slot: "frame"),
             "layer.bounds": AttributeCluster(name: "geometry", slot: "bounds"),
             "layer.position": AttributeCluster(name: "geometry", slot: "position"),
             "layer.transform": AttributeCluster(name: "geometry", slot: "transform"),
             "layer.shadowOpacity": AttributeCluster(name: "shadow", slot: "opacity"),
             "layer.shadowOffset": AttributeCluster(name: "shadow", slot: "offset"),
             "layer.borderWidth": AttributeCluster(name: "border", slot: "width"),
             "layer.borderColor": AttributeCluster(name: "border", slot: "color"),
             "label.fontSize": AttributeCluster(name: "font", slot: "size"),
             "label.fontTextStyle": AttributeCluster(name: "font", slot: "textStyle"),
             "label.adjustsFontForContentSizeCategory": AttributeCluster(name: "font", slot: "scalable"),
             "label.numberOfLines": AttributeCluster(name: "lines", slot: "count"),
             "view.isHidden": AttributeCluster(name: "visibility", slot: "hidden"),
             "view.alpha": AttributeCluster(name: "visibility", slot: "opacity")])

        let units = attributes.mapValues(\.unit).filter { $0.value != .unspecified }
        XCTAssertEqual(
            units,
            ["layer.frame": .points, "layer.bounds": .points, "layer.position": .points,
             "layer.shadowOffset": .points, "layer.borderWidth": .points, "label.fontSize": .points,
             "view.layoutMargins": .points, "layer.shadowOpacity": .fraction, "view.alpha": .fraction])

        XCTAssertEqual(
            attributes.compactMapValues(\.inactiveCause),
            ["layer.borderColor": "layer.borderWidth", "layer.shadowOffset": "layer.shadowOpacity"])
        XCTAssertEqual(attributes.compactMapValues(\.systemColorName), ["view.tintColor": "systemBlue"])
        XCTAssertNil(attributes["layer.borderColor"]?.systemColorName, "a CGColor has no name")

        let sections = attributes.mapValues(\.section)
        XCTAssertEqual(sections["label.text"], .content)
        XCTAssertEqual(sections["view.backgroundColor"], .appearance)
        XCTAssertEqual(sections["view.isUserInteractionEnabled"], .behavior)
        XCTAssertEqual(sections["view.tag"], .identity)
        XCTAssertEqual(sections["layer.frame"], .layout)
        XCTAssertFalse(sections.values.contains(.general), "no fixture uses General")
    }

    func test_C_WIRE_11_aLayerThatBacksNoViewHasTheLayersAttributes() throws {
        let details = try details("layer-details-edge")
        let layer8 = try XCTUnwrap(details.first { $0.layerID == 8 })
        XCTAssertEqual(layer8.attributeGroups.map(\.className), ["CALayer"])
        let layer8Attributes = attributes(layer8)
        XCTAssertEqual(
            layer8Attributes.compactMapValues(\.cluster),
            ["layer.hidden": AttributeCluster(name: "visibility", slot: "hidden"),
             "layer.opacity": AttributeCluster(name: "visibility", slot: "opacity")])
        XCTAssertEqual(layer8Attributes["layer.opacity"]?.unit, .fraction)

        let layer9 = try XCTUnwrap(details.first { $0.layerID == 9 })
        XCTAssertEqual(
            attributes(layer9).compactMapValues(\.cluster),
            ["layer.frame": AttributeCluster(name: "geometry", slot: "frame"),
             "view.isHidden": AttributeCluster(name: "visibility", slot: "hidden")])
    }

    func test_C_WIRE_11_aClusterSpansTwoGroups() throws {
        let results = try Fixtures.setAttributeResults()
        let layer4 = try XCTUnwrap(results.first { $0.layerID == 4 })
        var corners: [String: String] = [:]
        for group in layer4.attributeGroups {
            for attribute in group.attributes where attribute.cluster?.name == "corners" {
                corners[attribute.cluster?.slot ?? ""] = group.id
            }
        }
        XCTAssertEqual(corners, ["radius": "layer", "clip": "view"])
        let ids = layer4.attributeGroups.flatMap(\.attributes).compactMap(\.id)
        XCTAssertFalse(ids.contains("layer.opacity"), "layer 4 backs a view (P-ATTR-11)")
    }

    // MARK: - Constraints

    func test_C_WIRE_11_constraintsCarryOriginsAndTheGuideItsKind() throws {
        let details = try details("layout-constraints")
        var origins: [UInt64: ClassOrigin] = [:]
        var guides: [LayoutGuide] = []
        for constraint in details.flatMap(\.constraints) {
            origins[constraint.id] = constraint.origin
            for case .layoutGuide(let guide)? in [constraint.firstItem, constraint.secondItem] {
                guides.append(guide)
            }
        }
        XCTAssertEqual(origins.count, 11)
        for id in 1...11 {
            XCTAssertEqual(origins[UInt64(id)], id <= 7 ? .app : .system, "constraint \(id)")
        }
        XCTAssertFalse(guides.isEmpty)
        XCTAssertTrue(guides.allSatisfy { $0.kind == .safeArea })
    }

    // MARK: - Without the optional fields

    func test_C_WIRE_11_framesWithoutTheNewFieldsReadAsUnknown() throws {
        let old = Fixtures.withoutTheOptionalFields(try hierarchy("hierarchy"))
        XCTAssertEqual(try roundTrip(.hierarchy(old)), .hierarchy(old))
        for node in old.nodes {
            XCTAssertEqual(node.layerClassOrigin, .unknown)
            XCTAssertEqual(node.viewClassOrigin, .unknown)
            XCTAssertEqual(node.viewControllerClassOrigin, .unknown)
            XCTAssertNil(node.layerBaseClassName)
            XCTAssertNil(node.viewBaseClassName)
            XCTAssertEqual(node.viewControllerVisibility, .unknown)
            // A virtual node has none (P-HIER-14).
            XCTAssertTrue(node.layerAddress != nil || node.kind == .virtual, "what is required stays")
        }

        var details = try details("layer-details")
        details += try self.details("layout-constraints")
        let stripped = details.map { detail in
            var detail = detail
            detail.attributeGroups = Fixtures.withoutTheOptionalFields(detail.attributeGroups)
            detail.constraints = Fixtures.withoutTheOptionalFields(detail.constraints)
            return detail
        }
        let body = Body.layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: stripped))
        guard case .layerDetailsChunk(let chunk) = try roundTrip(body) else {
            XCTFail("not a chunk")
            return
        }
        XCTAssertEqual(chunk.details, stripped)
        let groups = chunk.details.flatMap(\.attributeGroups)
        XCTAssertTrue(groups.allSatisfy { $0.className == nil })
        let attributes = groups.flatMap(\.attributes)
        XCTAssertTrue(attributes.allSatisfy {
            $0.cluster == nil && $0.inactiveCause == nil && $0.unit == .unspecified
                && $0.systemColorName == nil
        })
        XCTAssertTrue(attributes.contains { $0.limits != nil }, "what is required stays")
        let constraints = chunk.details.flatMap(\.constraints)
        XCTAssertFalse(constraints.isEmpty)
        XCTAssertTrue(constraints.allSatisfy { $0.origin == .unknown })
        for constraint in constraints {
            for case .layoutGuide(let guide)? in [constraint.firstItem, constraint.secondItem] {
                XCTAssertEqual(guide.kind, .unknown)
            }
        }
    }

    func test_C_WIRE_11_theNewFieldsAreWrittenAsTheyWereRead() throws {
        let hierarchy = try hierarchy("hierarchy")
        XCTAssertEqual(try roundTrip(.hierarchy(hierarchy)), .hierarchy(hierarchy))
        let details = try details("layer-details") + self.details("layout-constraints")
        let body = Body.layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: details))
        XCTAssertEqual(try roundTrip(body), body)
    }

    // MARK: - Values this client does not know, and fields that break the rules

    /// A layer node as a server writes it, with raw values in the given vtable slots.
    private func node(raw: [(slot: Int, value: UInt8)],
                      strings: [(slot: Int, value: String)] = []) throws -> LayerNode
    {
        var builder = FlatBufferBuilder()
        let offsets = strings.map { (slot: $0.slot, offset: builder.create(string: $0.value)) }
        let start = Cutaway_Wire_LayerNode.startLayerNode(&builder)
        Cutaway_Wire_LayerNode.add(id: 3, &builder)
        for (slot, value) in raw {
            builder.add(element: value, def: UInt8(0), at: VOffset(slot))
        }
        for (slot, offset) in offsets {
            builder.add(offset: offset, at: VOffset(slot))
        }
        let end = Cutaway_Wire_LayerNode.endLayerNode(&builder, start: start)
        builder.finish(offset: end, fileId: "CTWY")
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_LayerNode = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        return LayerNode(wire)
    }

    func test_C_WIRE_11_enumValuesThisClientDoesNotKnowReadAsUnknown() throws {
        // LayerNode: layer_class_origin 44, view_class_origin 46, view_controller_class_origin
        // 48, view_controller_visibility 54.
        let unknown = try node(raw: [(44, 9), (46, 9), (48, 9), (54, 9)])
        XCTAssertEqual(unknown.layerClassOrigin, .unknown)
        XCTAssertEqual(unknown.viewClassOrigin, .unknown)
        XCTAssertEqual(unknown.viewControllerClassOrigin, .unknown)
        XCTAssertEqual(unknown.viewControllerVisibility, .unknown)
        let known = try node(raw: [(44, 1), (46, 2), (54, 2)])
        XCTAssertEqual(known.layerClassOrigin, .system)
        XCTAssertEqual(known.viewClassOrigin, .app)
        XCTAssertEqual(known.viewControllerVisibility, .notShown)

        // Attribute: section 18, unit 28.
        for (raw,
             section) in [(UInt8(4), AttributeSection.content), (5, .appearance), (6, .behavior), (9, .unspecified)]
        {
            XCTAssertEqual(try attribute(raw: [(18, raw)]).section, section, "section \(raw)")
        }
        // A unit counts only for a number, so the kind is a double (value_kind 16).
        for (raw, unit) in [(UInt8(1), AttributeUnit.points), (2, .fraction), (9, .unspecified)] {
            XCTAssertEqual(try attribute(raw: [(16, 3), (28, raw)]).unit, unit, "unit \(raw)")
        }

        // LayoutItem: guide_kind 18. LayoutConstraint: origin 28.
        for (raw, kind) in [(UInt8(1), LayoutGuideKind.other), (2, .safeArea), (3, .layoutMargins),
                            (4, .readableContent), (5, .keyboard), (9, .unknown)]
        {
            XCTAssertEqual(try guide(rawKind: raw).kind, kind, "guide kind \(raw)")
        }
        for (raw, origin) in [(UInt8(1), ClassOrigin.system), (2, .app), (9, .unknown)] {
            var builder = FlatBufferBuilder()
            let start = Cutaway_Wire_LayoutConstraint.startLayoutConstraint(&builder)
            Cutaway_Wire_LayoutConstraint.add(id: 1, &builder)
            builder.add(element: raw, def: UInt8(0), at: VOffset(28))
            let end = Cutaway_Wire_LayoutConstraint.endLayoutConstraint(&builder, start: start)
            builder.finish(offset: end, fileId: "CTWY")
            var buffer = builder.sizedBuffer
            let wire: Cutaway_Wire_LayoutConstraint = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
            XCTAssertEqual(LayoutConstraint(wire).origin, origin, "constraint origin \(raw)")
        }
    }

    /// P-ATTR-14: only the kinds of numbers that can be lengths or proportions have a unit;
    /// any other kind reads as `Unspecified`, as limits on a kind without them read as none.
    func test_C_WIRE_11_aUnitOnACaseWithoutNumbersReadsAsUnspecified() throws {
        // value_kind 16, unit 28 (Points).
        let kept: [(UInt8, String)] = [
            (2, "an integer"), (3, "a double"), (6, "a point"), (7, "a size"), (8, "a rect"),
            (9, "insets"),
        ]
        for (kind, name) in kept {
            XCTAssertEqual(try attribute(raw: [(16, kind), (28, 1)]).unit, .points, name)
        }
        let dropped: [(UInt8, String)] = [
            (0, "no kind"), (1, "a bool"), (4, "a string"), (5, "a colour"), (10, "a transform"),
            (11, "an enum"),
        ]
        for (kind, name) in dropped {
            XCTAssertEqual(try attribute(raw: [(16, kind), (28, 1)]).unit, .unspecified, name)
        }
    }

    private func attribute(
        raw: [(slot: Int, value: UInt8)] = [], cluster: String? = nil, slot: String? = nil,
        inactiveCause: String? = nil, systemName: String? = nil
    ) throws -> Attribute {
        var builder = FlatBufferBuilder()
        let clusterOffset = cluster.map { builder.create(string: $0) } ?? Offset()
        let slotOffset = slot.map { builder.create(string: $0) } ?? Offset()
        let causeOffset = inactiveCause.map { builder.create(string: $0) } ?? Offset()
        let nameOffset = systemName.map { builder.create(string: $0) } ?? Offset()
        let color = Cutaway_Wire_ColorValue.createColorValue(
            &builder, value: Cutaway_Wire_Color(red: 0, green: 0.47843137, blue: 1, alpha: 1),
            systemNameOffset: nameOffset)
        let start = Cutaway_Wire_Attribute.startAttribute(&builder)
        Cutaway_Wire_Attribute.add(valueType: .colorvalue, &builder)
        Cutaway_Wire_Attribute.add(value: color, &builder)
        Cutaway_Wire_Attribute.add(cluster: clusterOffset, &builder)
        Cutaway_Wire_Attribute.add(slot: slotOffset, &builder)
        Cutaway_Wire_Attribute.add(inactiveCause: causeOffset, &builder)
        for (slot, value) in raw {
            builder.add(element: value, def: UInt8(0), at: VOffset(slot))
        }
        let end = Cutaway_Wire_Attribute.endAttribute(&builder, start: start)
        builder.finish(offset: end, fileId: "CTWY")
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_Attribute = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        return Attribute(wire)
    }

    private func guide(rawKind: UInt8) throws -> LayoutGuide {
        var builder = FlatBufferBuilder()
        let start = Cutaway_Wire_LayoutItem.startLayoutItem(&builder)
        Cutaway_Wire_LayoutItem.add(kind: .layoutguide, &builder)
        Cutaway_Wire_LayoutItem.add(guideId: 7, &builder)
        builder.add(element: rawKind, def: UInt8(0), at: VOffset(18))
        let end = Cutaway_Wire_LayoutItem.endLayoutItem(&builder, start: start)
        builder.finish(offset: end, fileId: "CTWY")
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_LayoutItem = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        guard case .layoutGuide(let guide) = LayoutItem(wire) else { throw UnexpectedBody() }
        return guide
    }

    func test_C_WIRE_11_aClusterWithoutItsSlotReadsAsNone() throws {
        XCTAssertEqual(
            try attribute(cluster: "border", slot: "width").cluster,
            AttributeCluster(name: "border", slot: "width"))
        XCTAssertNil(try attribute(cluster: "border").cluster, "no slot")
        XCTAssertNil(try attribute(slot: "width").cluster, "no cluster")
        XCTAssertNil(try attribute(cluster: "", slot: "width").cluster, "an empty cluster")
        XCTAssertNil(try attribute(cluster: "border", slot: "").cluster, "an empty slot")
    }

    func test_C_WIRE_11_emptyStringsReadAsAbsent() throws {
        XCTAssertEqual(try attribute(inactiveCause: "layer.borderWidth").inactiveCause, "layer.borderWidth")
        XCTAssertNil(try attribute(inactiveCause: "").inactiveCause)
        XCTAssertEqual(try attribute(systemName: "systemBlue").systemColorName, "systemBlue")
        XCTAssertNil(try attribute(systemName: "").systemColorName)
        XCTAssertNil(try attribute().systemColorName)

        // LayerNode: layer_base_class_name 50, view_base_class_name 52.
        let empty = try node(raw: [], strings: [(50, ""), (52, "")])
        XCTAssertNil(empty.layerBaseClassName)
        XCTAssertNil(empty.viewBaseClassName)
        let given = try node(raw: [], strings: [(50, "CATextLayer"), (52, "SomeFutureView")])
        XCTAssertEqual(given.layerBaseClassName, "CATextLayer")
        XCTAssertEqual(given.viewBaseClassName, "SomeFutureView", "the reader ignores names it does not know")

        var builder = FlatBufferBuilder()
        let className = builder.create(string: "")
        let end = Cutaway_Wire_AttributeGroup.createAttributeGroup(&builder, classNameOffset: className)
        builder.finish(offset: end, fileId: "CTWY")
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_AttributeGroup = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        XCTAssertNil(AttributeGroup(wire).className)
    }

    func test_C_WIRE_11_aColorNameIsReadOnlyFromAColor() throws {
        // A system_name on a value that is not a ColorValue cannot be written: it is a field of
        // ColorValue. The name is not part of the color itself.
        let attribute = try attribute(systemName: "systemBlue")
        guard case .color(let color) = attribute.value else {
            XCTFail("not a color")
            return
        }
        XCTAssertEqual(color, Color(red: 0, green: 0.47843137, blue: 1, alpha: 1))
    }
}
