import Foundation

/// Produces an archive piece by piece, so that a writer can put each frame on disk as it
/// arrives: `header`, then `frame` for each frame in order, then `trailer`.
///
/// The encoder does not check which frames it is given or in what order; the decoder does.
public struct ArchiveEncoder: Sendable {
    /// The format version this code writes and the highest it reads.
    public static let formatVersion: UInt32 = 1

    private var frameCount: UInt32 = 0

    public init() {}

    /// The magic, the format version, the manifest and the interface state.
    public func header(manifest: ArchiveManifest, state: Data) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        let json = ManifestJSON(
            protocol: .init(
                major: manifest.protocolVersion.major, minor: manifest.protocolVersion.minor),
            cutawayVersion: manifest.cutawayVersion, savedAt: manifest.savedAt)
        // Encoding plain strings, integers and a date cannot fail.
        let manifestBytes = (try? encoder.encode(json)) ?? Data()

        var data = ArchiveLayout.magic
        data += Self.uint32(Self.formatVersion)
        data += Self.uint32(UInt32(manifestBytes.count)) + manifestBytes
        data += Self.uint32(UInt32(state.count)) + state
        return data
    }

    /// One frame as received: its length, then the buffer (P-FRAME-01). Throws for an empty
    /// buffer, whose length would read as the trailer, and for one over the frame limit.
    public mutating func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else {
            throw FrameError.verificationFailed("an empty frame")
        }
        guard payload.count <= FrameCodec.maximumFrameLength else {
            throw FrameError.tooLarge(length: payload.count)
        }
        frameCount += 1
        return Self.uint32(UInt32(payload.count)) + payload
    }

    /// The end of the archive: a zero length, the number of frames and `CTWYDONE`.
    public func trailer() -> Data {
        Self.uint32(0) + Self.uint32(frameCount) + ArchiveLayout.endMagic
    }

    private static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
