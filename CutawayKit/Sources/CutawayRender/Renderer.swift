import CutawayScene
import Foundation
import Metal

public enum RenderError: Error, Equatable {
    case missingShader(String)
    case noCommandQueue
    case noTarget
    case invalidSize(width: Int, height: Int)
    case gpu(String)
}

/// Draws a draw list with Metal. It makes no decision about what is drawn or where: the
/// scene has made them. Each item gets its image, then its highlight's tint, then its border,
/// in the order of the list, without a depth buffer and without culling (mirrored layers and
/// layers seen from behind wind the other way). The marks come after every item: the
/// layout guides' tints and dashed borders, then the views' borders (C-REND-07). A
/// measurement comes last: solid lines, then dashed ones, then dotted ones (C-REND-08,
/// C-REND-09).
public final class Renderer {
    /// The format of every texture and render target: 8-bit BGRA, without sRGB conversion,
    /// so that blending works on the stored values (C-REND-02).
    public static let pixelFormat = MTLPixelFormat.bgra8Unorm

    /// Samples per pixel. Edges, the borders' lines above all, are smoothed instead of
    /// stepping from pixel to pixel; every Mac GPU supports 4.
    public static let sampleCount = 4

    /// How to store a texture the CPU writes or reads. Shared storage for textures needs an
    /// Apple-family GPU; Intel GPUs report unified memory too but take only managed storage,
    /// which must be synchronized before the CPU reads it back.
    static func cpuAccessibleStorage(on device: any MTLDevice) -> MTLStorageMode {
        device.supportsFamily(.apple7) ? .shared : .managed
    }

    /// The longest side of a 2D texture on `device`, from Apple's Metal feature set tables:
    /// 16,384 on the Apple3 family and later and on the Mac2 family, 8,192 before that. The
    /// inspection asks the app for images no larger than this (C-REND-05, P-DET-05).
    public static func maxTextureDimension(of device: any MTLDevice) -> Int {
        device.supportsFamily(.apple3) || device.supportsFamily(.mac2) ? 16_384 : 8_192
    }

    /// One corner as the shaders read it; matches `LayerVertex` in Preview.metal.
    private struct Vertex {
        var position: SIMD4<Float>
        var uv: SIMD2<Float>
    }

    /// How lines are placed; matches `LineSettings` in Preview.metal.
    private struct LineSettings {
        var halfTarget: SIMD2<Float>
        var halfWidth: Float
        var snaps: UInt32
        var closed: UInt32
    }

    /// An excluded layer's stripes; matches `HatchSettings` in Preview.metal.
    private struct HatchSettings {
        var color: SIMD4<Float>
        var alternate: SIMD4<Float>
        var width: Float
        var opacity: Float
    }

    /// Per item and per mark: four corners as a triangle strip, then eight ends of the four
    /// border lines.
    private static let verticesPerItem = 12

    public let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let texturePipeline: any MTLRenderPipelineState
    private let colorPipeline: any MTLRenderPipelineState
    private let linePipeline: any MTLRenderPipelineState
    private let dashPipeline: any MTLRenderPipelineState
    private let dotPipeline: any MTLRenderPipelineState
    private let hatchPipeline: any MTLRenderPipelineState
    private let sampler: any MTLSamplerState

