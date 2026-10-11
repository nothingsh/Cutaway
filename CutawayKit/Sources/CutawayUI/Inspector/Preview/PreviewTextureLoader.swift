import CutawayModel
import CutawayRender
import CutawayScene
import CutawayWire

/// The preview's textures: it uploads arriving pixels, keeps the textures of the images
/// drawn and drops the rest, and asks the store for the pixels of drawn images it lacks
/// (C-DET-08, C-SCALE-02).
@MainActor
final class PreviewTextureLoader {
    private let store: InspectionStore
    private let textures: TextureCache
    /// Called when pixels that came late were uploaded: new textures are new content
    /// (C-REND-04).
    private let onLateTextures: @MainActor () -> Void
    /// Keys of images the texture cache refused; they are not offered again.
    private var refused = Set<TextureKey>()
    /// The keys of the images drawn: by the layout, or by any frame of the transition under
    /// way. The preview keeps their textures and no others (C-SCALE-02).
    private var drawnKeys = Set<TextureKey>()
    /// Keys of drawn images the preview lacked, whose pixels the store is decompressing.
    private var decompressing = Set<TextureKey>()
    /// The tasks that bring those pixels, by a number of their own.
    private var lateUploads: [UInt64: Task<Void, Never>] = [:]
    private var nextLateUpload: UInt64 = 0

    init(
        store: InspectionStore, textures: TextureCache,
        onLateTextures: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.textures = textures
        self.onLateTextures = onLateTextures
    }

    /// Uploads pixels the preview does not have a texture of yet, and keeps nothing of them
    /// (C-DET-08). An image the texture cache refused is not offered again. Returns whether a
    /// texture was stored. Arriving pixels come before the layout that draws them, so they
    /// are all uploaded; the layout that follows drops those it does not draw.
    @discardableResult
    func upload(_ pixels: [TextureKey: Bitmap]) -> Bool {
        var stored = false
        for (key, bitmap) in pixels {
            guard textures.texture(for: key) == nil, !refused.contains(key) else {
                continue
            }
            if textures.store(TextureImage(bitmap), for: key) {
                stored = true
            } else {
                refused.insert(key)
            }
        }
        return stored
    }

    /// Forgets that the cache refused images of `ids` the store no longer holds: a new image
    /// of the same layer has a new key anyway.
    func follow(changedLayers ids: [UInt64]) {
        // Most of the time nothing was refused: then a chunk costs nothing here (C-SCALE-02).
        guard !refused.isEmpty else { return }
        let changed = Set(ids)
        refused = refused.filter {
            !changed.contains($0.layerID) || store.images[$0.layerID]?.image(for: $0) != nil
        }
    }

    /// Keeps the textures of the images drawn, still or in the transition under way, and
    /// drops the rest (C-SCALE-02). For drawn images the preview has no texture of (held
    /// before the preview was made, or dropped when their layers were last not drawn), it asks
    /// the store for the pixels (C-DET-08); until they come, their layers are drawn without
    /// them. Not for every projection: the camera, the selection and the hover draw nothing
    /// else.
    func keepDrawnTextures(_ drawn: Set<TextureKey>) {
        drawnKeys = drawn
        textures.retain(only: drawn)
        let lacking = drawn.filter {
            textures.texture(for: $0) == nil && !refused.contains($0)
                && !decompressing.contains($0)
        }
        guard !lacking.isEmpty else { return }
        decompressing.formUnion(lacking)
        let number = nextLateUpload
        nextLateUpload += 1
        lateUploads[number] = Task { [weak self, store] in
            let pixels = await store.pixels(for: Array(lacking))
            guard let self else { return }
            self.lateUploads[number] = nil
            self.decompressing.subtract(lacking)
            let wanted = lacking.filter(self.drawnKeys.contains)
            // Drawn, so held, and still not there: it does not decompress.
            self.refused.formUnion(wanted.filter { pixels[$0] == nil })
            // New textures are new content (C-REND-04).
            if self.upload(pixels.filter { wanted.contains($0.key) }) {
                self.onLateTextures()
            }
        }
    }

    /// Returns once the pixels asked for so far are uploaded.
    func settled() async {
        while let task = lateUploads.values.first {
            await task.value
        }
    }
}
