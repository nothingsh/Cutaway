import CutawayTestSupport
import CutawayWire
import XCTest

/// C-WIRE-01 and C-WIRE-04. The expected values come from Protocol/fixtures/README.md and
/// Protocol/fixtures/src.
final class FixtureDecodingTests: XCTestCase {
    private func decode(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    private static let demoApp = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.4.0")

    /// The client of the `handshake` fixture.
    private static let cutawayClient = ClientInfo(name: "Cutaway", version: "0.4.0")
    /// The client of the `handshake-version-mismatch` fixture, which was not updated for 0.2.
    private static let mismatchClient = ClientInfo(name: "Cutaway", version: "0.1.0")

    // MARK: - C-WIRE-01

    func test_C_WIRE_01_everyFixtureFrameDecodes() throws {
        let scenarios = try Fixtures.scenarios()
        XCTAssertEqual(scenarios.count, 14)
        var count = 0
        for scenario in scenarios {
            for frame in try Fixtures.frames(scenario: scenario) {
                XCTAssertNoThrow(
                    try FrameCodec.decode(frame.payload), "\(scenario)/\(frame.fileName)")
                count += 1
            }
        }
        XCTAssertEqual(count, 52)
    }

    func test_C_WIRE_01_handshake() throws {
        XCTAssertEqual(
            try decode("handshake", "01-c2s-hello.bin"),
            Frame(requestID: 0, body: .hello(Hello(
                protocolVersion: Version(major: 1, minor: 0), role: .client,
                client: Self.cutawayClient, app: nil))))
        XCTAssertEqual(
            try decode("handshake", "02-s2c-hello.bin"),
            Frame(requestID: 0, body: .hello(Hello(
                protocolVersion: Version(major: 1, minor: 0), role: .server,
                client: nil, app: Self.demoApp))))
        XCTAssertEqual(
            try decode("handshake", "03-s2c-app-state.bin"),
            Frame(requestID: 0, body: .appStateChanged(.active)))
    }

    func test_C_WIRE_01_handshakeVersionMismatch() throws {
        XCTAssertEqual(
            try decode("handshake-version-mismatch", "01-c2s-hello.bin"),
            Frame(requestID: 0, body: .hello(Hello(
                protocolVersion: Version(major: 1, minor: 0), role: .client,
                client: Self.mismatchClient, app: nil))))
        XCTAssertEqual(
            try decode("handshake-version-mismatch", "02-s2c-hello.bin"),
            Frame(requestID: 0, body: .hello(Hello(
                protocolVersion: Version(major: 0, minor: 5), role: .server,
                client: nil, app: Self.demoApp))))
    }

    func test_C_WIRE_01_busy() throws {
        XCTAssertEqual(
            try decode("busy", "01-s2c-error.bin"),
            Frame(requestID: 0, body: .error(ServerError(
                code: .busy, message: "another client is connected"))))
    }

    func test_C_WIRE_01_appIcon() throws {
        XCTAssertEqual(
            try decode("app-icon", "01-c2s-get-app-icon.bin"),
            Frame(requestID: 1, body: .getAppIcon))

        let frame = try decode("app-icon", "02-s2c-app-icon.bin")
        XCTAssertEqual(frame.requestID, 1)
        guard case .appIcon(let icon) = frame.body else {
            XCTFail("not an AppIcon")
            return
        }
        let image = try XCTUnwrap(icon.image)
        XCTAssertEqual(image.encoding, .bgra8PremultipliedLzfse)
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 2)
        XCTAssertEqual(image.bytesPerRow, 8)
        XCTAssertEqual(image.scale, 1)
        XCTAssertEqual(
            image.data.map { String(format: "%02x", $0) }.joined(),
            "6276782d100000000000ffff00ff00ffff0000ff0000000062767824")
    }

    func test_C_WIRE_01_hierarchy() throws {
        XCTAssertEqual(
            try decode("hierarchy", "01-c2s-get-hierarchy.bin"),
            Frame(requestID: 2, body: .getHierarchy))

        let expected = Self.expectedHierarchy()

        let frame = try decode("hierarchy", "02-s2c-hierarchy.bin")
        XCTAssertEqual(frame.requestID, 2)
        guard case .hierarchy(let hierarchy) = frame.body else {
            XCTFail("not a Hierarchy")
            return
        }
        XCTAssertEqual(hierarchy.keyWindowID, expected.keyWindowID)
        XCTAssertEqual(hierarchy.nodes.count, 9)
        // Compared one by one so that a failure names the node.
        for (actual, wanted) in zip(hierarchy.nodes, expected.nodes) {
            XCTAssertEqual(actual, wanted, "node \(wanted.id)")
        }
    }

