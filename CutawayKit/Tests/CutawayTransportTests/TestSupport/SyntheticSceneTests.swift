import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// The scenes the test support library makes up (C-MOCK-03).
final class SyntheticSceneTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static let tenThousand = SyntheticScene(
        layerCount: 10_000, shape: .app(AppShape()), imagePixels: .fixed(width: 32, height: 32),
        attributes: true, constraints: true)

    /// Whether the nodes form a tree as P-HIER-01 and P-HIER-03 have it: IDs that are not 0
    /// and appear once, each parent before its children.
    private func assertIsTree(
        _ hierarchy: Hierarchy, file: StaticString = #filePath, line: UInt = #line
    ) {
        var seen = Set<UInt64>()
        for node in hierarchy.nodes {
            XCTAssertNotEqual(node.id, 0, file: file, line: line)
            XCTAssertTrue(seen.insert(node.id).inserted, "\(node.id) twice", file: file, line: line)
            if node.parentID != 0 {
                XCTAssertTrue(
                    seen.contains(node.parentID), "\(node.id) before its parent", file: file,
                    line: line)
            }
        }
    }

    func test_C_MOCK_03_tenThousandLayersMakeATreeAndEveryLayerHasDetails() async throws {
        let scene = Self.tenThousand
        let hierarchy = scene.hierarchy()
        XCTAssertEqual(hierarchy.nodes.count, 10_000)
        assertIsTree(hierarchy)
        XCTAssertEqual(hierarchy.keyWindowID, hierarchy.nodes[0].id)

        let details = scene.details()
        XCTAssertEqual(Set(details.keys), Set(hierarchy.nodes.map(\.id)))
        XCTAssertTrue(details.values.allSatisfy { $0.status == .ok && $0.solo != nil && $0.group != nil })
        XCTAssertTrue(details.values.allSatisfy { !$0.attributeGroups.isEmpty })
        XCTAssertTrue(details.values.contains { !$0.constraints.isEmpty })

        // Asked for every layer over a connection, as the preview asks: in batches of eight.
        let server = try await MockServer.start(
            script: MockScript(
                steps: try MockScript.fixtures("handshake").steps + [.respond(scene.responder())]),
            records: false)
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, requestTimeout: .seconds(10))
        _ = try await session.handshake()
        let answered0 = try await session.hierarchy()
        XCTAssertEqual(answered0, hierarchy)
        var answered = Set<UInt64>()
        let ids = hierarchy.nodes.map(\.id)
        for start in stride(from: 0, to: ids.count, by: 8) {
            let request = GetLayerDetails(
                requests: ids[start..<min(start + 8, ids.count)].map {
                    LayerDetailRequest(
                        layerID: $0, wantSolo: true, wantGroup: true, wantAttributes: true,
                        wantConstraints: true)
                },
                maxTextureDimension: 4096)
            for try await chunk in await session.layerDetails(request).chunks {
                for detail in chunk where detail.status == .ok { answered.insert(detail.layerID) }
            }
        }
        XCTAssertEqual(answered.count, 10_000)
        await session.close()
        await server.stop()
    }

    func test_C_MOCK_03_theSameParametersGiveTheSameBytes() {
        let shapes: [SyntheticScene.Shape] = [.deep, .wide, .app(AppShape())]
        for shape in shapes {
            let scene = SyntheticScene(
                layerCount: 600, shape: shape, imagePixels: .layerSize(scale: 0.25),
                attributes: true, constraints: true)
            XCTAssertEqual(Self.frames(of: scene), Self.frames(of: scene), "\(shape)")
            XCTAssertEqual(scene.hierarchy().nodes.count, 600, "\(shape)")
        }
    }

    func test_C_MOCK_03_theShapesNestAsTheirNamesSay() {
        let deep = SyntheticScene(layerCount: 50, shape: .deep).hierarchy()
        XCTAssertTrue(zip(deep.nodes.dropFirst(), deep.nodes).allSatisfy { $0.parentID == $1.id })

        let wide = SyntheticScene(layerCount: 50, shape: .wide).hierarchy()
        XCTAssertTrue(wide.nodes.dropFirst().allSatisfy { $0.parentID == wide.nodes[0].id })

        // A window, then screens: containers, a bar with its buttons, a list of cells.
        let app = SyntheticScene(layerCount: 2_000, shape: .app(AppShape())).hierarchy()
        let classes = app.nodes.compactMap(\.viewClassName)
        XCTAssertEqual(app.nodes[0].viewClassName, "UIWindow")
        XCTAssertGreaterThan(classes.filter { $0 == "UITableViewCell" }.count, 100)
        XCTAssertGreaterThan(classes.filter { $0 == "UINavigationBar" }.count, 1)
    }

    func test_C_MOCK_03_imagesHaveTheSizeAskedFor() throws {
        let fixed = SyntheticScene(
            layerCount: 20, shape: .app(AppShape()), imagePixels: .fixed(width: 32, height: 16))
        let image = try XCTUnwrap(fixed.details().values.first?.group)
        XCTAssertEqual(image.pixelWidth, 32)
        XCTAssertEqual(image.pixelHeight, 16)
        XCTAssertEqual(try image.decoded().pixels.count, 32 * 16 * 4)

        let none = SyntheticScene(layerCount: 20, shape: .app(AppShape()), imagePixels: .none)
        XCTAssertTrue(none.details().values.allSatisfy { $0.solo == nil && $0.group == nil })

        // The window is 393 × 852 points.
        let sized = SyntheticScene(
            layerCount: 1, shape: .app(AppShape()), imagePixels: .layerSize(scale: 2))
        let window = try XCTUnwrap(sized.details().values.first?.group)
        XCTAssertEqual(window.pixelWidth, 786)
        XCTAssertEqual(window.pixelHeight, 1704)
        XCTAssertEqual(window.scale, 2)
    }

    /// The hierarchy, then one chunk of every eight layers' details, encoded.
    private static func frames(of scene: SyntheticScene) -> [Data] {
        let hierarchy = scene.hierarchy()
        let details = scene.details()
        var frames = [FrameCodec.encode(Frame(requestID: 1, body: .hierarchy(hierarchy)))]
        let ids = hierarchy.nodes.map(\.id)
        for start in stride(from: 0, to: ids.count, by: 8) {
            let chunk = LayerDetailsChunk(
                sequence: 0, details: ids[start..<min(start + 8, ids.count)].compactMap { details[$0] })
            frames.append(FrameCodec.encode(Frame(requestID: 2, body: .layerDetailsChunk(chunk))))
        }
        return frames
    }
}
