import Compression
import CutawayWire
import Foundation

/// Decompresses images as the app does, and keeps count of what it handed out (C-DET-08,
/// C-DET-09): the calls, the ones made on the main thread, and the decompressed pixels that
/// are still alive. Each result's pixels live in memory of its own, which is counted free
/// once the last `Data` sharing it goes.
public final class PixelTracker: Sendable {
    private struct Counts {
        var calls = 0
        var mainThreadCalls = 0
        var live = 0
    }

    private let counts = Locked(Counts())

    public init() {}

    public var callCount: Int { counts.withLock { $0.calls } }
    public var mainThreadCallCount: Int { counts.withLock { $0.mainThreadCalls } }
    /// How many decompressed images are still held somewhere.
    public var liveCount: Int { counts.withLock { $0.live } }

    public func decode(_ image: EncodedImage) throws -> Bitmap {
        let onMain = pthread_main_np() != 0
        counts.withLock {
            $0.calls += 1
            if onMain { $0.mainThreadCalls += 1 }
        }
        var bitmap = try image.decoded()
        let count = bitmap.pixels.count
        guard count > 0 else { return bitmap }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        bitmap.pixels.copyBytes(to: memory.assumingMemoryBound(to: UInt8.self), count: count)
        counts.withLock { $0.live += 1 }
        bitmap.pixels = Data(
            bytesNoCopy: memory, count: count,
            deallocator: .custom { [counts] pointer, _ in
                pointer.deallocate()
                counts.withLock { $0.live -= 1 }
            })
        return bitmap
    }
}

/// A lock around a value, for test doubles used from several threads.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

extension EncodedImage {
    /// An image that decompresses: `pixelWidth` × `pixelHeight` opaque pixels in a gradient
    /// that `seed` shifts, LZFSE-compressed (P-IMG-01). A 2048 × 2048 one is 16 MiB of pixels
    /// in about 1.7 MiB of data.
    public static func gradient(pixelWidth: Int, pixelHeight: Int, seed: Int = 0) -> EncodedImage {
        let byteCount = pixelWidth * pixelHeight * 4
        var pixels = Data(count: byteCount)
        pixels.withUnsafeMutableBytes { raw in
            let words = raw.bindMemory(to: UInt32.self)
            for y in 0..<pixelHeight {
                for x in 0..<pixelWidth {
                    let blue = UInt32((x + seed) & 255)
                    let green = UInt32((y + seed) & 255)
                    let red = UInt32((x ^ y) & 255)
                    words[y * pixelWidth + x] = 0xFF00_0000 | red << 16 | green << 8 | blue
                }
            }
        }
        return compressed(pixels, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    /// An image of one colour: `pixelWidth` × `pixelHeight` pixels of `bgra` (blue in the
    /// lowest byte, premultiplied), LZFSE-compressed (P-IMG-01).
    public static func solid(pixelWidth: Int, pixelHeight: Int, bgra: UInt32) -> EncodedImage {
        var pixels = Data(count: pixelWidth * pixelHeight * 4)
        pixels.withUnsafeMutableBytes { raw in
            let words = raw.bindMemory(to: UInt32.self)
            for index in words.indices { words[index] = bgra.littleEndian }
        }
        return compressed(pixels, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    private static func compressed(_ pixels: Data, pixelWidth: Int, pixelHeight: Int) -> EncodedImage {
        let byteCount = pixels.count
        var data = Data(count: byteCount + 4096)
        let written = data.withUnsafeMutableBytes { destination in
            pixels.withUnsafeBytes { source in
                guard let output = destination.bindMemory(to: UInt8.self).baseAddress,
                      let input = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_encode_buffer(
                    output, destination.count, input, byteCount, nil, COMPRESSION_LZFSE)
            }
        }
        data.count = written
        return EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: UInt32(pixelWidth),
            pixelHeight: UInt32(pixelHeight), bytesPerRow: UInt32(pixelWidth * 4), scale: 1,
            data: data)
    }
}