    /// The layers of the `hierarchy` fixture's answer.
    private static func expectedHierarchy() -> Hierarchy {
        func node(
            _ id: UInt64, parent: UInt64, layer: String, view: String?, viewDisplay: String? = nil,
            bounds: Rect, position: Point, anchor: Point = Point(x: 0.5, y: 0.5),
            transform: Transform3D = .identity, hidden: Bool = false, opacity: Float = 1,
            masks: Bool = false, controller: Bool = false, members: [MemberReference] = []
        ) -> LayerNode {
            LayerNode(
                id: id, parentID: parent, className: layer, displayClassName: layer,
                viewClassName: view, viewDisplayClassName: viewDisplay ?? view,
                bounds: bounds, position: position, anchorPoint: anchor, transform: transform,
                zPosition: 0, isHidden: hidden, opacity: opacity, masksToBounds: masks,
                viewControllerClassName: controller ? "Demo.HomeViewController" : nil,
                viewControllerDisplayClassName: controller ? "HomeViewController" : nil,
                memberReferences: members)
        }
        // Protocol 0.2 (P-HIER-07 to P-HIER-09; Protocol/fixtures/README.md).
        func home(_ name: String) -> MemberReference {
            MemberReference(
                ownerClassName: "Demo.HomeViewController",
                ownerDisplayClassName: "HomeViewController", name: name)
        }
        func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Rect {
            Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height))
        }
        var rotation = Transform3D.identity
        rotation.m11 = 0.8660254037844387
        rotation.m12 = 0.5
        rotation.m21 = -0.5
        rotation.m22 = 0.8660254037844387

        return Hierarchy(
            nodes: [
                node(1, parent: 0, layer: "UIWindowLayer", view: "UIWindow",
                     bounds: rect(0, 0, 393, 852), position: Point(x: 196.5, y: 426)),
                node(2, parent: 1, layer: "CALayer", view: "UIView",
                     bounds: rect(0, 0, 393, 852), position: Point(x: 196.5, y: 426),
                     controller: true),
                node(3, parent: 2, layer: "_UILabelLayer", view: "UILabel",
                     bounds: rect(0, 0, 200, 24), position: Point(x: 196.5, y: 120),
                     members: [home("titleLabel")]),
                node(4, parent: 2, layer: "CALayer", view: "Demo.CardView", viewDisplay: "CardView",
                     bounds: rect(0, 0, 300, 180), position: Point(x: 196.5, y: 300),
                     transform: rotation, masks: true, members: [home("cardView")]),
                node(5, parent: 4, layer: "CAShapeLayer", view: nil,
                     bounds: rect(0, 0, 40, 40), position: Point(x: 40, y: 40),
                     hidden: true, opacity: 0.5,
                     members: [
                         MemberReference(
                             ownerClassName: "Demo.CardView", ownerDisplayClassName: "CardView",
                             name: "badgeLayer"),
                         home("cardBadge"),
                     ]),
                node(6, parent: 2, layer: "CALayer", view: "UIScrollView",
                     bounds: rect(0, 100, 300, 200), position: Point(x: 196.5, y: 600), masks: true,
                     members: [home("scrollView")]),
                node(7, parent: 6, layer: "_UILabelLayer", view: "UILabel",
                     bounds: rect(0, 0, 100, 40), position: Point(x: 150, y: 150)),
                node(8, parent: 2, layer: "CALayer", view: nil,
                     bounds: rect(0, 0, 60, 30), position: Point(x: 10, y: 10),
                     anchor: Point(x: 0, y: 0),
                     members: [
                         // An Objective-C instance variable keeps its underscore (P-HIER-09).
                         MemberReference(
                             ownerClassName: "DMBaseViewController",
                             ownerDisplayClassName: "DMBaseViewController", name: "_dividerLayer"),
                     ]),
                node(9, parent: 2, layer: "CALayer", view: "UIView",
                     bounds: rect(0, 0, 0, 0), position: Point(x: 300, y: 700)),
            ],
            keyWindowID: 1)
    }

    func test_C_WIRE_01_layerDetails() throws {
        XCTAssertEqual(
            try decode("layer-details", "01-c2s-get-layer-details.bin"),
            Frame(requestID: 3, body: .getLayerDetails(GetLayerDetails(
                requests: [
                    LayerDetailRequest(layerID: 3, wantSolo: false, wantGroup: true, wantAttributes: true),
                    LayerDetailRequest(layerID: 4, wantSolo: true, wantGroup: true, wantAttributes: false),
                    LayerDetailRequest(layerID: 99, wantSolo: false, wantGroup: true, wantAttributes: false),
                ],
                maxTextureDimension: 16384))))

        // Chunk 0: layer 3 with a group image and all its attributes.
        let first = try decode("layer-details", "02-s2c-chunk-0.bin")
        XCTAssertEqual(first.requestID, 3)
        guard case .layerDetailsChunk(let chunk0) = first.body else {
            XCTFail("not a chunk")
            return
        }
        XCTAssertEqual(chunk0.sequence, 0)
        XCTAssertEqual(chunk0.details.count, 1)
        let layer3 = chunk0.details[0]
        XCTAssertEqual(layer3.layerID, 3)
        XCTAssertEqual(layer3.status, .ok)
        XCTAssertNil(layer3.solo)
        let red = try XCTUnwrap(layer3.group)
        XCTAssertEqual([red.pixelWidth, red.pixelHeight, red.bytesPerRow], [200, 24, 800])
        XCTAssertEqual(red.scale, 1)
        XCTAssertEqual(red.data.count, 164)

        XCTAssertEqual(layer3.attributeGroups, ExpectedAttributes.layer3())

        // Chunk 1: layer 4 with both images, layer 99 not found.
        let second = try decode("layer-details", "03-s2c-chunk-1.bin")
        guard case .layerDetailsChunk(let chunk1) = second.body else {
            XCTFail("not a chunk")
            return
        }
        XCTAssertEqual(chunk1.sequence, 1)
        XCTAssertEqual(chunk1.details.map(\.layerID), [4, 99])
        let layer4 = chunk1.details[0]
        XCTAssertEqual(layer4.status, .ok)
        for image in [try XCTUnwrap(layer4.solo), try XCTUnwrap(layer4.group)] {
            XCTAssertEqual([image.pixelWidth, image.pixelHeight, image.bytesPerRow], [300, 180, 1200])
            XCTAssertEqual(image.data.count, 275)
        }
        XCTAssertEqual(layer4.attributeGroups, [])
        XCTAssertEqual(
            chunk1.details[1],
            LayerDetail(layerID: 99, status: .layerNotFound, solo: nil, group: nil, attributeGroups: []))

        XCTAssertEqual(
            try decode("layer-details", "04-s2c-stream-end.bin"),
            Frame(requestID: 3, body: .streamEnd(StreamEnd(
                status: .completed, chunkCount: 2, error: nil))))
    }

    func test_C_WIRE_01_layerDetailsEdge() throws {
        let frame = try decode("layer-details-edge", "02-s2c-chunk-0.bin")
        XCTAssertEqual(frame.requestID, 4)
        guard case .layerDetailsChunk(let chunk) = frame.body else {
            XCTFail("not a chunk")
            return
        }
        XCTAssertEqual(chunk.details.map(\.layerID), [3, 8, 9, 7])

        // Layer 3: solo was requested, only group came back.
        XCTAssertNil(chunk.details[0].solo)
        XCTAssertNotNil(chunk.details[0].group)

        // Layer 8: rows padded to 256 bytes.
        let padded = try XCTUnwrap(chunk.details[1].group)
        XCTAssertEqual([padded.pixelWidth, padded.pixelHeight, padded.bytesPerRow], [60, 30, 256])

        // Layer 9: capture failed, attributes still present.
        XCTAssertEqual(chunk.details[2], LayerDetail(
            layerID: 9, status: .captureFailed, solo: nil, group: nil,
            attributeGroups: [
                AttributeGroup(id: "layer", title: "Layer", attributes: [
                    Attribute(
                        id: "layer.frame", title: "Frame",
                        value: .rect(Rect(
                            origin: Point(x: 300, y: 700), size: Size(width: 0, height: 0))),
                        editable: false, valueKind: .rect),
                    Attribute(
                        id: "layer.hidden", title: "Hidden", value: .bool(false), editable: true,
                        valueKind: .bool),
                ]),
            ]))

        // Layer 7: nothing was requested.
        XCTAssertEqual(
            chunk.details[3],
            LayerDetail(layerID: 7, status: .ok, solo: nil, group: nil, attributeGroups: []))

        XCTAssertEqual(
            try decode("layer-details-edge", "03-s2c-stream-end.bin"),
            Frame(requestID: 4, body: .streamEnd(StreamEnd(
                status: .completed, chunkCount: 1, error: nil))))
    }

    func test_C_WIRE_01_layerDetailsCancelled() throws {
        let chunk = try decode("layer-details-cancelled", "02-s2c-chunk-0.bin")
        guard case .layerDetailsChunk(let body) = chunk.body else {
            XCTFail("not a chunk")
            return
        }
        let blue = try XCTUnwrap(body.details.first?.group)
        XCTAssertEqual([blue.pixelWidth, blue.pixelHeight, blue.bytesPerRow], [393, 852, 1572])

        XCTAssertEqual(
            try decode("layer-details-cancelled", "03-c2s-cancel.bin"),
            Frame(requestID: 6, body: .cancel(Cancel(targetRequestID: 5))))
        XCTAssertEqual(
            try decode("layer-details-cancelled", "04-s2c-stream-end.bin"),
            Frame(requestID: 5, body: .streamEnd(StreamEnd(
                status: .cancelled, chunkCount: 1, error: nil))))
    }

    func test_C_WIRE_01_appNotActive() throws {
        XCTAssertEqual(
            try decode("app-not-active", "01-s2c-app-state.bin"),
            Frame(requestID: 0, body: .appStateChanged(.background)))
        XCTAssertEqual(
            try decode("app-not-active", "02-c2s-get-hierarchy.bin"),
            Frame(requestID: 7, body: .getHierarchy))
        XCTAssertEqual(
            try decode("app-not-active", "03-s2c-error.bin"),
            Frame(requestID: 7, body: .error(ServerError(
                code: .appNotActive, message: "the app is not active"))))
    }

    func test_C_WIRE_01_layerDetailsFailed() throws {
        XCTAssertEqual(
            try decode("layer-details-failed", "02-s2c-app-state.bin"),
            Frame(requestID: 0, body: .appStateChanged(.inactive)))
        XCTAssertEqual(
            try decode("layer-details-failed", "03-s2c-stream-end.bin"),
            Frame(requestID: 8, body: .streamEnd(StreamEnd(
                status: .failed, chunkCount: 0,
                error: ServerError(
                    code: .appNotActive,
                    message: "the app left the active state during capture")))))
    }

    // MARK: - C-WIRE-04

    func test_C_WIRE_04_omittedScalarsReadAsDefaults() throws {
        // flatc does not write fields equal to their default.
        // request_id 0 and AppState.Active (the first member) are both omitted here.
        XCTAssertEqual(
            try decode("handshake", "03-s2c-app-state.bin"),
            Frame(requestID: 0, body: .appStateChanged(.active)))

        guard case .hierarchy(let hierarchy) = try decode("hierarchy", "02-s2c-hierarchy.bin").body
        else {
            XCTFail("not a Hierarchy")
            return
        }
        let root = hierarchy.nodes[0]
        XCTAssertEqual(root.parentID, 0)
        XCTAssertEqual(root.zPosition, 0)
        XCTAssertFalse(root.isHidden)
        XCTAssertFalse(root.masksToBounds)

        // DetailStatus.Ok, chunk_count 0 and StreamStatus.Completed are omitted too.
        guard case .streamEnd(let failed) =
            try decode("layer-details-failed", "03-s2c-stream-end.bin").body
        else {
            XCTFail("not a StreamEnd")
            return
        }
        XCTAssertEqual(failed.chunkCount, 0)
    }

    func test_C_WIRE_04_absentTableFieldsReadAsNil() throws {
        // A layer that backs no view has no view class names.
        guard case .hierarchy(let hierarchy) = try decode("hierarchy", "02-s2c-hierarchy.bin").body
        else {
            XCTFail("not a Hierarchy")
            return
        }
        XCTAssertNil(hierarchy.nodes[4].viewClassName)
        XCTAssertNil(hierarchy.nodes[4].viewDisplayClassName)
        // A layer that backs no view controller, and that no member holds (protocol 0.2).
        XCTAssertNil(hierarchy.nodes[0].viewControllerClassName)
        XCTAssertNil(hierarchy.nodes[0].viewControllerDisplayClassName)
        XCTAssertEqual(hierarchy.nodes[0].memberReferences, [])

        // An attribute without a value is nil, and the attribute is still there.
        guard case .layerDetailsChunk(let chunk) =
            try decode("layer-details", "02-s2c-chunk-0.bin").body
        else {
            XCTFail("not a chunk")
            return
        }
        let background = try XCTUnwrap(
            chunk.details[0].attributeGroups[0].attributes.first { $0.id == "layer.backgroundColor" })
        XCTAssertEqual(background.title, "Background Color")
        XCTAssertNil(background.value)

        // Absent sub-tables and vectors.
        guard case .layerDetailsChunk(let edge) =
            try decode("layer-details-edge", "02-s2c-chunk-0.bin").body
        else {
            XCTFail("not a chunk")
            return
        }
        XCTAssertNil(edge.details[3].solo)
        XCTAssertNil(edge.details[3].group)
        XCTAssertEqual(edge.details[3].attributeGroups, [])

        // A client Hello has no app; a StreamEnd that did not fail has no error.
        guard case .hello(let hello) = try decode("handshake", "01-c2s-hello.bin").body
        else {
            XCTFail("not a Hello")
            return
        }
        XCTAssertNil(hello.app)
    }
}
