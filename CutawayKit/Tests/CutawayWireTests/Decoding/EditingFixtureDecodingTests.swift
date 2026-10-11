import CutawayTestSupport
import FlatBuffers
import XCTest

@testable import CutawayWire

/// C-WIRE-05: what protocol 0.3 adds. The expected values come from Protocol/fixtures/README.md
/// and Protocol/fixtures/src.
final class EditingFixtureDecodingTests: XCTestCase {
    private func decode(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    private static let blue = Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)

    func test_C_WIRE_05_setAttribute() throws {
        let requests: [(String, Frame)] = [
            ("01-c2s-set-text.bin", Frame(requestID: 1, body: .setAttribute(SetAttribute(
                layerID: 3, attributeID: "label.text", value: .string("Welcome back"))))),
            // Only `value` is sent for an enum (P-SET-02).
            ("03-c2s-set-alignment.bin", Frame(requestID: 2, body: .setAttribute(SetAttribute(
                layerID: 3, attributeID: "label.textAlignment",
                value: .enumeration(EnumValue(value: 2, cases: [], caseName: nil)))))),
            ("05-c2s-set-background.bin", Frame(requestID: 3, body: .setAttribute(SetAttribute(
                layerID: 4, attributeID: "layer.backgroundColor", value: .color(Self.blue))))),
            ("07-c2s-set-alpha.bin", Frame(requestID: 4, body: .setAttribute(SetAttribute(
                layerID: 4, attributeID: "view.alpha", value: .double(0.5))))),
            // No value sets nil.
            ("09-c2s-clear-background.bin", Frame(requestID: 5, body: .setAttribute(SetAttribute(
                layerID: 4, attributeID: "layer.backgroundColor", value: nil)))),
        ]
        for (file, expected) in requests {
            XCTAssertEqual(try decode("set-attribute", file), expected, file)
        }

        let results: [(String, UInt32, UInt64, [AttributeGroup])] = [
            ("02-s2c-result.bin", 1, 3, ExpectedAttributes.layer3(text: "Welcome back")),
            ("04-s2c-result.bin", 2, 3, ExpectedAttributes.layer3(
                text: "Welcome back", alignment: 2, alignmentName: "right")),
            ("06-s2c-result.bin", 3, 4, ExpectedAttributes.layer4(opacity: 1, background: Self.blue)),
            // view.alpha took layer.opacity with it.
            ("08-s2c-result.bin", 4, 4, ExpectedAttributes.layer4(opacity: 0.5, background: Self.blue)),
            // Back to nil; the kind is still given.
            ("10-s2c-result.bin", 5, 4, ExpectedAttributes.layer4(opacity: 0.5, background: nil)),
        ]
        for (file, requestID, layerID, groups) in results {
            XCTAssertEqual(
                try decode("set-attribute", file),
                Frame(requestID: requestID, body: .setAttributeResult(SetAttributeResult(
                    layerID: layerID, attributeGroups: groups))),
                file)
        }
    }

    func test_C_WIRE_05_setAttributeRejected() throws {
        let requests: [(String, SetAttribute)] = [
            ("01-c2s-set-missing-layer.bin", SetAttribute(
                layerID: 99, attributeID: "label.text", value: .string("Hi"))),
            ("03-c2s-set-read-only.bin", SetAttribute(
                layerID: 3, attributeID: "layer.frame",
                value: .rect(Rect(origin: Point(x: 0, y: 0), size: Size(width: 100, height: 24))))),
            ("05-c2s-set-wrong-kind.bin", SetAttribute(
                layerID: 3, attributeID: "layer.opacity", value: .string("half"))),
            ("07-c2s-set-nil.bin", SetAttribute(
                layerID: 3, attributeID: "label.numberOfLines", value: nil)),
        ]
        let errors: [(String, ServerError)] = [
            ("02-s2c-error.bin", ServerError(code: .layerNotFound, message: "no layer with id 99")),
            ("04-s2c-error.bin", ServerError(
                code: .attributeNotEditable, message: "layer.frame is read-only")),
            ("06-s2c-error.bin", ServerError(
                code: .invalidAttributeValue, message: "layer.opacity takes a DoubleValue")),
            ("08-s2c-error.bin", ServerError(
                code: .invalidAttributeValue, message: "label.numberOfLines cannot be nil")),
        ]
        for (index, (file, request)) in requests.enumerated() {
            XCTAssertEqual(
                try decode("set-attribute-rejected", file),
                Frame(requestID: UInt32(index + 1), body: .setAttribute(request)), file)
        }
        for (index, (file, error)) in errors.enumerated() {
            XCTAssertEqual(
                try decode("set-attribute-rejected", file),
                Frame(requestID: UInt32(index + 1), body: .error(error)), file)
        }
    }

