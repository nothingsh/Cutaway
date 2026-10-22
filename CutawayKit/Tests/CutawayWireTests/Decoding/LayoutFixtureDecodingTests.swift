import CutawayTestSupport
import FlatBuffers
import XCTest

@testable import CutawayWire

/// C-WIRE-06: what protocol 0.4 adds; C-WIRE-07: what protocol 0.5 adds. The expected values
/// come from Protocol/fixtures/README.md and Protocol/fixtures/src.
final class LayoutFixtureDecodingTests: XCTestCase {
    private func decode(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    private static let safeArea = LayoutGuide(
        ownerLayerID: 2, guideID: 1, className: "UILayoutGuide", displayClassName: "UILayoutGuide",
        identifier: "UIViewSafeAreaLayoutGuide",
        frame: Rect(origin: Point(x: 0, y: 59), size: Size(width: 393, height: 759)),
        kind: .safeArea)

    /// A constraint as the fixture writes it: multiplier 1, priority 1000, satisfied; the
    /// app's when it is an `NSLayoutConstraint`, UIKit's otherwise (P-LAYOUT-09).
    private static func constraint(
        _ id: UInt64, className: String = "NSLayoutConstraint", identifier: String? = nil,
        _ first: LayoutItem, _ firstAttribute: LayoutAttribute,
        _ second: LayoutItem? = nil, _ secondAttribute: LayoutAttribute = .notAnAttribute,
        constant: Double = 0, priority: Float = 1000, status: ConstraintStatus = .satisfied
    ) -> LayoutConstraint {
        LayoutConstraint(
            id: id, className: className, identifier: identifier, firstItem: first,
            firstAttribute: firstAttribute, relation: .equal, secondItem: second,
            secondAttribute: secondAttribute, multiplier: 1, constant: constant,
            priority: priority, status: status,
            origin: className == "NSLayoutConstraint" ? .app : .system)
    }

    /// Layer 9's constraints, the shapes UIKit makes from an autoresizing mask (protocol 0.5).
    private static let autoresizingConstraints: [LayoutConstraint] = {
        let autoresizing = "NSAutoresizingMaskLayoutConstraint"
        return [
            // The flexible left margin, written from the superview's side: 393 = 300 + 93.
            constraint(
                8, className: autoresizing, .view(layerID: 2), .width, .view(layerID: 9), .maxX,
                constant: 93),
            constraint(9, className: autoresizing, .view(layerID: 9), .width),
            // The fixed top margin, without a second item.
            constraint(10, className: autoresizing, .view(layerID: 9), .minY, constant: 700),
            constraint(11, className: autoresizing, .view(layerID: 9), .height),
        ]
    }()

    private static let shared = constraint(4, .view(layerID: 4), .top, .view(layerID: 3), .bottom, constant: 78)

    func test_C_WIRE_06_layoutConstraintsRequest() throws {
        let requests = [UInt64(3), 4, 9, 8, 99].map {
            LayerDetailRequest(
                layerID: $0, wantSolo: false, wantGroup: false, wantAttributes: false,
                wantConstraints: true)
        }
        XCTAssertEqual(
            try decode("layout-constraints", "01-c2s-get-layer-details.bin"),
            Frame(requestID: 1, body: .getLayerDetails(GetLayerDetails(
                requests: requests, maxTextureDimension: 16384))))
    }

    func test_C_WIRE_06_layoutConstraintsAnswer() throws {
        let frame = try decode("layout-constraints", "02-s2c-chunk-0.bin")
        XCTAssertEqual(frame.requestID, 1)
        guard case .layerDetailsChunk(let chunk) = frame.body else {
            XCTFail("not a chunk: \(String(describing: frame.body))")
            return
        }
        XCTAssertEqual(chunk.sequence, 0)
        XCTAssertEqual(chunk.details.map(\.layerID), [3, 4, 9, 8, 99])

        let layer3 = chunk.details[0]
        XCTAssertEqual(layer3.status, .ok)
        XCTAssertNil(layer3.solo)
        XCTAssertEqual(layer3.attributeGroups, [])
        XCTAssertEqual(layer3.constraints, [
            Self.constraint(1, .view(layerID: 3), .centerX, .view(layerID: 2), .centerX),
            Self.constraint(
                2, .view(layerID: 3), .top, .layoutGuide(Self.safeArea), .top, constant: 49),
            // No second item; optional and losing (P-LAYOUT-05, P-LAYOUT-06).
            Self.constraint(
                3, identifier: "titleLabel.preferredWidth", .view(layerID: 3), .width,
                constant: 240, priority: 250, status: .unsatisfied),
            Self.shared,
        ])

        // The same constraint, the same ID and content, in both views' details (P-LAYOUT-03).
        XCTAssertEqual(chunk.details[1].constraints, [
            Self.shared,
            Self.constraint(5, .view(layerID: 4), .width, constant: 300),
            Self.constraint(6, .view(layerID: 4), .height, constant: 180),
            Self.constraint(7, .view(layerID: 4), .centerX, .view(layerID: 2), .centerX),
        ])

        // Made by UIKit, not filtered out (P-LAYOUT-02).
        XCTAssertEqual(chunk.details[2].constraints, Self.autoresizingConstraints)

        // Not the layer of a view: no constraints (P-LAYOUT-01).
        XCTAssertEqual(
            chunk.details[3],
            LayerDetail(layerID: 8, status: .ok, solo: nil, group: nil, attributeGroups: []))
        // Gone, whether released or out of every window (P-DET-02, P-HIER-12).
        XCTAssertEqual(
            chunk.details[4],
            LayerDetail(
                layerID: 99, status: .layerNotFound, solo: nil, group: nil, attributeGroups: []))

        XCTAssertEqual(
            try decode("layout-constraints", "03-s2c-stream-end.bin"),
            Frame(requestID: 1, body: .streamEnd(StreamEnd(
                status: .completed, chunkCount: 1, error: nil))))
    }

    func test_C_WIRE_06_detailsWithoutConstraintsReadAsAnEmptyList() throws {
        // The bytes of this scenario are the same as in protocol 0.3, which had no constraints.
        let frame = try decode("layer-details", "02-s2c-chunk-0.bin")
        guard case .layerDetailsChunk(let chunk) = frame.body else {
            XCTFail("not a chunk: \(String(describing: frame.body))")
            return
        }
        XCTAssertFalse(chunk.details.isEmpty)
        for detail in chunk.details {
            XCTAssertEqual(detail.constraints, [], "layer \(detail.layerID)")
        }

        guard case .getLayerDetails(let request) = try decode(
            "layer-details", "01-c2s-get-layer-details.bin").body
        else {
            XCTFail("not a request")
            return
        }
        XCTAssertTrue(request.requests.allSatisfy { !$0.wantConstraints })
    }

    func test_C_WIRE_06_everyKindOfEndAndEveryEnumCaseRoundTrips() throws {
        let attributes: [LayoutAttribute] = [
            .notAnAttribute, .left, .right, .top, .bottom, .leading, .trailing, .width, .height,
            .centerX, .centerY, .lastBaseline, .firstBaseline, .leftMargin, .rightMargin,
            .topMargin, .bottomMargin, .leadingMargin, .trailingMargin, .centerXWithinMargins,
            .centerYWithinMargins, .minX, .minY, .maxX, .maxY,
        ]
        XCTAssertEqual(attributes.map(\.rawValue), Array(0...20) + [32, 33, 36, 37])
        let relations: [LayoutRelation] = [.equal, .lessThanOrEqual, .greaterThanOrEqual]
        let statuses: [ConstraintStatus] = [.unknown, .satisfied, .unsatisfied]
        let ends: [LayoutItem?] = [
            .view(layerID: 7),
            .layoutGuide(LayoutGuide(
                ownerLayerID: 2, guideID: 5, className: "UILayoutGuide",
                displayClassName: "UILayoutGuide", identifier: nil, frame: nil)),
            .layoutGuide(Self.safeArea),
            .other(className: "_UIFancyAnchor", displayClassName: "FancyAnchor"),
            .other(className: nil, displayClassName: nil),
            nil,
        ]

        var constraints: [LayoutConstraint] = []
        for (index, attribute) in attributes.enumerated() {
            constraints.append(LayoutConstraint(
                id: UInt64(index + 1), className: index.isMultiple(of: 2) ? "NSLayoutConstraint" : nil,
                identifier: index == 3 ? "named" : nil, firstItem: ends[index % ends.count],
                firstAttribute: attribute, relation: relations[index % relations.count],
                secondItem: ends[(index + 1) % ends.count],
                secondAttribute: attributes[(index + 5) % attributes.count],
                multiplier: 0.5 * Double(index), constant: -12.25 + Double(index),
                priority: Float(1 + index * 40), status: statuses[index % statuses.count]))
        }
        let detail = LayerDetail(
            layerID: 3, status: .ok, solo: nil, group: nil, attributeGroups: [],
            constraints: constraints)
        let answer = Frame(requestID: 6, body: .layerDetailsChunk(LayerDetailsChunk(
            sequence: 0, details: [detail])))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(answer)), answer)

