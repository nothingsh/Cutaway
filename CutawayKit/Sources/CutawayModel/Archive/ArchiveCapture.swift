import CutawayTransport
import CutawayWire
import Foundation

/// Where saving an archive stands (C-ARCH-02).
public enum ArchiveSaveState: Equatable, Sendable {
    case idle
    /// Layers captured so far, of how many; the total is 0 until the hierarchy is in.
    case saving(completed: Int, total: Int)
    /// The archive is at this location. Stays until dismissed.
    case saved(URL)
    /// Nothing was left at the destination. Stays until dismissed.
    case failed(ArchiveSaveFailure)
}

/// Why an archive was not saved (C-ARCH-02).
public enum ArchiveSaveFailure: Equatable, Sendable {
    /// The connection ended, or the app stopped answering.
    case disconnected
    /// The app left the foreground (P-APP-01).
    case appNotActive
    /// A request failed otherwise, so the app did not send every layer.
    case incompleteAnswer
    /// The file could not be written or put in place. The text is the system's reason.
    case writeFailed(String)
}

enum ArchiveCaptureError: Error, Equatable {
    case cancelled
    case failed(ArchiveSaveFailure)
}

/// Captures one archive (C-ARCH-02, Resources/ARCHIVE.md): the app's icon, its hierarchy asked for
/// again, its environment (C-ENV-04), and every layer's screenshots, attributes and constraints, written as they arrive
/// into a temporary file that takes the destination's place only when complete.
enum ArchiveCapture {
    /// What an archive says of itself besides the protocol version: the version of Cutaway
    /// that saved it, when, and the state of the window it was saved from.
    struct Stamp {
        let cutawayVersion: String
        let savedAt: Date
        let state: ArchiveState
    }

    /// Layers per `GetLayerDetails`. The server answers requests one by one (P-REQ-06), so
    /// the preview's and the attribute panel's requests wait for at most one batch.
    static let batchSize = 8

    /// Runs a capture. Cancelling the task stops it; the request under way is cancelled
    /// (P-REQ-04). Whatever the outcome other than success, nothing is left at the
    /// destination that was not there before.
    ///
    /// `progress` reports layers done and the total, from (0, total) once the hierarchy is
    /// in; it is called on no particular thread.
    static func run(
        from session: any ArchiveRecordable, to destination: URL, stamp: Stamp,
        maxTextureDimension: UInt32,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int) -> Void
    ) async throws(ArchiveCaptureError) {
        let cutawayVersion = stamp.cutawayVersion, savedAt = stamp.savedAt, state = stamp.state
        guard let version = await session.negotiatedVersion,
              let hello = await session.serverHelloPayload
        else { throw .failed(.disconnected) }

        let writer: ArchiveFileWriter
        do {
            writer = try ArchiveFileWriter(destination: destination)
        } catch {
            throw .failed(.writeFailed(error.localizedDescription))
        }
        do {
            var encoder = ArchiveEncoder()
            let manifest = ArchiveManifest(
                protocolVersion: version, cutawayVersion: cutawayVersion,
                savedAt: Date(timeIntervalSince1970: savedAt.timeIntervalSince1970.rounded(.down)))
            try await writer.write(encoder.header(manifest: manifest, state: state.encoded()))
            try await writer.write(try encoder.frame(hello))

            let icon = try await session.recordedAppIcon()
            try Task.checkCancellation()
            try await writer.write(try encoder.frame(icon.payload))

            let hierarchy = try await session.recordedHierarchy()
            try Task.checkCancellation()
            try await writer.write(try encoder.frame(hierarchy.payload))

            // The environment the app is in, from 1.2 on (C-ENV-04): it cannot change during
            // the capture, since no override is sent while an archive is saved.
            if version.minor >= 2 {
                let environment = try await session.recordedEnvironment()
                try Task.checkCancellation()
                try await writer.write(try encoder.frame(environment.payload))
            }

            let nodes = hierarchy.value.nodes
            progress(0, nodes.count)
            var done = 0
            for start in stride(from: 0, to: nodes.count, by: batchSize) {
                let batch = nodes[start..<min(start + batchSize, nodes.count)]
                let request = GetLayerDetails(
                    // No images of a virtual node, which has none, or of what the app
                    // excludes from them; no constraints of a virtual node (C-DET-11).
                    requests: batch.map {
                        let isVirtual = $0.kind == .virtual
                        let images = !isVirtual && !$0.isCaptureExcluded
                        return LayerDetailRequest(
                            layerID: $0.id, wantSolo: images, wantGroup: images,
                            wantAttributes: true, wantConstraints: !isVirtual)
                    },
                    maxTextureDimension: maxTextureDimension)
                let stream = await session.recordedLayerDetails(request)
                for try await chunk in stream.chunks {
                    try await writer.write(try encoder.frame(chunk.payload))
                    done += chunk.value.count
                    progress(done, nodes.count)
                }
                // A reader whose task is cancelled sees the stream end early, not fail.
                try Task.checkCancellation()
            }

            try await writer.write(encoder.trailer())
            try await writer.finish()
        } catch {
            await writer.discard()
            throw failure(for: error)
        }
    }

    private static func failure(for error: any Error) -> ArchiveCaptureError {
        switch error {
        case is CancellationError:
            return .cancelled
        case let error as RequestError:
            switch error {
            case .disconnected, .timedOut: return .failed(.disconnected)
            case .appNotActive: return .failed(.appNotActive)
            // Cancelled by the server unasked, or anything else: not every layer came.
            default: return .failed(.incompleteAnswer)
            }
        case let error as ArchiveWriteError:
            return .failed(.writeFailed(error.reason))
        default:
            // The encoder refuses only frames the session would not have decoded.
            return .failed(.incompleteAnswer)
        }
    }
}