    public init(device: any MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RenderError.noCommandQueue }
        self.queue = queue
        let library = try ShaderLibrary.make(device: device)
        texturePipeline = try Self.pipeline(device, library, fragment: "layerTextureFragment")
        colorPipeline = try Self.pipeline(device, library, fragment: "layerColorFragment")
        linePipeline = try Self.pipeline(
            device, library, vertex: "lineVertex", fragment: "lineFragment")
        dashPipeline = try Self.pipeline(
            device, library, vertex: "lineVertex", fragment: "dashFragment")
        dotPipeline = try Self.pipeline(
            device, library, vertex: "lineVertex", fragment: "dotFragment")
        hatchPipeline = try Self.pipeline(device, library, fragment: "hatchFragment")

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        // A layer seen from the side is shrunk far more across than down: without this the
        // level chosen for across blurs it down too.
        samplerDescriptor.maxAnisotropy = 16
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RenderError.gpu("no sampler")
        }
        self.sampler = sampler
    }

    private static func pipeline(
        _ device: any MTLDevice, _ library: any MTLLibrary, vertex: String = "layerVertex",
        fragment: String
    ) throws -> any MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex) else {
            throw RenderError.missingShader(vertex)
        }
        guard let fragmentFunction = library.makeFunction(name: fragment) else {
            throw RenderError.missingShader(fragment)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = sampleCount
        let attachment: MTLRenderPipelineColorAttachmentDescriptor = descriptor.colorAttachments[0]
        attachment.pixelFormat = pixelFormat
        // Premultiplied "over": source + destination × (1 − source alpha).
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Encodes the list into a pass whose colour target has `Renderer.pixelFormat` and is
    /// `width` × `height` pixels. Throws when the GPU cannot take the vertices; the caller
    /// still ends the encoder.
    private func encode(
        _ list: DrawList, textures: TextureCache, style: RenderStyle, width: Int, height: Int,
        into encoder: any MTLRenderCommandEncoder
    ) throws {
        guard !list.items.isEmpty || !list.marks.isEmpty || list.measurement != nil else {
            return
        }
        let solid = list.measurement?.lines ?? [], dashes = list.measurement?.dashes ?? []
        let dots = list.measurement?.links ?? []
        let count = (list.items.count + list.marks.count) * Self.verticesPerItem
            + 2 * (solid.count + dashes.count + dots.count)
        // Written in place: building an array first and copying it took most of a frame
        // with thousands of layers.
        guard let buffer = device.makeBuffer(
            length: MemoryLayout<Vertex>.stride * count, options: .storageModeShared)
        else { throw RenderError.gpu("no vertex buffer") }
        var vertices = VertexWriter(
            buffer.contents().bindMemory(to: Vertex.self, capacity: count))
        for item in list.items {
            // A virtual node's border is dashed: its ends carry their distances.
            Self.appendVertices(
                item.corners, points: item.content == .drawnByParent ? item.points : nil,
                to: &vertices)
        }
        for mark in list.marks {
            Self.appendVertices(mark.corners, points: mark.points, to: &vertices)
        }
        for segment in solid + dashes + dots {
            Self.appendVertices(segment, to: &vertices)
        }
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        // The lines are placed in pixels around their ends (Preview.metal), as wide as the style
        // says in the list's viewport points.
        let pixelsPerPoint = list.viewport.map {
            $0.width > 0 ? Float(Double(width) / $0.width) : 1
        } ?? 1
        // Borders and marks go round their quads; the measurement's lines stand alone.
        var lines = LineSettings(
            halfTarget: SIMD2(Float(width) / 2, Float(height) / 2),
            halfWidth: style.lineWidth * pixelsPerPoint / 2, snaps: list.facesSquareOn ? 1 : 0,
            closed: 1)
        encoder.setVertexBytes(&lines, length: MemoryLayout<LineSettings>.stride, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        // The borders step back while something is pointed out (C-PREV-17).
        let receding = !list.marks.isEmpty || list.measurement != nil
        encodeItems(
            list.items, textures: textures, style: style, receding: receding,
            pixelsPerPoint: pixelsPerPoint, into: encoder)
        let marksStart = list.items.count * Self.verticesPerItem
        var markLines = lines
        markLines.halfWidth = style.markLineWidth * pixelsPerPoint / 2
        encodeMarks(
            list.marks, from: marksStart, style: style, lines: markLines,
            pixelsPerPoint: pixelsPerPoint, into: encoder)

        // The measurement over everything: solid lines, then the dashed extensions and copy,
        // then the dotted links.
        let measurementStart = marksStart + list.marks.count * Self.verticesPerItem
        var measure = style.measure
        lines.closed = 0
        encoder.setVertexBytes(&lines, length: MemoryLayout<LineSettings>.stride, index: 1)
        if !solid.isEmpty {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setFragmentBytes(&measure, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            Self.drawLines(from: measurementStart, count: solid.count, into: encoder)
        }
        if !dashes.isEmpty {
            encoder.setRenderPipelineState(dashPipeline)
            encoder.setFragmentBytes(&measure, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            Self.drawLines(from: measurementStart + 2 * solid.count, count: dashes.count, into: encoder)
        }
        if !dots.isEmpty {
            encoder.setRenderPipelineState(dotPipeline)
            encoder.setFragmentBytes(&measure, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            Self.drawLines(
                from: measurementStart + 2 * (solid.count + dashes.count), count: dots.count,
                into: encoder)
        }
    }

    /// The layers' images (or an excluded layer's stripes), fills and borders, whose vertices
    /// come first. A virtual node has no image and a dashed border unless highlighted
    /// (C-REND-11).
    private func encodeItems(
        _ items: [DrawItem], textures: TextureCache, style: RenderStyle, receding: Bool,
        pixelsPerPoint: Float, into encoder: any MTLRenderCommandEncoder
    ) {
        // The state is set only when it changes: with thousands of layers, setting it for
        // each one costs more than drawing them.
        var current: (any MTLRenderPipelineState)?
        func use(_ pipeline: any MTLRenderPipelineState) {
            guard current !== pipeline else { return }
            encoder.setRenderPipelineState(pipeline)
            current = pipeline
        }
        for (index, item) in items.enumerated() {
            let first = index * Self.verticesPerItem
            if let key = item.texture, let texture = textures.texture(for: key) {
                use(texturePipeline)
                encoder.setFragmentTexture(texture, index: 0)
                var opacity = style.imageOpacity(for: item)
                encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: first, vertexCount: 4)
            } else if item.content == .excluded {
                use(hatchPipeline)
                var hatch = HatchSettings(
                    color: style.hatch, alternate: style.hatchAlternate,
                    width: style.hatchWidth * pixelsPerPoint, opacity: style.imageOpacity(for: item))
                encoder.setFragmentBytes(&hatch, length: MemoryLayout<HatchSettings>.stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: first, vertexCount: 4)
            }
            if var fill = style.fill(for: item) {
                use(colorPipeline)
                encoder.setFragmentBytes(&fill, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: first, vertexCount: 4)
            }
            if var border = style.border(for: item, receding: receding) {
                use(item.content == .drawnByParent && item.highlight == .none ? dashPipeline : linePipeline)
                encoder.setFragmentBytes(
                    &border, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
                Self.drawLines(from: first + 4, count: 4, into: encoder)
            }
        }
    }

    /// The views' faint tints first, then the guides' tints and their dashes, so that no tint
    /// lies over a dash; the views' borders last, as wide as `lines` says, and a stressed
    /// view's wider (C-LAYOUT-06). Each in its colour for its emphasis. The marks' vertices
    /// start at `marksStart`.
    private func encodeMarks(
        _ marks: [DrawMark], from marksStart: Int, style: RenderStyle, lines: LineSettings,
        pixelsPerPoint: Float, into encoder: any MTLRenderCommandEncoder
    ) {
        let guides = marks.indices.filter {
            if case .area = marks[$0].mark { true } else { false }
        }
        let views = marks.indices.filter {
            if case .layer = marks[$0].mark { true } else { false }
        }
        func setColor(_ color: SIMD4<Float>, _ index: Int, isEdge: Bool) {
            var color = style.markColor(color, marks[index].emphasis, isEdge: isEdge)
            encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        }
        encoder.setRenderPipelineState(colorPipeline)
        for index in views {
            setColor(style.endFill, index, isEdge: false)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: marksStart + index * Self.verticesPerItem,
                vertexCount: 4)
        }
        for index in guides {
            setColor(style.guideFill, index, isEdge: false)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: marksStart + index * Self.verticesPerItem,
                vertexCount: 4)
        }
        encoder.setRenderPipelineState(dashPipeline)
        for index in guides {
            setColor(style.guideBorder, index, isEdge: true)
            Self.drawLines(from: marksStart + index * Self.verticesPerItem + 4, count: 4, into: encoder)
        }
        guard !views.isEmpty else { return }
        encoder.setRenderPipelineState(linePipeline)
        for index in views {
            var lines = lines
            if marks[index].emphasis == .emphasized {
                lines.halfWidth = style.emphasizedMarkLineWidth * pixelsPerPoint / 2
            }
            encoder.setVertexBytes(&lines, length: MemoryLayout<LineSettings>.stride, index: 1)
            setColor(style.endBorder, index, isEdge: true)
            Self.drawLines(from: marksStart + index * Self.verticesPerItem + 4, count: 4, into: encoder)
        }
    }

    /// The lines whose ends start at `vertex`, one instance each.
    private static func drawLines(
        from vertex: Int, count: Int, into encoder: any MTLRenderCommandEncoder
    ) {
        encoder.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count,
            baseInstance: vertex / 2)
    }

    /// The two ends of a line; the second carries its distance in viewport points from the
    /// first, for the dashes.
    private static func appendVertices(_ segment: DrawSegment, to vertices: inout VertexWriter) {
        func position(_ p: ClipPoint) -> SIMD4<Float> {
            SIMD4(Float(p.x), Float(p.y), Float(p.z), Float(p.w))
        }
        let dx = segment.to.x - segment.from.x, dy = segment.to.y - segment.from.y
        vertices.append(Vertex(position: position(segment.clipFrom), uv: .zero))
        vertices.append(
            Vertex(
                position: position(segment.clipTo),
                uv: SIMD2(Float((dx * dx + dy * dy).squareRoot()), 0)))
    }

    /// Four corners as a triangle strip with the image's corners, then the ends of the border
    /// lines. With `points`, each end carries its distance in viewport points from the start
    /// of its line, for the dashes.
    private static func appendVertices(
        _ corners: Corners<ClipPoint>, points: Corners<ScenePoint>?,
        to vertices: inout VertexWriter
    ) {
        func position(_ p: ClipPoint) -> SIMD4<Float> {
            SIMD4(Float(p.x), Float(p.y), Float(p.z), Float(p.w))
        }
        let c0 = position(corners.topLeft), c1 = position(corners.topRight)
        let c2 = position(corners.bottomLeft), c3 = position(corners.bottomRight)
        // Top left, top right, bottom left, bottom right: a triangle strip.
        vertices.append(Vertex(position: c0, uv: SIMD2(0, 0)))
        vertices.append(Vertex(position: c1, uv: SIMD2(1, 0)))
        vertices.append(Vertex(position: c2, uv: SIMD2(0, 1)))
        vertices.append(Vertex(position: c3, uv: SIMD2(1, 1)))
        // The border: top, right, bottom, left.
        func length(_ from: Int, _ to: Int) -> Float {
            guard let points else { return 0 }
            let dx = points[to].x - points[from].x, dy = points[to].y - points[from].y
            return Float((dx * dx + dy * dy).squareRoot())
        }
        vertices.append(Vertex(position: c0, uv: .zero))
        vertices.append(Vertex(position: c1, uv: SIMD2(length(0, 1), 0)))
        vertices.append(Vertex(position: c1, uv: .zero))
        vertices.append(Vertex(position: c3, uv: SIMD2(length(1, 3), 0)))
        vertices.append(Vertex(position: c3, uv: .zero))
        vertices.append(Vertex(position: c2, uv: SIMD2(length(3, 2), 0)))
        vertices.append(Vertex(position: c2, uv: .zero))
        vertices.append(Vertex(position: c0, uv: SIMD2(length(2, 0), 0)))
    }

    /// Writes vertices one after another into a buffer's memory.
    private struct VertexWriter {
        let base: UnsafeMutablePointer<Vertex>
        var count = 0

        init(_ base: UnsafeMutablePointer<Vertex>) {
            self.base = base
        }

        mutating func append(_ vertex: Vertex) {
            (base + count).initialize(to: vertex)
            count += 1
        }
    }

    /// Draws the list into a render pass with this renderer's queue, presents the drawable
    /// if there is one, and commits. The pass decides the target and how it is cleared.
    @discardableResult
    public func commit(
        _ list: DrawList, textures: TextureCache, style: RenderStyle,
        to pass: MTLRenderPassDescriptor, presenting drawable: (any MTLDrawable)?
    ) throws -> any MTLCommandBuffer {
        guard let target = pass.colorAttachments[0].texture else { throw RenderError.noTarget }
        guard let commands = queue.makeCommandBuffer() else {
            throw RenderError.gpu("no command buffer")
        }
        textures.encodeMipmaps(into: commands)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            throw RenderError.gpu("no command buffer")
        }
        do {
            try encode(
                list, textures: textures, style: style, width: target.width,
                height: target.height, into: encoder)
        } catch {
            // An encoder has to be ended before it goes away.
            encoder.endEncoding()
            throw error
        }
        encoder.endEncoding()
        if let drawable { commands.present(drawable) }
        commands.commit()
        return commands
    }

    /// Draws the list into an offscreen target of this many pixels and reads it back. The
    /// list is in clip space, so any pixel size works: twice the viewport's points for a
    /// Retina snapshot.
    public func renderImage(
        _ list: DrawList, textures: TextureCache, style: RenderStyle, pixelWidth: Int,
        pixelHeight: Int
    ) throws -> RenderedImage {
        let longest = Self.maxTextureDimension(of: device)
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth <= longest, pixelHeight <= longest
        else {
            throw RenderError.invalidSize(width: pixelWidth, height: pixelHeight)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: pixelWidth, height: pixelHeight,
            mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = Self.cpuAccessibleStorage(on: device)
        let managed = descriptor.storageMode == .managed
        // Drawn with several samples a pixel, as on screen, then resolved into the target.
        let samples = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: pixelWidth, height: pixelHeight,
            mipmapped: false)
        samples.textureType = .type2DMultisample
        samples.sampleCount = Self.sampleCount
        samples.usage = .renderTarget
        samples.storageMode = .private
        guard let target = device.makeTexture(descriptor: descriptor),
              let sampled = device.makeTexture(descriptor: samples)
        else {
            throw RenderError.noTarget
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = sampled
        pass.colorAttachments[0].resolveTexture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = style.clearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve

        guard let commands = queue.makeCommandBuffer() else {
            throw RenderError.gpu("no command buffer")
        }
        textures.encodeMipmaps(into: commands)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            throw RenderError.gpu("no command buffer")
        }
        do {
            try encode(
                list, textures: textures, style: style, width: pixelWidth, height: pixelHeight,
                into: encoder)
        } catch {
            // An encoder has to be ended before it goes away.
            encoder.endEncoding()
            throw error
        }
        encoder.endEncoding()
        if managed, let blit = commands.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        commands.commit()
        commands.waitUntilCompleted()
        if let error = commands.error { throw RenderError.gpu(error.localizedDescription) }

        var bytes = Data(count: pixelWidth * pixelHeight * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let pixels = raw.baseAddress else { return }
            target.getBytes(
                pixels, bytesPerRow: pixelWidth * 4,
                from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0)
        }
        return RenderedImage(pixelWidth: pixelWidth, pixelHeight: pixelHeight, bytes: bytes)
    }
}

/// Loads the shaders that the build compiles into this module's resource bundle.
public enum ShaderLibrary {
    public static func make(device: any MTLDevice) throws -> any MTLLibrary {
        try device.makeDefaultLibrary(bundle: .module)
    }
}
