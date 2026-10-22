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
