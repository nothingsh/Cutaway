import CutawayScene
import CutawayWire

// `take(_:)`, `rebuildLayout()` and `swapTextures()` are internal only so that the other
// InspectionStore files can call them.
extension InspectionStore {
    // MARK: - Images

    /// Takes the images that came with layer details. A layer that is not in the tree is
    /// skipped. An `ok` detail replaces the kinds of image it brings and leaves the others;
    /// an image that does not decompress counts as not brought. A layer whose detail did not
    /// succeed has no image afterwards. A layer the app excludes from images is marked so in
    /// the tree with what is below it, and no longer asked for (C-DET-11). The images are decompressed away from the
    /// main thread
    /// first (C-DET-09). Publishes once, and not at all when nothing changed. Package for tests.
    package func applyDetails(_ details: [LayerDetail]) async {
        take(await ImageDecompression.decompress(details, using: decodeImage))
    }

    /// Takes decompressed details in, as `applyDetails(_:)` describes. Their pixels go out by
    /// `arrivingPixels`; only the compressed images are kept (C-DET-08). `images` changes in
    /// place, entry by entry: a chunk costs what its layers cost (C-SCALE-02).
    func take(_ decompressed: [ImageDecompression.DecompressedDetail]) {
        var changedIDs: [UInt64] = []
        var excludedIDs: [UInt64] = []
        var pixels: [TextureKey: Bitmap] = [:]
        for item in decompressed where tree.contains(item.detail.layerID) {
            let detail = item.detail
            let id = detail.layerID
            guard detail.status == .ok else {
                if images.removeValue(forKey: id) != nil { changedIDs.append(id) }
                // Not a failure: the layer leaves the needs below, and the round with them.
                if detail.status == .excluded {
                    excludedIDs.append(id)
                } else {
                    fetcher.scheduler.failed(id)
                }
                continue
            }
            var layerImages = images[id] ?? LayerImages()
            var layerChanged = false
            if let image = detail.solo, let bitmap = item.solo {
                let revision = takeRevision()
                layerImages.solo = RevisionedImage(revision: revision, image: image)
                pixels[TextureKey(layerID: id, kind: .solo, revision: revision)] = bitmap
                fetcher.scheduler.received(.solo, for: id)
                layerChanged = true
            }
            if let image = detail.group, let bitmap = item.group {
                let revision = takeRevision()
                layerImages.group = RevisionedImage(revision: revision, image: image)
                pixels[TextureKey(layerID: id, kind: .group, revision: revision)] = bitmap
                fetcher.scheduler.received(.group, for: id)
                layerChanged = true
            }
            if layerChanged {
                changedIDs.append(id)
                images[id] = layerImages
            }
            fetcher.scheduler.answered(id)
        }
        let marked = !excludedIDs.isEmpty && markCaptureExcluded(excludedIDs)
        if !changedIDs.isEmpty {
            if !pixels.isEmpty { arrivingPixelsSubject.send(pixels) }
            imagesChangedSubject.send(changedIDs)
            swapTextures(of: changedIDs)
        } else if marked {
            swapTextures()
        } else {
            publishProgress()
        }
    }

    /// Marks the layers excluded from images in the tree, with what is below them, and lays
    /// the tree out again: their needs go (C-DET-11). Whether the tree changed.
    private func markCaptureExcluded(_ ids: [UInt64]) -> Bool {
        let marked = tree.markingCaptureExcluded(ids)
        guard marked != tree else { return false }
        layOut(marked)
        tree = marked
        return true
    }

    /// The pixels of held images, decompressed again away from the main thread (C-DET-08,
    /// C-DET-09): for a preview that lacks their textures. A key whose image is not held
    /// under that revision, or does not decompress, is left out.
    public func pixels(for keys: [TextureKey]) async -> [TextureKey: Bitmap] {
        var held: [TextureKey: EncodedImage] = [:]
        for key in keys {
            held[key] = images[key.layerID]?.image(for: key)
        }
        return await ImageDecompression.decompress(held, using: decodeImage)
    }

    private func takeRevision() -> UInt64 {
        defer { nextImageRevision += 1 }
        return nextImageRevision
    }

    // MARK: - Layout

    /// Lays the tree out again, for a new expansion, and publishes it.
    func rebuildLayout() {
        layOut(tree)
        swapTextures()
    }

    /// Publishes the layout with the textures of the images held now, choosing again only
    /// those of `ids`: the images of the other layers are those the layout has. A chunk then
    /// costs what its layers cost (C-SCALE-02).
    private func swapTextures(of ids: [UInt64]) {
        guard layout.isSameBuild(as: geometry) else {
            swapTextures()
            return
        }
        var textures: [UInt64: LayerTextures] = [:]
        for id in ids { textures[id] = images[id]?.textures(layerID: id) }
        layout = layout.replacingTextures(textures, of: ids)
        publishProgress()
    }

    /// Publishes the layout with the textures of the images held now.
    func swapTextures() {
        layout = geometry.replacingTextures(
            Dictionary(
                uniqueKeysWithValues: images.map { ($0.key, $0.value.textures(layerID: $0.key)) }))
        publishProgress()
    }
}
