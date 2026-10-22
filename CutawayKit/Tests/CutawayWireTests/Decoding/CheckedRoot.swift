import FlatBuffers
import Foundation
@testable import CutawayWire

extension FrameCodec {
    /// The verified root of a frame the encoder made, for tests that read the generated
    /// accessors after the call: unlike `withCheckedRoot`, the root keeps its bytes alive.
    static func checkedRoot(_ payload: Data) throws -> Cutaway_Wire_Frame {
        var buffer = ByteBuffer(data: Data(payload))
        return try getCheckedRoot(byteBuffer: &buffer, fileId: fileIdentifier)
    }
}
