import CutawayTestSupport
import CutawayWire
import XCTest

/// Encoding, checked against decoding: what is encoded must decode to the same value.
final class RoundTripTests: XCTestCase {
    func test_C_WIRE_01_everyFixtureFrameSurvivesARoundTrip() throws {
        let scenarios = try Fixtures.scenarios()
        XCTAssertEqual(scenarios.count, 16)
        var count = 0
        for scenario in scenarios {
            for fixture in try Fixtures.frames(scenario: scenario) {
                let frame = try FrameCodec.decode(fixture.payload)
                let encoded = FrameCodec.encode(frame)
                XCTAssertEqual(
                    try FrameCodec.decode(encoded), frame, "\(scenario)/\(fixture.fileName)")
                count += 1
            }
        }
        XCTAssertEqual(count, 79)
    }

    func test_C_WIRE_04_aFrameWithoutABodyRoundTrips() throws {
        let frame = Frame(requestID: 9, body: nil)
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
    }

    func test_C_WIRE_04_absentFieldsStayAbsentAfterEncoding() throws {
        // nil must be written as "absent", not as an empty string or a zero struct.
        let node = LayerNode(
            id: 5, parentID: 4, className: "CAShapeLayer", displayClassName: nil,
            viewClassName: nil, viewDisplayClassName: nil, bounds: nil, position: nil,
            anchorPoint: nil, transform: nil, zPosition: 0, isHidden: false, opacity: 0,
            masksToBounds: false)
        let frame = Frame(
            requestID: 1, body: .hierarchy(Hierarchy(nodes: [node], keyWindowID: 0)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)

        let hello = Frame(requestID: 0, body: .hello(Hello(
            protocolVersion: nil, role: .client, client: nil, app: nil)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(hello)), hello)
    }

    func test_C_WIRE_02_reencodedClientFramesReadBackFromAStream() throws {
        var count = 0
        for scenario in try Fixtures.scenarios() {
            for fixture in try Fixtures.frames(scenario: scenario)
                where fixture.direction == .clientToServer
            {
                let frame = try FrameCodec.decode(fixture.payload)
                let stream = FrameCodec.encodeForStream(frame)

                // A 4-byte little-endian length, then a plain buffer: its bytes 4..<8 are the
                // file identifier. A size-prefixed FlatBuffer would not look like this.
                let length = stream.prefix(4).enumerated()
                    .reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
                XCTAssertEqual(length, stream.count - 4, "\(scenario)/\(fixture.fileName)")
                XCTAssertEqual(Data(stream[8..<12]), Data("CTWY".utf8))

                var reader = FrameReader()
                reader.append(stream)
                let payload = try XCTUnwrap(try reader.nextPayload())
                XCTAssertEqual(try FrameCodec.decode(payload), frame)
                XCTAssertNil(try reader.nextPayload())
                count += 1
            }
        }
        // Hello x2, GetAppIcon, GetHierarchy x2, GetLayerDetails x4, Cancel; protocol 0.3:
        // SetAttribute x9, GetSubtree x2; protocol 0.4: GetLayerDetails x1; protocol 1.1:
        // SetAttribute x2 outside the limits, x1 for the layer's attribute of a pair and x1 for
        // the layer's background.
        XCTAssertEqual(count, 35)
    }

    func test_C_WIRE_04_aNodeWithoutAControllerOrMembersRoundTripsWithout() throws {
        // The encoder writes an empty vector; a vector that is absent altogether, as from a
        // 0.1 server, is read in FixtureDecodingTests (the fixture's first node).
        let node = LayerNode(
            id: 1, parentID: 0, className: "CALayer", displayClassName: "CALayer",
            viewClassName: nil, viewDisplayClassName: nil, bounds: nil, position: nil,
            anchorPoint: nil, transform: nil, zPosition: 0, isHidden: false, opacity: 1,
            masksToBounds: false)
        let frame = Frame(
            requestID: 2, body: .hierarchy(Hierarchy(nodes: [node], keyWindowID: 0)))
        guard case .hierarchy(let decoded) = try FrameCodec.decode(FrameCodec.encode(frame)).body
        else {
            XCTFail("not a Hierarchy")
            return
        }
        XCTAssertNil(decoded.nodes[0].viewControllerClassName)
        XCTAssertNil(decoded.nodes[0].viewControllerDisplayClassName)
        XCTAssertEqual(decoded.nodes[0].memberReferences, [])
    }

    func test_C_WIRE_01_memberReferencesRoundTripInOrder() throws {
        let references = [
            MemberReference(ownerClassName: "A", ownerDisplayClassName: "A", name: "first"),
            MemberReference(ownerClassName: nil, ownerDisplayClassName: nil, name: "second"),
        ]
        let node = LayerNode(
            id: 1, parentID: 0, className: nil, displayClassName: nil, viewClassName: nil,
            viewDisplayClassName: nil, bounds: nil, position: nil, anchorPoint: nil,
            transform: nil, zPosition: 0, isHidden: false, opacity: 1, masksToBounds: false,
            viewControllerClassName: "Demo.VC", viewControllerDisplayClassName: "VC",
            memberReferences: references)
        let frame = Frame(
            requestID: 2, body: .hierarchy(Hierarchy(nodes: [node], keyWindowID: 0)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
    }
}
