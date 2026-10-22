internal import FlatBuffers
import Foundation

/// Why an archive cannot be read, in the order Resources/ARCHIVE.md checks them.
public enum ArchiveError: Error, Equatable, Sendable {
    /// Shorter than the magic, or the magic is not `CTWYARCH`.
    case notAnArchive
    /// Written in a format version above `ArchiveEncoder.formatVersion`.
    case newerFormat(UInt32)
    /// The file ends before the trailer does.
    case incomplete
    /// The structure, the manifest or a frame is wrong. The text is for logs.
    case damaged(String)
    /// The frames were fetched under another major protocol version.
    case differentProtocolMajor(Version)
    /// The frames were fetched under a minor protocol version above this reader's.
    case newerProtocolMinor(Version)
    /// A chunk was asked for by an index outside `0..<chunkCount`. Only a caller's mistake
    /// gives this, never the file.
    case noSuchChunk(Int)
}

/// A layer's detail in an archive, as far as an index needs it.
public struct ArchiveLayer: Equatable, Sendable {
    public var layerID: UInt64
    public var hasSolo: Bool
    public var hasGroup: Bool

    public init(layerID: UInt64, hasSolo: Bool, hasGroup: Bool) {
        self.layerID = layerID
        self.hasSolo = hasSolo
        self.hasGroup = hasGroup
    }
}

/// Reads an archive. Every check of Resources/ARCHIVE.md runs when it is created, so a damaged
/// archive is refused before anything is shown. The hello, icon and hierarchy are decoded
/// then; chunks are decoded when asked for.
///
/// Give it the file mapped into memory (`Data(contentsOf:options: .alwaysMapped)`): it keeps
/// the data and slices frames out of it.
public struct ArchiveDecoder: Sendable {
    public let manifest: ArchiveManifest
    /// The interface state section, as written. Empty when there is none.
    public let state: Data
    public let hello: Hello
    public let appIcon: AppIcon
    public let hierarchy: Hierarchy
    /// The environment the archive was saved in: from protocol 1.2, and optional (C-ENV-04).
    public let environment: Environment?

    private let data: Data
    /// Where each frame's buffer lies in `data`. Internal for tests.
    let frames: [Range<Data.Index>]
    /// The layers of each chunk, noted as the chunks were checked.
    private let chunkLayers: [[ArchiveLayer]]
    /// The index of the first chunk's frame: after the optional `Environment`.
    private let firstChunk: Int

    public init(_ data: Data) throws(ArchiveError) {
        let (manifestBytes, state, frames) = try Self.structure(of: data)
        let manifest = try Self.manifest(from: manifestBytes)
        try Self.checkProtocol(of: manifest)

        // The frames: verified, and of the kinds Resources/ARCHIVE.md lists, in its order.
        guard frames.count >= 3 else {
            throw .damaged("\(frames.count) frames, at least 3 are needed")
        }
        let first = try Self.decode(data[frames[0]], index: 0)
        guard case .hello(let hello) = first, hello.role == .server, hello.app != nil else {
            throw .damaged("frame 0 is not the server's Hello")
        }
        guard case .appIcon(let appIcon) = try Self.decode(data[frames[1]], index: 1) else {
            throw .damaged("frame 1 is not an AppIcon")
        }
        guard case .hierarchy(let hierarchy) = try Self.decode(data[frames[2]], index: 2) else {
            throw .damaged("frame 2 is not a Hierarchy")
        }
        // An Environment may follow the Hierarchy; anywhere else it is not a chunk.
        var environment: Environment?
        if frames.count > 3, Self.isEnvironment(data[frames[3]]) {
            guard case .environment(let saved) = try Self.decode(data[frames[3]], index: 3) else {
                throw .damaged("frame 3 is not an Environment")
            }
            environment = saved
        }
        let firstChunk = environment == nil ? 3 : 4
        let chunkLayers = try Self.checkChunks(
            data, frames: Array(frames.dropFirst(firstChunk)), firstIndex: firstChunk)

        self.manifest = manifest
        self.state = state
        self.hello = hello
        self.appIcon = appIcon
        self.hierarchy = hierarchy
        self.environment = environment
        self.firstChunk = firstChunk
        self.data = data
        self.frames = frames
        self.chunkLayers = chunkLayers
    }

    /// The container read as far as it can be without trusting the content: the manifest's
    /// bytes, the state section, and where each frame lies.
    private static func structure(
        of data: Data
    ) throws(ArchiveError) -> (manifest: Data, state: Data, frames: [Range<Data.Index>]) {
        var reader = Reader(data: data)

        guard reader.remaining >= 8, reader.peek(8) == ArchiveLayout.magic else {
            throw .notAnArchive
        }
        reader.skip(8)
        let format = try reader.uint32()
        guard format <= ArchiveEncoder.formatVersion else { throw .newerFormat(format) }

        // The structure, as far as it can be read without trusting the content.
        let manifestBytes = try reader.bytes(Int(try reader.uint32()))
        let state = try reader.bytes(Int(try reader.uint32()))
        var frames: [Range<Data.Index>] = []
        while true {
            let length = try reader.uint32()
            if length == 0 { break }
            guard length <= FrameCodec.maximumFrameLength else {
                throw .damaged("frame \(frames.count) is \(length) bytes long")
            }
            frames.append(try reader.range(Int(length)))
        }
        let count = try reader.uint32()
        let endMagic = try reader.bytes(8)
        guard endMagic == ArchiveLayout.endMagic else { throw .damaged("the trailer's magic") }
        guard reader.remaining == 0 else {
            throw .damaged("\(reader.remaining) bytes after the trailer")
        }
        guard count == frames.count else {
            throw .damaged("the trailer counts \(count) frames, \(frames.count) are present")
        }
        return (manifestBytes, state, frames)
    }

