import CutawayWire

/// Decompressing the images of layer details away from the main thread (C-DET-09).
enum ImageDecompression {
    /// A detail and its images decompressed; nil for one that did not decompress.
    struct DecompressedDetail: Sendable {
        var detail: LayerDetail
        var solo: Bitmap?
        var group: Bitmap?
    }

    /// Decompresses the images of the `ok` details, all at once, away from the main thread.
    nonisolated static func decompress(
        _ details: [LayerDetail], using decode: @escaping @Sendable (EncodedImage) throws -> Bitmap
    ) async -> [DecompressedDetail] {
        var images: [Int: EncodedImage] = [:]
        for (index, detail) in details.enumerated() where detail.status == .ok {
            images[2 * index] = detail.solo
            images[2 * index + 1] = detail.group
        }
        let pixels = await decompress(images, using: decode)
        return details.enumerated().map { index, detail in
            DecompressedDetail(
                detail: detail, solo: pixels[2 * index], group: pixels[2 * index + 1])
        }
    }

    /// Decompresses images side by side, away from the main thread. An image that does not
    /// decompress is left out. Cancelled, it starts no more images: a cancelled batch is not
    /// kept waiting for the rest of its chunk.
    nonisolated static func decompress<Key: Hashable & Sendable>(
        _ images: [Key: EncodedImage],
        using decode: @escaping @Sendable (EncodedImage) throws -> Bitmap
    ) async -> [Key: Bitmap] {
        guard !images.isEmpty else { return [:] }
        let work = Task.detached {
            await withTaskGroup(of: (Key, Bitmap?).self) { group in
                for (key, image) in images {
                    group.addTask { (key, Task.isCancelled ? nil : try? decode(image)) }
                }
                var result: [Key: Bitmap] = [:]
                for await (key, bitmap) in group {
                    result[key] = bitmap
                }
                return result
            }
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }
}
