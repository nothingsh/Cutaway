import CutawayScene
import Foundation
import Metal

/// Pixels for a texture: premultiplied BGRA, 8 bits per channel, sRGB, rows top to bottom
/// (P-IMG-01). Rows may carry padding beyond `pixelWidth * 4` bytes (P-IMG-02).
public struct TextureImage: Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var bytesPerRow: Int
    /// `bytesPerRow * pixelHeight` bytes.
    public var bytes: Data

    public init(pixelWidth: Int, pixelHeight: Int, bytesPerRow: Int, bytes: Data) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.bytes = bytes
    }
}

/// The textures of the layers' images, by the key the draw list names them with.
public final class TextureCache {
    private let device: any MTLDevice
    /// `Renderer.maxTextureDimension(of:)` of the device.
    private let longestSide: Int
    private var textures: [TextureKey: any MTLTexture] = [:]
    /// Stored textures whose smaller levels are not made yet: the next frame makes them
    /// before it draws (`encodeMipmaps(into:)`).
    private var unfinished: [any MTLTexture] = []

    /// How many images `store` refused.
    public private(set) var refusedCount = 0

    public init(device: any MTLDevice) {
        self.device = device
        self.longestSide = Renderer.maxTextureDimension(of: device)
    }

    public var count: Int { textures.count }

    /// The keys of the textures held.
    public var keys: Set<TextureKey> { Set(textures.keys) }

    public func texture(for key: TextureKey) -> (any MTLTexture)? {
        textures[key]
    }

    /// Makes a texture of the image. An image without pixels, one larger than a texture can
    /// be, or one whose bytes fall short of its size is not stored: its layer is drawn
    /// without an image. Returns whether the image was stored.
    @discardableResult
    public func store(_ image: TextureImage, for key: TextureKey) -> Bool {
        // A size that does not fit in an Int is refused, not trapped on.
        let (needed, overflows) = image.bytesPerRow.multipliedReportingOverflow(
            by: image.pixelHeight)
        guard image.pixelWidth > 0, image.pixelHeight > 0,
              image.pixelWidth <= longestSide, image.pixelHeight <= longestSide,
              image.bytesPerRow >= image.pixelWidth * 4,
              !overflows, image.bytes.count >= needed
        else {
            return refuse(key)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: image.pixelWidth,
            height: image.pixelHeight, mipmapped: true)
        descriptor.usage = .shaderRead
        descriptor.storageMode = Renderer.cpuAccessibleStorage(on: device)
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return refuse(key)
        }
        image.bytes.withUnsafeBytes { raw in
            guard let bytes = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, image.pixelWidth, image.pixelHeight),
                mipmapLevel: 0, withBytes: bytes, bytesPerRow: image.bytesPerRow)
        }
        textures[key] = texture
        if texture.mipmapLevelCount > 1 { unfinished.append(texture) }
        return true
    }

    /// Makes the smaller levels of the textures stored since the last call, in `commands`
    /// ahead of the drawing: a shrunken image is then averaged instead of showing moiré.
    func encodeMipmaps(into commands: any MTLCommandBuffer) {
        guard !unfinished.isEmpty, let blit = commands.makeBlitCommandEncoder() else { return }
        for texture in unfinished { blit.generateMipmaps(for: texture) }
        blit.endEncoding()
        unfinished = []
    }

    private func refuse(_ key: TextureKey) -> Bool {
        textures[key] = nil
        refusedCount += 1
        return false
    }

    /// Drops every texture whose key is not in `keys`.
    public func retain(only keys: Set<TextureKey>) {
        textures = textures.filter { keys.contains($0.key) }
        let kept = Set(textures.values.map { ObjectIdentifier($0) })
        unfinished.removeAll { !kept.contains(ObjectIdentifier($0)) }
    }
}
