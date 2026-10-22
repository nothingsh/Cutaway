internal import FlatBuffers
import Foundation

public enum FrameError: Error, Equatable {
    /// The length exceeds `FrameCodec.maximumFrameLength` (P-FRAME-03).
    case tooLarge(length: Int)
    /// The buffer's file identifier is not `CTWY` (P-FRAME-02).
    case wrongFileIdentifier
    /// The buffer did not pass verification (P-FRAME-04). The text is for logs.
    case verificationFailed(String)
}

/// Converts between frames and the bytes of a plain FlatBuffer.
package enum FrameCodec {
    package static let fileIdentifier = "CTWY"
    /// 256 MiB (P-FRAME-03).
    package static let maximumFrameLength = 268_435_456

    /// A buffer within the length limit is never refused for its table count, depth or
    /// apparent size (P-FRAME-06). The runtime allows 1,000,000 tables by default; a table
    /// takes at least 4 bytes, so 2^26 tables cover a buffer of `maximumFrameLength`. The
    /// default depth (64) and apparent size (2^31) already suffice.
    private static let maximumTableCount: UInt32 = 1 << 26

    /// Decodes one frame from a plain FlatBuffer, without a length prefix.
    /// The whole buffer is verified before any field is read (P-FRAME-04).
    package static func decode(_ payload: Data) throws -> Frame {
        try withCheckedRoot(payload) { Frame($0) }
    }

    /// Calls `body` with the verified root of one frame, before any value is built. The
    /// archive reader uses it to check a frame's kind without decoding its contents. The root
    /// may read `payload` where it lies: neither it nor anything read lazily from it may
    /// outlive `body`.
    static func withCheckedRoot<Result>(
        _ payload: Data, _ body: (Cutaway_Wire_Frame) throws -> Result
    ) throws -> Result {
        guard payload.count <= maximumFrameLength else {
            throw FrameError.tooLarge(length: payload.count)
        }
        // The root offset and the file identifier take 8 bytes.
        guard payload.count >= 8 else {
            throw FrameError.verificationFailed("\(payload.count) bytes is too short for a frame")
        }
        // The verifier refuses a scalar whose address is not aligned to its size, and the
        // runtime reads scalars where they lie. A payload that starts on an 8-byte boundary is
        // read in place, whatever its indices: a frame sliced out of a mapped archive file
        // among them. Any other is copied into memory of its own. The address is checked where
        // the bytes are read: another access to them need not give the same one.
        let inPlace: Result? = try payload.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, Int(bitPattern: base) % 8 == 0 else { return nil }
            // The buffer does not own this memory: it neither copies nor frees it, and
            // verifying and reading never write to it.
            var buffer = ByteBuffer(
                assumingMemoryBound: UnsafeMutableRawPointer(mutating: base), capacity: bytes.count)
            return try body(try verifiedRoot(&buffer))
        }
        if let inPlace { return inPlace }
        copies.add()
        var buffer = ByteBuffer(data: alignedCopy(of: payload))
        return try body(try verifiedRoot(&buffer))
    }

    private static func verifiedRoot(_ buffer: inout ByteBuffer) throws -> Cutaway_Wire_Frame {
        do {
            return try getCheckedRoot(
                byteBuffer: &buffer, fileId: fileIdentifier,
                options: VerifierOptions(maxTableCount: maximumTableCount))
        } catch FlatbuffersErrors.bufferIdDidntMatchPassedId, FlatbuffersErrors.bufferDoesntContainID {
            throw FrameError.wrongFileIdentifier
        } catch {
            throw FrameError.verificationFailed(String(describing: error))
        }
    }

    /// A copy in memory of its own, which the allocator aligns. `Data(payload)` is not enough:
    /// it may share the storage of a payload that is not a slice.
    private static func alignedCopy(of payload: Data) -> Data {
        payload.withUnsafeBytes { bytes in
            bytes.baseAddress.map { Data(bytes: $0, count: bytes.count) } ?? Data()
        }
    }

    /// How many payloads were copied to be read since the process started. For tests.
    static var copyCount: Int { copies.value }
    private static let copies = CopyCounter()

    /// A count that any thread can add to; the lock is Foundation's, which this target is
    /// limited to.
    private final class CopyCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int { lock.withLock { count } }

        func add() { lock.withLock { count += 1 } }
    }

    /// Encodes one frame as a plain FlatBuffer carrying the file identifier, without a
    /// length prefix.
    package static func encode(_ frame: Frame) -> Data {
        var builder = FlatBufferBuilder(initialSize: 1024)
        var object = frame.makeObject()
        let root = Cutaway_Wire_Frame.pack(&builder, obj: &object)
        builder.finish(offset: root, fileId: fileIdentifier)
        return builder.data
    }

    /// Encodes one frame as it travels on the wire: a 4-byte little-endian length, then the
    /// plain buffer. This is not FlatBuffers' own size-prefixed format (P-FRAME-01).
    package static func encodeForStream(_ frame: Frame) -> Data {
        let payload = encode(frame)
        var stream = Data(capacity: payload.count + 4)
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { stream.append(contentsOf: $0) }
        stream.append(payload)
        return stream
    }
}
