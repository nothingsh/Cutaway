import CutawayTransport
import CutawayWire
import Foundation

/// An archive as the source of an inspection (C-ARCH-05): it answers the inspection's
/// requests from what the archive holds, as the app answered when it was saved. Nothing in it
/// can be changed.
///
/// Opening only notes which chunk holds each layer; a chunk is decoded when a request needs
/// it, and the last few decoded stay at hand.
public actor ArchiveSource: InspectionSource {
    /// How many decoded chunks are kept.
    static let keptChunks = 4

    /// The images each layer has in the archive, known from opening on: whether a screenshot
    /// can be exported is asked while a menu is shown, without waiting (C-ARCH-06).
    public nonisolated let knownImagePresence: [UInt64: ImagePresence]

    private let decoder: ArchiveDecoder
    /// The chunk each layer's detail is in.
    private let chunkOfLayer: [UInt64: Int]
    /// Decoded chunks, the most recently used last.
    private var decoded: [(index: Int, details: [UInt64: LayerDetail])] = []
    /// How many times a chunk was decoded. For tests.
    private(set) var decodedChunkCount = 0

    public init(decoder: ArchiveDecoder) {
        self.decoder = decoder
        var chunkOfLayer: [UInt64: Int] = [:]
        var imagePresence: [UInt64: ImagePresence] = [:]
        for index in 0..<decoder.chunkCount {
            // A chunk that cannot be read now fails when a request needs it.
            for layer in (try? decoder.layers(inChunk: index)) ?? []
                where chunkOfLayer[layer.layerID] == nil
            {
                chunkOfLayer[layer.layerID] = index
                imagePresence[layer.layerID] = ImagePresence(solo: layer.hasSolo, group: layer.hasGroup)
            }
        }
        self.chunkOfLayer = chunkOfLayer
        knownImagePresence = imagePresence
    }

    public nonisolated var isLive: Bool { false }

    public var negotiatedVersion: Version? {
        decoder.manifest.protocolVersion
    }

    public nonisolated var imagePresence: [UInt64: ImagePresence]? { knownImagePresence }

    public func hierarchy() async throws -> Hierarchy {
        decoder.hierarchy
    }

    public func subtree(of rootID: UInt64) async throws -> Hierarchy {
        throw RequestError.unsupported
    }

    public func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult {
        throw RequestError.unsupported
    }

    /// Each layer asked for with the parts asked for, in one chunk; a layer the archive does
    /// not hold is `LayerNotFound` (P-DET-02).
    public func layerDetails(_ request: GetLayerDetails) async -> LayerDetailsStream {
        let (chunks, continuation) = AsyncThrowingStream.makeStream(of: [LayerDetail].self)
        do {
            let details = try request.requests.map { asked -> LayerDetail in
                guard let index = chunkOfLayer[asked.layerID],
                      let detail = try chunk(index)[asked.layerID]
                else {
                    return LayerDetail(
                        layerID: asked.layerID, status: .layerNotFound, solo: nil, group: nil,
                        attributeGroups: [], constraints: [])
                }
                return detail.trimmed(to: asked)
            }
            continuation.yield(details)
            continuation.finish()
        } catch {
            // The mapped file changed since it was checked.
            continuation.finish(throwing: RequestError.server(ServerError(
                code: .internalError, message: "The archive could not be read.")))
        }
        return LayerDetailsStream(chunks: chunks, cancelAction: {})
    }

    private func chunk(_ index: Int) throws -> [UInt64: LayerDetail] {
        if let position = decoded.firstIndex(where: { $0.index == index }) {
            let entry = decoded.remove(at: position)
            decoded.append(entry)
            return entry.details
        }
        let details = try decoder.chunk(at: index).details
        decodedChunkCount += 1
        let byLayer = Dictionary(details.map { ($0.layerID, $0) }, uniquingKeysWith: { first, _ in first })
        decoded.append((index, byLayer))
        if decoded.count > Self.keptChunks { decoded.removeFirst() }
        return byLayer
    }
}

extension LayerDetail {
    /// Only the parts a request asks for (P-DET-04).
    func trimmed(to request: LayerDetailRequest) -> LayerDetail {
        var detail = self
        if !request.wantSolo { detail.solo = nil }
        if !request.wantGroup { detail.group = nil }
        if !request.wantAttributes { detail.attributeGroups = [] }
        if !request.wantConstraints { detail.constraints = [] }
        return detail
    }
}
