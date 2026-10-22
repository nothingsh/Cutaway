import CutawayScene
import CutawayTestSupport
import Metal
import XCTest

@testable import CutawayRender

/// Frames use their vertex buffers again instead of making one each: drawing does not
/// allocate as the camera moves (C-SCALE-02), and what is drawn does not change (C-REND-01).
final class VertexBufferReuseTests: XCTestCase {
    private var device: (any MTLDevice)!
    private var renderer: Renderer!
    private var textures: TextureCache!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    private func hierarchyList(camera: Camera = .standard3D) throws -> DrawList {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(camera: camera, viewport: RenderFixtures.square, selected: 3, hovered: 4)
    }

    private func render(_ list: DrawList, with renderer: Renderer) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: .standard, pixelWidth: 900, pixelHeight: 900)
    }

    func test_C_SCALE_02_framesOneAfterAnotherUseOneVertexBuffer() throws {
        let list = try hierarchyList()
        let first = try render(list, with: renderer)
        for _ in 0..<9 {
            XCTAssertEqual(try render(list, with: renderer), first)
        }
        XCTAssertEqual(renderer.vertexBufferCount, 1)
    }

    func test_C_SCALE_02_framesInFlightShareAtMostThreeVertexBuffers() throws {
        let list = try hierarchyList()
        let expected = try render(list, with: try Renderer(device: device))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: 900, height: 900, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        nonisolated(unsafe) let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        descriptor.textureType = .type2DMultisample
        descriptor.sampleCount = Renderer.sampleCount
        nonisolated(unsafe) let samples = try XCTUnwrap(device.makeTexture(descriptor: descriptor))

        // Committed without waiting, as the preview does: a frame waits only for a buffer.
        nonisolated(unsafe) let renderer = renderer!
        nonisolated(unsafe) let textures = textures!
        let done = expectation(description: "every frame was committed")
        nonisolated(unsafe) var committed: [any MTLCommandBuffer] = []
        DispatchQueue.global().async {
            for _ in 0..<24 {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = samples
                pass.colorAttachments[0].resolveTexture = target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .multisampleResolve
                if let commands = try? renderer.commit(
                    list, textures: textures, style: .standard, to: pass, presenting: nil)
                {
                    committed.append(commands)
                }
            }
            committed.last?.waitUntilCompleted()
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(committed.count, 24)
        XCTAssertEqual(committed.filter { $0.status == .completed }.count, 24)
        XCTAssertLessThanOrEqual(renderer.vertexBufferCount, VertexBuffers.limit)
        // The buffers come back: an offscreen frame after them draws as a fresh renderer does.
        XCTAssertEqual(try render(list, with: renderer), expected)
    }

    func test_C_REND_01_aLongerListGrowsTheBufferAndDrawsAsAFreshRenderer() throws {
        let short = RenderFixtures.blendingList(
            red: TextureKey(layerID: 1, kind: .group, revision: 1),
            blue: TextureKey(layerID: 2, kind: .group, revision: 1))
        _ = try render(short, with: renderer)
        XCTAssertEqual(renderer.vertexBufferCount, 1)

        // Thousands of layers, more than the first buffer holds.
        let layers = (1...2_000).map { id in
            SceneLayer(
                id: UInt64(id), parentID: 0,
                bounds: SceneRect(x: 0, y: 0, width: 40, height: 40),
                position: ScenePoint(x: Double(id % 40) * 10, y: Double(id / 40) * 17),
                anchorPoint: .zero)
        }
        let long = RenderFixtures.layout(layers).project(
            camera: .flat, viewport: RenderFixtures.square, selected: 7, hovered: nil)
        let grown = try render(long, with: renderer)
        XCTAssertEqual(renderer.vertexBufferCount, 2)
        XCTAssertEqual(grown, try render(long, with: try Renderer(device: device)))

        // The grown buffer holds the short list too.
        XCTAssertEqual(try render(short, with: renderer), try render(short, with: try Renderer(device: device)))
        XCTAssertEqual(renderer.vertexBufferCount, 2)
    }
}
