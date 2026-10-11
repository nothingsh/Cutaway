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
        Frame(try checkedRoot(payload))
    }

    /// The verified root of one frame, before any value is built. The archive reader uses it
    /// to check a frame's kind without decoding its contents.
    static func checkedRoot(_ payload: Data) throws -> Cutaway_Wire_Frame {
        guard payload.count <= maximumFrameLength else {
            throw FrameError.tooLarge(length: payload.count)
        }
        // The root offset and the file identifier take 8 bytes.
        guard payload.count >= 8 else {
            throw FrameError.verificationFailed("\(payload.count) bytes is too short for a frame")
        }
        var buffer = ByteBuffer(data: startsAligned(payload) ? payload : alignedCopy(of: payload))
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

    /// Whether the runtime can read `payload` where it is. A slice keeps its parent's indices,
    /// and the verifier refuses a scalar whose address is not aligned to its size; a buffer
    /// that starts at index 0 on an 8-byte boundary has neither problem. Anything else, such
    /// as a frame sliced out of an archive file, is copied into a buffer of its own.
    private static func startsAligned(_ payload: Data) -> Bool {
        guard payload.startIndex == 0 else { return false }
        return payload.withUnsafeBytes { bytes in
            bytes.baseAddress.map { Int(bitPattern: $0) % 8 == 0 } ?? false
        }
    }

    /// A copy in memory of its own, which the allocator aligns. `Data(payload)` is not enough:
    /// it may share the storage of a payload that is not a slice.
    private static func alignedCopy(of payload: Data) -> Data {
        payload.withUnsafeBytes { bytes in
            bytes.baseAddress.map { Data(bytes: $0, count: bytes.count) } ?? Data()
        }
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
