import CutawayRender
import CutawayScene
import CutawayTestSupport
import Metal
import XCTest

/// C-SCALE-01 for drawing: 10,000 app-shaped layers (`ScaleScene`), every one expanded and
/// drawn with an image. A frame is the time the main thread spends encoding and committing it,
/// which is what holds up the interaction: the GPU's own work runs alongside and is short. The
/// time until the GPU is done is printed.
final class ScaleRenderTests: XCTestCase {
    func test_C_SCALE_01_aFrameOfTenThousandLayersTakesAtMostSixteenMilliseconds() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let hierarchy = try ScaleScene.hierarchy()
        let layers = SceneInput.layers(of: hierarchy)
        let all = Set(layers.map(\.id))
        // Each layer has the kind of image it is drawn with.
        let needs = SceneLayout(layers: layers, expanded: all).neededTextures
        var textures: [UInt64: LayerTextures] = [:]
        for need in needs {
            let key = TextureKey(layerID: need.layerID, kind: need.kind, revision: 1)
            textures[need.layerID] = need.kind == .solo ? LayerTextures(solo: key) : LayerTextures(group: key)
        }
        let layout = SceneLayout(
            layers: SceneInput.layers(of: hierarchy, textures: textures), expanded: all)
        let list = layout.project(
            camera: .standard3D, viewport: Viewport(width: 900, height: 900), selected: 5,
            hovered: nil)
        XCTAssertEqual(list.items.count, layers.count)
        XCTAssertTrue(list.items.allSatisfy { $0.texture != nil }, "every layer has its image")

        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        // The GPU of a virtual Mac, as on a CI runner, stops making small mipmapped textures
        // after a few thousand in a fresh process, and later textures fail with them: what it
        // can hold depends on what the process made before, so the frame cannot be timed there.
        try XCTSkipIf(
            device.name.contains("Paravirtual"),
            "\(device.name) cannot hold 10,000 mipmapped images reliably")
        let renderer = try Renderer(device: device)
        let cache = TextureCache(device: device)
        let pixels = Data(repeating: 0x80, count: 32 * 32 * 4)
        for item in list.items {
            let key = try XCTUnwrap(item.texture)
            cache.store(
                TextureImage(pixelWidth: 32, pixelHeight: 32, bytesPerRow: 128, bytes: pixels),
                for: key)
        }
        // A refused image would be drawn as an outline only, and the frame timed with less work.
        XCTAssertEqual(cache.refusedCount, 0, "every image is stored")
        // As the preview draws: several samples a pixel, resolved into the drawable.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: 1800, height: 1800, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        descriptor.textureType = .type2DMultisample
        descriptor.sampleCount = Renderer.sampleCount
        let samples = try XCTUnwrap(device.makeTexture(descriptor: descriptor))

        var untilDone: [Duration] = [], scheduling: [Duration] = [], onGPU: [Duration] = []
        let measured = try ScaleScene.median(of: 21) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = samples
            pass.colorAttachments[0].resolveTexture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .multisampleResolve
            let start = ContinuousClock.now
            let commands = try renderer.commit(
                list, textures: cache, style: .standard, to: pass, presenting: nil)
            let encoded = ContinuousClock.now - start
            commands.waitUntilCompleted()
            untilDone.append(ContinuousClock.now - start)
            // Host times in seconds: the driver scheduling the buffer, then the GPU running it.
            scheduling.append(.seconds(commands.kernelEndTime - commands.kernelStartTime))
            onGPU.append(.seconds(commands.gpuEndTime - commands.gpuStartTime))
            XCTAssertEqual(commands.status, .completed)
            return encoded
        }
        print("C-SCALE-01 frame, until the GPU is done: \(ScaleScene.milliseconds(untilDone.sorted()[10]))"
            + " (scheduling \(ScaleScene.milliseconds(scheduling.sorted()[10])),"
            + " on the GPU \(ScaleScene.milliseconds(onGPU.sorted()[10])))")
        let report = ScaleScene.report("frame", measured, limit: .milliseconds(16))
        if ScaleScene.checksLimits { XCTAssertLessThanOrEqual(measured, .milliseconds(16), report) }
    }
}
