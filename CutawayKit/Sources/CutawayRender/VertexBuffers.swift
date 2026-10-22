import Foundation
import Metal

/// The renderer's vertex buffers, used again from frame to frame. Making one for every frame
/// allocated megabytes a frame with thousands of layers: hundreds of megabytes a second while
/// the camera moves. At most `limit` frames are in flight, each with a buffer of its own; a
/// frame that finds them all in use waits until the GPU is done with one.
final class VertexBuffers: @unchecked Sendable {
    /// A buffer taken by one frame. It crosses to the thread that completes the frame's
    /// commands, which gives it back; nothing else touches it there.
    struct Lease: @unchecked Sendable {
        let buffer: any MTLBuffer
    }

    /// Frames in flight: one the GPU draws, one the CPU encodes, one waiting between.
    static let limit = 3
    /// The smallest buffer made, so that a few small lists do not make one after another.
    private static let minimumLength = 4096

    private let device: any MTLDevice
    /// Counts the buffers not in use by a frame, made or not.
    private let available = DispatchSemaphore(value: limit)
    private let lock = NSLock()
    /// The buffers made and not in use, guarded by `lock`.
    private var idle: [any MTLBuffer] = []
    private var made = 0

    init(device: any MTLDevice) {
        self.device = device
    }

    /// How many buffers were made. For tests.
    var madeCount: Int { lock.withLock { made } }

    /// A buffer of at least `length` bytes that no frame in flight uses, made larger when the
    /// idle one is too small. Waits while `limit` frames hold one. Each buffer taken is given
    /// back once, when the GPU is done with it.
    func take(length: Int) throws -> Lease {
        available.wait()
        let reusable = lock.withLock { idle.popLast() }
        if let reusable, reusable.length >= length { return Lease(buffer: reusable) }
        // Rounded up to a power of two: a list that grows a little at a time, as marks and a
        // measurement come and go, does not make a buffer every frame.
        var size = Self.minimumLength
        while size < length { size *= 2 }
        guard let buffer = device.makeBuffer(length: size, options: .storageModeShared) else {
            // The smaller buffer is kept for the frames that fit in it.
            if let reusable { giveBack(Lease(buffer: reusable)) } else { available.signal() }
            throw RenderError.gpu("no vertex buffer")
        }
        lock.withLock { made += 1 }
        return Lease(buffer: buffer)
    }

    /// Takes back the buffer of a frame, if it had one, when its commands complete. The
    /// commands must be committed, or the buffer is never given back.
    func giveBack(_ lease: Lease?, after commands: any MTLCommandBuffer) {
        guard let lease else { return }
        commands.addCompletedHandler { [self] _ in giveBack(lease) }
    }

    /// Takes back a buffer the GPU is done with.
    func giveBack(_ lease: Lease) {
        lock.withLock { idle.append(lease.buffer) }
        available.signal()
    }
}
