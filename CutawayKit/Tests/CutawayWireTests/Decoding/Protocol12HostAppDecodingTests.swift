import CutawayTestSupport
import FlatBuffers
import XCTest

@testable import CutawayWire

/// C-WIRE-12, the part `v1.2.0-dev.2` appended: virtual nodes, nodes collapsed by default and
/// excluded from images, the `Excluded` status, the host app's groups and registered color
/// names. The expected values come from Protocol/fixtures/README.md and Protocol/fixtures/src.
final class Protocol12HostAppDecodingTests: XCTestCase {
    private struct UnexpectedBody: Error {}

    private static let brandBlue = Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)

    private func detail(_ layerID: UInt64) throws -> LayerDetail {
        try XCTUnwrap(Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == layerID })
    }

    // MARK: - Hierarchy

    func test_C_WIRE_12_virtualAndExcludedNodesDecodeAsTheFixtureSays() throws {
        let nodes = try Fixtures.hierarchy().nodes
        XCTAssertEqual(nodes.map(\.id), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        XCTAssertEqual(nodes.filter { $0.kind == .virtual }.map(\.id), [10, 11, 12])
        XCTAssertEqual(byID[10]?.name, "Total")
        XCTAssertEqual(byID[11]?.name, "New")
        XCTAssertEqual(byID[12]?.name, "Tax")
        XCTAssertEqual(byID[10]?.className, "Demo.CardRow")
        XCTAssertEqual(byID[10]?.displayClassName, "CardRow")
        XCTAssertEqual(byID[10]?.layerClassOrigin, .app)
        XCTAssertNil(byID[10]?.layerAddress)
        XCTAssertEqual(byID[11]?.parentID, 10)
        XCTAssertEqual(nodes.filter(\.isCollapsedByDefault).map(\.id), [10])
        XCTAssertEqual(nodes.filter(\.isCaptureExcluded).map(\.id), [13, 14])

        for node in nodes where node.id < 10 {
            XCTAssertEqual(node.kind, .layer, "node \(node.id)")
            XCTAssertNil(node.name, "node \(node.id)")
            XCTAssertFalse(node.isCollapsedByDefault, "node \(node.id)")
            XCTAssertFalse(node.isCaptureExcluded, "node \(node.id)")
        }
    }

    func test_C_WIRE_12_aSubtreeIncludesItsVirtualNodes() throws {
        XCTAssertEqual(try Fixtures.subtreeOfNode4().nodes.map(\.id), [4, 10, 11, 12, 5])
        guard case .hierarchy(let virtual) = try FrameCodec.decode(
            try Fixtures.data(scenario: "subtree", file: "06-s2c-hierarchy.bin")).body
        else { throw UnexpectedBody() }
        XCTAssertEqual(virtual.nodes.map(\.id), [10, 11])
        XCTAssertEqual(virtual.nodes.first?.parentID, 4)
        XCTAssertEqual(virtual.nodes.map(\.kind), [.virtual, .virtual])
    }

    // MARK: - Details

    func test_C_WIRE_12_theExcludedStatusDecodes() throws {
        let excluded = try detail(13)
        XCTAssertEqual(excluded.status, .excluded)
        XCTAssertNil(excluded.solo)
        XCTAssertNil(excluded.group)
        XCTAssertEqual(excluded.attributeGroups.flatMap(\.attributes).map(\.id), ["view.isHidden"])

        let virtual = try detail(10)
        XCTAssertEqual(virtual.status, .ok)
        XCTAssertNil(virtual.solo)
        XCTAssertNil(virtual.group)
    }

    func test_C_WIRE_12_hostAppGroupsAndRegisteredNamesDecode() throws {
        let groups = try detail(10).attributeGroups
        XCTAssertEqual(groups.map(\.id), ["app.row"])
        XCTAssertEqual(groups.map(\.isFromApp), [true])
        XCTAssertEqual(groups.first?.className, "Demo.CardRow")
        let attributes = groups.flatMap(\.attributes)
        XCTAssertEqual(attributes.map(\.id), ["app.row.title", "app.row.amount", "app.row.color"])
        XCTAssertEqual(attributes.map(\.section), [.content, .content, .appearance])
        XCTAssertTrue(attributes.allSatisfy(\.editable))
        XCTAssertEqual(attributes[1].limits, [NumberLimit(minimum: 0, maximum: nil)])
        XCTAssertEqual(attributes[2].value, .color(Self.brandBlue))
        XCTAssertEqual(attributes[2].registeredColorName, "brandBlue")
        XCTAssertNil(attributes[2].appearanceColors)

        // The server's own groups are not the app's.
        for layer: UInt64 in [3, 6, 13] {
            XCTAssertFalse(try detail(layer).attributeGroups.contains(where: \.isFromApp), "layer \(layer)")
        }
        let others = try [3, 6].flatMap { try detail($0).attributeGroups.flatMap(\.attributes) }
        XCTAssertTrue(others.allSatisfy { $0.registeredColorName == nil })
    }

    func test_C_WIRE_12_setAttributeRepliesCarryTheRegisteredNameAndTheAppsGroup() throws {
        let results = try Fixtures.setAttributeResults()
        let backgrounds = results.filter { $0.layerID == 4 }.map { result in
            result.attributeGroups.flatMap(\.attributes).first { $0.id == "view.backgroundColor" }
        }
        // Set to brandBlue's value, then view.alpha, then back to nil.
        XCTAssertEqual(backgrounds.map { $0?.registeredColorName }, ["brandBlue", "brandBlue", nil])

        let row = try XCTUnwrap(results.last { $0.layerID == 10 })
        XCTAssertEqual(row.attributeGroups.map(\.isFromApp), [true])
        XCTAssertEqual(
            row.attributeGroups.flatMap(\.attributes).first { $0.id == "app.row.title" }?.value,
            .string("Grand Total"))
    }

    func test_C_WIRE_12_editingTheAppsAttributeIsAPlainSetAttribute() throws {
        let frame = try FrameCodec.decode(
            try Fixtures.data(scenario: "set-attribute", file: "11-c2s-set-app-title.bin"))
        XCTAssertEqual(
            frame,
            Frame(requestID: 6, body: .setAttribute(SetAttribute(
                layerID: 10, attributeID: "app.row.title", value: .string("Grand Total")))))
    }

    // MARK: - Older peers and unknown values

    func test_C_WIRE_12_framesWithoutDev2FieldsReadAsBefore() throws {
        let hierarchy = Fixtures.withoutProtocol12(try Fixtures.hierarchy())
        guard case .hierarchy(let read) = try FrameCodec.decode(FrameCodec.encode(
            Frame(requestID: 2, body: .hierarchy(hierarchy)))).body
        else { throw UnexpectedBody() }
        XCTAssertEqual(read.nodes.count, 14)
        XCTAssertTrue(read.nodes.allSatisfy { $0.kind == .layer })
        XCTAssertTrue(read.nodes.allSatisfy { $0.name == nil })
        XCTAssertFalse(read.nodes.contains(where: \.isCollapsedByDefault))
        XCTAssertFalse(read.nodes.contains(where: \.isCaptureExcluded))

        let details = try Fixtures.layerDetails(scenario: "layer-details").map { detail in
            var detail = detail
            detail.attributeGroups = Fixtures.withoutProtocol12(detail.attributeGroups)
            return detail
        }
        guard case .layerDetailsChunk(let chunk) = try FrameCodec.decode(FrameCodec.encode(Frame(
            requestID: 3, body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: details))))).body
        else { throw UnexpectedBody() }
        let groups = chunk.details.flatMap(\.attributeGroups)
        XCTAssertFalse(groups.contains(where: \.isFromApp))
        XCTAssertTrue(groups.flatMap(\.attributes).allSatisfy { $0.registeredColorName == nil })
    }

    /// P-HELLO-04 keeps a peer from sending values this client does not know, but one that
    /// does anyway must not fail the decoding.
    func test_C_WIRE_12_anUnknownNodeKindReadsAsALayerAndAnEmptyNameAsNone() throws {
        func node(kind: UInt8) throws -> LayerNode {
            var builder = FlatBufferBuilder()
            let name = builder.create(string: "")
            let start = Cutaway_Wire_LayerNode.startLayerNode(&builder)
            Cutaway_Wire_LayerNode.add(id: 7, &builder)
            Cutaway_Wire_LayerNode.add(name: name, &builder)
            // `node_kind`'s vtable slot (56 in the generated code).
            builder.add(element: kind, def: UInt8(0), at: VOffset(56))
            let end = Cutaway_Wire_LayerNode.endLayerNode(&builder, start: start)
            builder.finish(offset: end, fileId: "CTWY")
            var buffer = builder.sizedBuffer
            let wire: Cutaway_Wire_LayerNode = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
            return LayerNode(wire)
        }
        // A known value first, so that the slot is shown to reach the field.
        XCTAssertEqual(try node(kind: 1).kind, .virtual)
        XCTAssertEqual(try node(kind: 9).kind, .layer)
        XCTAssertNil(try node(kind: 1).name)
    }

    func test_C_WIRE_12_dev2FieldsSurviveARoundTrip() throws {
        let hierarchy = try Fixtures.hierarchy()
        let frame = Frame(requestID: 2, body: .hierarchy(hierarchy))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)

        let details = try Fixtures.layerDetails(scenario: "layer-details")
        let chunk = Frame(requestID: 3, body: .layerDetailsChunk(LayerDetailsChunk(sequence: 1, details: details)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(chunk)), chunk)

        let root = try FrameCodec.checkedRoot(FrameCodec.encode(chunk))
        let wire = try XCTUnwrap(root.body(type: Cutaway_Wire_LayerDetailsChunk.self))
        let statuses = wire.details.map(\.status.rawValue)
        XCTAssertEqual(statuses.last, 3, "Excluded is 3 in the schema")
    }

    func test_C_WIRE_12_aColourWrittenBackCarriesNoName() throws {
        let frame = Frame(requestID: 9, body: .setAttribute(SetAttribute(
            layerID: 4, attributeID: "view.backgroundColor", value: .color(Self.brandBlue))))
        let root = try FrameCodec.checkedRoot(FrameCodec.encode(frame))
        let request = try XCTUnwrap(root.body(type: Cutaway_Wire_SetAttribute.self))
        let color = try XCTUnwrap(request.value(type: Cutaway_Wire_ColorValue.self))
        XCTAssertNil(color.name)
    }
}