        let request = Frame(requestID: 6, body: .getLayerDetails(GetLayerDetails(
            requests: [
                LayerDetailRequest(
                    layerID: 3, wantSolo: true, wantGroup: false, wantAttributes: true,
                    wantConstraints: true),
                LayerDetailRequest(layerID: 4, wantSolo: true, wantGroup: true, wantAttributes: false),
            ],
            maxTextureDimension: 0)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(request)), request)
    }

    /// A constraint built field by field with raw enum values, so that values outside the schema
    /// can be written. The vtable offsets follow the field order in Protocol/schema/cutaway.fbs.
    private func constraint(
        kind: UInt8, first: UInt8, relation: UInt8, second: UInt8, status: UInt8
    ) throws -> LayoutConstraint {
        var builder = FlatBufferBuilder()
        let itemStart = Cutaway_Wire_LayoutItem.startLayoutItem(&builder)
        builder.add(element: kind, def: 0, at: 4)  // kind
        builder.add(element: UInt64(3), def: 0, at: 6)  // layer_id
        let item = Cutaway_Wire_LayoutItem.endLayoutItem(&builder, start: itemStart)
        let start = Cutaway_Wire_LayoutConstraint.startLayoutConstraint(&builder)
        Cutaway_Wire_LayoutConstraint.add(id: 1, &builder)
        Cutaway_Wire_LayoutConstraint.add(firstItem: item, &builder)
        builder.add(element: first, def: 0, at: 12)  // first_attribute
        builder.add(element: relation, def: 0, at: 14)  // relation
        builder.add(element: second, def: 0, at: 18)  // second_attribute
        builder.add(element: status, def: 0, at: 26)  // status
        let end = Cutaway_Wire_LayoutConstraint.endLayoutConstraint(&builder, start: start)
        Cutaway_Wire_LayoutConstraint.finish(&builder, end: end)

        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_LayoutConstraint = try getCheckedRoot(
            byteBuffer: &buffer, fileId: "CTWY")
        return LayoutConstraint(wire)
    }

    /// P-HELLO-04 keeps a peer from sending enum values this client does not know, but one that
    /// does anyway must not fail the decoding.
    func test_C_WIRE_06_unknownEnumValuesReadAsTheirDefaults() throws {
        // Known values first, so that the offsets are shown to reach the fields.
        let known = try constraint(kind: 2, first: 9, relation: 2, second: 20, status: 2)
        XCTAssertEqual(known.firstItem, .other(className: nil, displayClassName: nil))
        XCTAssertEqual(known.firstAttribute, .centerX)
        XCTAssertEqual(known.relation, .greaterThanOrEqual)
        XCTAssertEqual(known.secondAttribute, .centerYWithinMargins)
        XCTAssertEqual(known.status, .unsatisfied)

        let unknown = try constraint(kind: 5, first: 99, relation: 7, second: 21, status: 9)
        XCTAssertEqual(unknown.firstAttribute, .notAnAttribute)
        XCTAssertEqual(unknown.relation, .equal)
        XCTAssertEqual(unknown.secondAttribute, .notAnAttribute)
        XCTAssertEqual(unknown.status, .unknown)
        // An item kind from a later version reads as a view, the kind's default.
        XCTAssertEqual(unknown.firstItem, .view(layerID: 3))
    }

    /// The round trip above cannot catch a mapping that is wrong the same way in both
    /// directions, so the values on the wire are checked against the schema's.
    func test_C_WIRE_06_enumsAreWrittenWithTheSchemasValues() throws {
        let relations: [LayoutRelation] = [.equal, .lessThanOrEqual, .greaterThanOrEqual]
        let statuses: [ConstraintStatus] = [.unknown, .satisfied, .unsatisfied]
        let ends: [LayoutItem] = [
            .view(layerID: 3), .layoutGuide(Self.safeArea),
            .other(className: "_UIAnchor", displayClassName: "Anchor"),
        ]
        let constraints = (0..<3).map { index in
            LayoutConstraint(
                id: UInt64(index + 1), className: nil, identifier: nil, firstItem: ends[index],
                firstAttribute: .centerYWithinMargins, relation: relations[index],
                secondItem: nil, secondAttribute: .notAnAttribute, multiplier: 1, constant: 0,
                priority: 1000, status: statuses[index])
        }
        let frame = Frame(requestID: 2, body: .layerDetailsChunk(LayerDetailsChunk(
            sequence: 0, details: [LayerDetail(
                layerID: 3, status: .ok, solo: nil, group: nil, attributeGroups: [],
                constraints: constraints)])))

        var buffer = ByteBuffer(data: FrameCodec.encode(frame))
        let wire: Cutaway_Wire_Frame = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        let chunk = try XCTUnwrap(wire.body(type: Cutaway_Wire_LayerDetailsChunk.self))
        let written = try XCTUnwrap(chunk.details.first).constraints
        XCTAssertEqual(written.count, 3)
        XCTAssertEqual(written.map { $0.relation.rawValue }, [0, 1, 2])
        XCTAssertEqual(written.map { $0.status.rawValue }, [0, 1, 2])
        XCTAssertEqual(written.map { $0.firstItem?.kind.rawValue }, [0, 1, 2])
        XCTAssertEqual(written.map { $0.firstAttribute.rawValue }, [20, 20, 20])
    }

    // MARK: - Protocol 0.5

    func test_C_WIRE_07_theAutoresizingAttributesAreWrittenWithUIKitsRawValues() throws {
        let attributes: [LayoutAttribute] = [.minX, .minY, .maxX, .maxY]
        XCTAssertEqual(attributes.map(\.rawValue), [32, 33, 36, 37])

        let constraints = attributes.enumerated().map { index, attribute in
            LayoutConstraint(
                id: UInt64(index + 1), className: nil, identifier: nil,
                firstItem: .view(layerID: 3), firstAttribute: attribute, relation: .equal,
                secondItem: .view(layerID: 2), secondAttribute: attributes[(index + 1) % 4],
                multiplier: 1, constant: 0, priority: 1000, status: .unknown)
        }
        let frame = Frame(requestID: 2, body: .layerDetailsChunk(LayerDetailsChunk(
            sequence: 0, details: [LayerDetail(
                layerID: 3, status: .ok, solo: nil, group: nil, attributeGroups: [],
                constraints: constraints)])))

        var buffer = ByteBuffer(data: FrameCodec.encode(frame))
        let wire: Cutaway_Wire_Frame = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        let chunk = try XCTUnwrap(wire.body(type: Cutaway_Wire_LayerDetailsChunk.self))
        let written = try XCTUnwrap(chunk.details.first).constraints
        XCTAssertEqual(written.map { $0.firstAttribute.rawValue }, [32, 33, 36, 37])
        XCTAssertEqual(written.map { $0.secondAttribute.rawValue }, [33, 36, 37, 32])
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
    }

    /// P-LAYOUT-08: a value the protocol does not name reads as `NotAnAttribute`.
    func test_C_WIRE_07_attributesTheProtocolDoesNotNameReadAsNotAnAttribute() throws {
        let named = try constraint(kind: 0, first: 32, relation: 0, second: 37, status: 0)
        XCTAssertEqual(named.firstAttribute, .minX)
        XCTAssertEqual(named.secondAttribute, .maxY)
        let alsoNamed = try constraint(kind: 0, first: 33, relation: 0, second: 36, status: 0)
        XCTAssertEqual(alsoNamed.firstAttribute, .minY)
        XCTAssertEqual(alsoNamed.secondAttribute, .maxX)

        for (first, second) in [(UInt8(34), UInt8(35)), (38, 21)] {
            let unnamed = try constraint(
                kind: 0, first: first, relation: 0, second: second, status: 0)
            XCTAssertEqual(unnamed.firstAttribute, .notAnAttribute, "\(first)")
            XCTAssertEqual(unnamed.secondAttribute, .notAnAttribute, "\(second)")
        }
    }
}