    func test_C_WIRE_05_subtree() throws {
        XCTAssertEqual(
            try decode("subtree", "01-c2s-get-subtree.bin"),
            Frame(requestID: 1, body: .getSubtree(GetSubtree(rootID: 4))))
        XCTAssertEqual(
            try decode("subtree", "03-c2s-get-subtree.bin"),
            Frame(requestID: 2, body: .getSubtree(GetSubtree(rootID: 99))))

        // Nodes 4 and 5, exactly as in the `hierarchy` scenario.
        guard case .hierarchy(let whole) = try decode("hierarchy", "02-s2c-hierarchy.bin").body
        else {
            XCTFail("not a Hierarchy")
            return
        }
        let answer = try decode("subtree", "02-s2c-hierarchy.bin")
        XCTAssertEqual(answer.requestID, 1)
        XCTAssertEqual(
            answer.body,
            .hierarchy(Hierarchy(
                nodes: whole.nodes.filter { [4, 5].contains($0.id) }, keyWindowID: 1)))
        guard case .hierarchy(let subtree) = answer.body else {
            XCTFail("not a Hierarchy")
            return
        }
        XCTAssertEqual(subtree.nodes.map(\.id), [4, 5])
        XCTAssertEqual(subtree.nodes[0].parentID, 2)

        XCTAssertEqual(
            try decode("subtree", "04-s2c-error.bin"),
            Frame(requestID: 2, body: .error(ServerError(
                code: .layerNotFound, message: "no layer with id 99"))))
    }

    func test_C_WIRE_05_layerDetailsCarryTheFlags() throws {
        guard case .layerDetailsChunk(let chunk) =
            try decode("layer-details", "02-s2c-chunk-0.bin").body
        else {
            XCTFail("not a chunk")
            return
        }
        let attributes = chunk.details[0].attributeGroups.flatMap(\.attributes)
        XCTAssertEqual(attributes.count, 12)

        XCTAssertEqual(attributes.filter { !$0.editable }.map(\.id), ["layer.frame"])
        XCTAssertEqual(
            attributes.filter(\.acceptsNil).map(\.id),
            ["layer.backgroundColor", "layer.borderColor", "label.text"])
        let background = try XCTUnwrap(attributes.first { $0.id == "layer.backgroundColor" })
        XCTAssertNil(background.value)
        XCTAssertEqual(background.valueKind, .color)
        for attribute in attributes {
            if let value = attribute.value {
                XCTAssertEqual(attribute.valueKind, value.kind, attribute.id ?? "")
            }
        }
        let alignment = try XCTUnwrap(attributes.first { $0.id == "label.textAlignment" })
        guard case .enumeration(let value) = alignment.value else {
            XCTFail("not an enum")
            return
        }
        XCTAssertEqual(value.caseValues, [0, 1, 2, 3, 4])
        XCTAssertEqual(value.caseValues.count, value.cases.count)
    }

