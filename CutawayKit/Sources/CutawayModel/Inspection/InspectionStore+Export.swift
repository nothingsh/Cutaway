import CutawayScene
import CutawayTransport
import CutawayWire
import Foundation

/// Why a layer's screenshot was not exported (C-ARCH-06).
public enum ScreenshotExportFailure: Error, Equatable, Sendable {
    /// The layer is not in the app any more (P-DET-02).
    case layerGone
    /// The app could not capture it, or sent no such image (P-DET-03).
    case notCaptured
    case appNotActive
    case disconnected
    case other
    /// The text is the system's reason.
    case writeFailed(String)
}

/// Where exporting a screenshot stands (C-ARCH-06). A finished export leaves no state.
public enum ScreenshotExportState: Equatable, Sendable {
    case idle
    case exporting
    /// Stays until dismissed.
    case failed(ScreenshotExportFailure)
}

/// Gets a layer's image for export and writes it (C-ARCH-06), away from the main thread.
enum ScreenshotExporter {
    /// A layer's image: `held`, the one the preview holds, decompressed again (C-DET-08);
    /// else asked of `source` on its own, and not taken into the preview. A `solo` that
    /// does not come is the `group` (P-DET-04).
    static func image(
        of id: UInt64, kind: TextureKey.Kind, held: EncodedImage?, from source: any InspectionSource,
        maxTextureDimension: UInt32, decode: @escaping @Sendable (EncodedImage) throws -> Bitmap
    ) async throws(ScreenshotExportFailure) -> Bitmap {
        if let held {
            guard let bitmap = await ImageDecompression.decompress([0: held], using: decode)[0]
            else { throw .notCaptured }
            return bitmap
        }
        let request = GetLayerDetails(
            requests: [LayerDetailRequest(
                layerID: id, wantSolo: kind == .solo, wantGroup: true, wantAttributes: false)],
            maxTextureDimension: maxTextureDimension)
        var detail: LayerDetail?
        do {
            for try await chunk in await source.layerDetails(request).chunks {
                detail = chunk.first { $0.layerID == id } ?? detail
            }
        } catch {
            switch error as? RequestError {
            case .appNotActive: throw .appNotActive
            case .disconnected, .timedOut: throw .disconnected
            case .layerNotFound: throw .layerGone
            default: throw .other
            }
        }
        guard let detail else { throw .other }
        switch detail.status {
        case .layerNotFound: throw .layerGone
        case .captureFailed: throw .notCaptured
        case .ok: break
        }
        let image = kind == .solo ? detail.solo ?? detail.group : detail.group
        guard let image, let bitmap = await ImageDecompression.decompress([0: image], using: decode)[0]
        else { throw .notCaptured }
        return bitmap
    }

    /// Encodes the image with `encode` and writes it to `url` in one piece, away from the
    /// main thread.
    static func write(
        _ bitmap: Bitmap, to url: URL, encode: @escaping @Sendable (Bitmap) -> Data?
    ) async throws {
        try await Task.detached {
            guard let data = encode(bitmap) else { throw ScreenshotExportFailure.notCaptured }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ScreenshotExportFailure.writeFailed(error.localizedDescription)
            }
        }.value
    }
}

extension InspectionStore {
    // MARK: - Exporting a screenshot

    /// Whether a layer's `solo` or `group` can be exported (C-ARCH-06): one export at a time,
    /// of a layer in the tree. An app is asked when the time comes; an archive is known to
    /// hold the image or not, a missing `solo` standing for the `group` (P-DET-04).
    public func canExportImage(of id: UInt64, kind: TextureKey.Kind) -> Bool {
        guard tree.contains(id), screenshotExport != .exporting else { return false }
        guard let known = source.imagePresence else { return true }
        guard let presence = known[id] else { return false }
        return kind == .group ? presence.group : presence.solo || presence.group
    }

    /// A layer's image to export (C-ARCH-06): the one the preview holds, else asked for on
    /// its own. Internal for tests.
    func exportImage(
        of id: UInt64, kind: TextureKey.Kind
    ) async throws(ScreenshotExportFailure) -> Bitmap {
        let held = kind == .solo ? images[id]?.solo : images[id]?.group
        return try await ScreenshotExporter.image(
            of: id, kind: kind, held: held?.image, from: source,
            maxTextureDimension: maxTextureDimension, decode: decodeImage)
    }

    /// Exports a layer's screenshot to `url` (C-ARCH-06): its image, encoded by `encode` away
    /// from the main thread, written in one piece. A failure stays in `screenshotExport`
    /// until dismissed. Does nothing while an export is under way.
    public func exportScreenshot(
        of id: UInt64, kind: TextureKey.Kind, to url: URL,
        encode: @escaping @Sendable (Bitmap) -> Data?
    ) {
        guard screenshotExport != .exporting else { return }
        screenshotExport = .exporting
        Task { [weak self] in
            guard let self else { return }
            let outcome: ScreenshotExportState
            do {
                let bitmap = try await self.exportImage(of: id, kind: kind)
                try await ScreenshotExporter.write(bitmap, to: url, encode: encode)
                outcome = .idle
            } catch let failure as ScreenshotExportFailure {
                outcome = .failed(failure)
            } catch {
                outcome = .failed(.other)
            }
            self.screenshotExport = outcome
        }
    }

    /// Forgets a failed export. Does nothing while one is under way.
    public func dismissScreenshotExport() {
        if case .failed = screenshotExport { screenshotExport = .idle }
    }
}
