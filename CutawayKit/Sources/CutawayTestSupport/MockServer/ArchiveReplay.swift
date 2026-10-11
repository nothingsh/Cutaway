import CutawayWire
import Foundation

/// The details an archive holds, taken out a chunk at a time as requests need them, so that
/// a large archive is not decoded whole (C-MOCK-04).
final class ArchivedDetails: @unchecked Sendable {
    /// How many decoded chunks are kept.
    static let keptChunks = 4

    private let decoder: ArchiveDecoder
    /// The chunk each layer's detail is in; the first one when several hold it.
    private let chunkOfLayer: [UInt64: Int]
    private let lock = NSLock()
    /// Decoded chunks, the most recently used last.
    private var decoded: [(index: Int, details: [UInt64: LayerDetail])] = []

    init(_ decoder: ArchiveDecoder) {
        self.decoder = decoder
        var chunkOfLayer: [UInt64: Int] = [:]
        for index in 0..<decoder.chunkCount {
            for layer in (try? decoder.layers(inChunk: index)) ?? []
                where chunkOfLayer[layer.layerID] == nil
            {
                chunkOfLayer[layer.layerID] = index
            }
        }
        self.chunkOfLayer = chunkOfLayer
    }

    /// Nil for a layer the archive has no detail of.
    func detail(of id: UInt64) -> LayerDetail? {
        guard let index = chunkOfLayer[id] else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let position = decoded.firstIndex(where: { $0.index == index }) {
            let entry = decoded.remove(at: position)
            decoded.append(entry)
            return entry.details[id]
        }
        // The decoder checked every frame when the archive was read.
        guard let chunk = try? decoder.chunk(at: index) else { return nil }
        let byLayer = Dictionary(
            chunk.details.map { ($0.layerID, $0) }, uniquingKeysWith: { first, _ in first })
        decoded.append((index, byLayer))
        if decoded.count > Self.keptChunks { decoded.removeFirst() }
        return byLayer[id]
    }
}

extension MockResponder {
    /// Answers as the app did when the archive was saved (C-MOCK-04): its icon and hierarchy,
    /// subtrees cut from that hierarchy, and each layer's detail as stored, whatever size is
    /// asked for. A layer the archive has no detail of is `LayerNotFound` (P-DET-02); edits
    /// are refused, as the archive holds no result of one.
    public init(archive: Data) throws {
        let decoder = try ArchiveDecoder(archive)
        self.init(icon: decoder.appIcon, hierarchy: decoder.hierarchy, details: [:])
        archived = ArchivedDetails(decoder)
    }
}

extension MockScript {
    /// A server that replays an archive (C-MOCK-04): the handshake with the server's `Hello`
    /// the archive holds, then a responder for it.
    public static func replaying(archive: Data) throws -> MockScript {
        let hello = try ArchiveDecoder(archive).hello
        var steps = try Self.fixtures("handshake").steps
        for (index, step) in steps.enumerated() {
            if case .send(var frame) = step, case .hello = frame.body {
                frame.body = .hello(hello)
                steps[index] = .send(frame)
            }
        }
        return MockScript(steps: steps + [.respond(try MockResponder(archive: archive))])
    }
}