    /// What a 0.2 server sends: an attribute table without the three flags and an enum
    /// without `case_values`. Built field by field, so that those fields are truly absent
    /// rather than written with their default value.
    func test_C_WIRE_05_attributesWithoutFlagsReadAsReadOnly() throws {
        var builder = FlatBufferBuilder()
        let left = builder.create(string: "left")
        let center = builder.create(string: "center")
        let cases = builder.createVector(ofOffsets: [left, center])
        let caseName = builder.create(string: "center")
        let enumStart = Cutaway_Wire_EnumValue.startEnumValue(&builder)
        Cutaway_Wire_EnumValue.add(value: 1, &builder)
        Cutaway_Wire_EnumValue.addVectorOf(cases: cases, &builder)
        Cutaway_Wire_EnumValue.add(caseName: caseName, &builder)
        let enumValue = Cutaway_Wire_EnumValue.endEnumValue(&builder, start: enumStart)
        let id = builder.create(string: "label.textAlignment")
        let title = builder.create(string: "Text Alignment")
        let start = Cutaway_Wire_Attribute.startAttribute(&builder)
        Cutaway_Wire_Attribute.add(id: id, &builder)
        Cutaway_Wire_Attribute.add(title: title, &builder)
        Cutaway_Wire_Attribute.add(valueType: .enumvalue, &builder)
        Cutaway_Wire_Attribute.add(value: enumValue, &builder)
        let end = Cutaway_Wire_Attribute.endAttribute(&builder, start: start)
        Cutaway_Wire_Attribute.finish(&builder, end: end)

        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_Attribute = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        let read = Attribute(wire)
        XCTAssertEqual(read, Attribute(
            id: "label.textAlignment", title: "Text Alignment",
            value: .enumeration(EnumValue(value: 1, cases: ["left", "center"], caseName: "center"))))
        XCTAssertFalse(read.editable)
        XCTAssertFalse(read.acceptsNil)
        XCTAssertEqual(read.valueKind, .none)
        guard case .enumeration(let value) = read.value else {
            XCTFail("not an enum")
            return
        }
        XCTAssertEqual(value.caseValues, [])
    }

    func test_C_WIRE_05_setAttributeToNilWritesNoValue() throws {
        let frame = Frame(requestID: 7, body: .setAttribute(SetAttribute(
            layerID: 4, attributeID: "layer.backgroundColor", value: nil)))
        let encoded = FrameCodec.encode(frame)
        var buffer = ByteBuffer(data: encoded)
        let wire: Cutaway_Wire_Frame = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        let request = try XCTUnwrap(wire.body(type: Cutaway_Wire_SetAttribute.self))
        XCTAssertEqual(request.valueType, .none_)
        XCTAssertNil(request.value(type: Cutaway_Wire_ColorValue.self))
        XCTAssertEqual(try FrameCodec.decode(encoded), frame)
    }

    func test_C_WIRE_05_newMessagesRoundTrip() throws {
        let attribute = Attribute(
            id: "label.textAlignment", title: "Text Alignment",
            value: .enumeration(EnumValue(
                value: 2, cases: ["left", "center", "right"], caseName: "right",
                caseValues: [0, 1, 2])),
            editable: true, acceptsNil: false, valueKind: .enumeration)
        let nilColor = Attribute(
            id: "view.tintColor", title: "Tint Color", value: nil, editable: true,
            acceptsNil: true, valueKind: .color)
        let bodies: [Body] = [
            .setAttribute(SetAttribute(layerID: 3, attributeID: "label.text", value: .string("Hi"))),
            .setAttribute(SetAttribute(
                layerID: 3, attributeID: "layer.transform", value: .transform(.identity))),
            .setAttributeResult(SetAttributeResult(
                layerID: 3,
                attributeGroups: [AttributeGroup(id: "g", title: "G", attributes: [attribute, nilColor])])),
            .getSubtree(GetSubtree(rootID: 42)),
            .error(ServerError(code: .layerNotFound, message: nil)),
            .error(ServerError(code: .attributeNotEditable, message: "x")),
            .error(ServerError(code: .invalidAttributeValue, message: "y")),
        ]
        for body in bodies {
            let frame = Frame(requestID: 9, body: body)
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
    }

    func test_C_WIRE_05_everyValueKnowsItsKind() {
        let values: [(AttributeValue, AttributeValueKind)] = [
            (.bool(true), .bool), (.integer(1), .integer), (.double(1), .double),
            (.string(""), .string), (.color(.zero), .color), (.point(.zero), .point),
            (.size(.zero), .size), (.rect(.zero), .rect), (.insets(.zero), .insets),
            (.transform(.identity), .transform),
            (.enumeration(EnumValue(value: 0, cases: [], caseName: nil)), .enumeration),
        ]
        for (value, kind) in values {
            XCTAssertEqual(value.kind, kind)
        }
    }
}
