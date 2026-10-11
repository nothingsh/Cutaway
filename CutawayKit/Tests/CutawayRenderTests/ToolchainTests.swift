import CutawayRender
import Metal
import XCTest

/// Toolchain probe: `swift test` compiles the package's Metal shaders, loads them in the test
/// process and renders offscreen.
final class ToolchainTests: XCTestCase {
    func test_M0_H1_swiftTestRendersOffscreenWithPackagedShaders() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try ShaderLibrary.make(device: device)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = try XCTUnwrap(library.makeFunction(name: "probeVertex"))
        pipelineDescriptor.fragmentFunction = try XCTUnwrap(library.makeFunction(name: "probeFragment"))
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        let side = 4
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: textureDescriptor))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        texture.getBytes(
            &pixels, bytesPerRow: side * 4,
            from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)

        // The probe shader outputs (red 1, green 0.5, blue 0, alpha 1); the texture is BGRA.
        // The clear colour is black, so a pass that drew nothing fails on red and green.
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            XCTAssertEqual(Int(pixels[offset]), 0, accuracy: 2, "blue at byte \(offset)")
            XCTAssertEqual(Int(pixels[offset + 1]), 128, accuracy: 2, "green at byte \(offset)")
            XCTAssertEqual(Int(pixels[offset + 2]), 255, accuracy: 2, "red at byte \(offset)")
            XCTAssertEqual(Int(pixels[offset + 3]), 255, accuracy: 2, "alpha at byte \(offset)")
        }
    }
}