    /// The archive's protocol version is one this side reads.
    private static func checkProtocol(of manifest: ArchiveManifest) throws(ArchiveError) {
        let local = ProtocolVersion.current
        guard manifest.protocolVersion.major == local.major else {
            throw .differentProtocolMajor(manifest.protocolVersion)
        }
        guard manifest.protocolVersion.minor <= local.minor else {
            throw .newerProtocolMinor(manifest.protocolVersion)
        }
    }

    /// Verifies every chunk's frame and notes its layers, the chunks spread over the
    /// processor's cores: one after another, opening an archive of thousands of layers took
    /// seconds. A failure is that of the first chunk that fails.
    private static func checkChunks(
        _ data: Data, frames: [Range<Data.Index>], firstIndex: Int
    ) throws(ArchiveError) -> [[ArchiveLayer]] {
        final class Results: @unchecked Sendable {
            private let lock = NSLock()
            private var results: [Result<[ArchiveLayer], ArchiveError>?]

            init(count: Int) {
                results = Array(repeating: nil, count: count)
            }

            subscript(index: Int) -> Result<[ArchiveLayer], ArchiveError>? {
                get { lock.withLock { results[index] } }
                set { lock.withLock { results[index] = newValue } }
            }
        }
        let results = Results(count: frames.count)
        DispatchQueue.concurrentPerform(iterations: frames.count) { chunk in
            results[chunk] = Result { () throws(ArchiveError) -> [ArchiveLayer] in
                let index = firstIndex + chunk
                // Read where it lies in the data when it can be, so that the chunks checked
                // side by side are not each held twice.
                let layers: [ArchiveLayer]?
                do {
                    layers = try FrameCodec.withCheckedRoot(data[frames[chunk]]) { root in
                        guard root.bodyType == .layerdetailschunk,
                              let body = root.body(type: Cutaway_Wire_LayerDetailsChunk.self)
                        else { return nil }
                        return body.details.map {
                            ArchiveLayer(
                                layerID: $0.layerId, hasSolo: $0.solo != nil,
                                hasGroup: $0.group != nil)
                        }
                    }
                } catch {
                    throw .damaged("frame \(index): \(error)")
                }
                guard let layers else { throw .damaged("frame \(index) is not a LayerDetailsChunk") }
                return layers
            }
        }
        var layers: [[ArchiveLayer]] = []
        layers.reserveCapacity(frames.count)
        for chunk in frames.indices {
            guard let result = results[chunk] else { throw .damaged("frame \(firstIndex + chunk)") }
            layers.append(try result.get())
        }
        return layers
    }

    /// The number of `LayerDetailsChunk` frames.
    public var chunkCount: Int { frames.count - firstChunk }

    /// One chunk, decoded. Throws only when the data changed since it was checked, which a
    /// mapped file that was modified on disk can do.
    public func chunk(at index: Int) throws -> LayerDetailsChunk {
        let frame = try FrameCodec.decode(data[try chunkFrame(index)])
        guard case .layerDetailsChunk(let chunk) = frame.body else {
            throw ArchiveError.damaged("frame \(firstChunk + index) is not a LayerDetailsChunk")
        }
        return chunk
    }

    /// The layers a chunk has details for, in its order, and which images each has, without
    /// decoding the details themselves: noted when the archive was checked. For indexing an
    /// archive as it opens.
    public func layers(inChunk index: Int) throws -> [ArchiveLayer] {
        _ = try chunkFrame(index)
        return chunkLayers[index]
    }

    /// Where chunk `index` lies in the data (C-WIRE-09).
    private func chunkFrame(_ index: Int) throws(ArchiveError) -> Range<Int> {
        guard index >= 0, index < chunkCount else { throw .noSuchChunk(index) }
        return frames[firstChunk + index]
    }

    /// Every frame's buffer as stored, in order.
    public var payloads: [Data] {
        frames.map { Data(data[$0]) }
    }

    /// Whether a frame that verifies holds an `Environment`; a frame that does not verify is
    /// left for the check of its kind to report.
    private static func isEnvironment(_ payload: Data) -> Bool {
        (try? FrameCodec.withCheckedRoot(payload) { $0.bodyType == .environment }) ?? false
    }

    private static func decode(_ payload: Data, index: Int) throws(ArchiveError) -> Body? {
        do {
            return try FrameCodec.decode(payload).body
        } catch {
            throw .damaged("frame \(index): \(error)")
        }
    }

    private static func manifest(from bytes: Data) throws(ArchiveError) -> ArchiveManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let json = try decoder.decode(ManifestJSON.self, from: bytes)
            return ArchiveManifest(
                protocolVersion: Version(major: json.protocol.major, minor: json.protocol.minor),
                cutawayVersion: json.cutawayVersion, savedAt: json.savedAt)
        } catch {
            throw .damaged("the manifest: \(error)")
        }
    }
}

/// Reads forward through archive bytes. Running past the end is `incomplete`.
private struct Reader {
    let data: Data
    private var offset: Data.Index

    init(data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var remaining: Int { data.endIndex - offset }

    func peek(_ count: Int) -> Data {
        data[offset..<(offset + count)]
    }

    mutating func skip(_ count: Int) {
        offset += count
    }

    mutating func range(_ count: Int) throws(ArchiveError) -> Range<Data.Index> {
        guard count <= remaining else { throw .incomplete }
        defer { offset += count }
        return offset..<(offset + count)
    }

    mutating func bytes(_ count: Int) throws(ArchiveError) -> Data {
        Data(data[try range(count)])
    }

    mutating func uint32() throws(ArchiveError) -> UInt32 {
        let bytes = data[try range(4)]
        return bytes.reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }
}
