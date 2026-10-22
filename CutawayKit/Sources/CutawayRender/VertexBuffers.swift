import Foundation
import Metal

/// The renderer's vertex buffers, used again from frame to frame. Making one for every frame
/// allocated megabytes a frame with thousands of layers: hundreds of megabytes a second while
/// the camera moves. At most `limit` frames are in flight, each with a buffer of its own; a
/// frame that finds them all in use waits for the GPU to be done with one, for about a frame
/// at most, and then draws with a buffer of its own that is not kept.
final class VertexBuffers: @unchecked Sendable {
    /// A buffer taken by one frame. It crosses to the thread that completes the frame's
    /// commands, which gives it back; nothing else touches it there.
    struct Lease: @unchecked Sendable {
        let buffer: any MTLBuffer
        /// False for a buffer made because every kept one was in use: it is not kept.
        let isKept: Bool
    }

    /// Frames in flight: one the GPU draws, one the CPU encodes, one waiting between.
    static let limit = 3
    /// The smallest buffer made, so that a few small lists do not make one after another.
    private static let minimumLength = 4096

    private let device: any MTLDevice
    /// How long a frame waits for a kept buffer before it makes one that is not kept: the
    /// thread that draws, the main one for the preview, is never held up for longer.
    private let waitLimit: DispatchTimeInterval
    /// How many frames in a row must fit in a quarter of the idle buffer they take before
    /// it is let go for a smaller one: a list that shrinks for a moment keeps its buffers.
    private let shrinkAfter: Int
    /// Counts the kept buffers not in use by a frame, made or not.
    private let available = DispatchSemaphore(value: limit)
    private let lock = NSLock()
    /// The kept buffers not in use, guarded by `lock`, as are the counts below.
    private var idle: [any MTLBuffer] = []
    private var made = 0
    private var madeNotKept = 0
    /// Frames in a row whose list fits in a quarter of the idle buffer they took.
    private var smallFrames = 0

    init(
        device: any MTLDevice, waitLimit: DispatchTimeInterval = .microseconds(16_667),
        shrinkAfter: Int = 60
    ) {
        self.device = device
        self.waitLimit = waitLimit
        self.shrinkAfter = shrinkAfter
    }

    /// How many kept buffers were made. For tests.
    var madeCount: Int { lock.withLock { made } }
    /// How many buffers were made that were not kept. For tests.
    var madeNotKeptCount: Int { lock.withLock { madeNotKept } }
    /// The lengths of the kept buffers not in use. For tests.
    var idleLengths: [Int] { lock.withLock { idle.map(\.length) } }

    /// A buffer of at least `length` bytes that no frame in flight uses. The idle one is used
    /// again when it is large enough and not far too large for a while; otherwise one of the
    /// right size takes its place. When `limit` frames hold one, waits for one to come back,
    /// and makes one that is not kept if none comes in time. Each buffer taken is given back
    /// once, when the GPU is done with it.
    func take(length: Int) throws -> Lease {
        // Rounded up to a power of two: a list that grows a little at a time, as marks and a
        // measurement come and go, does not make a buffer every frame.
        var size = Self.minimumLength
        while size < length { size *= 2 }
        guard available.wait(timeout: .now() + waitLimit) == .success else {
            guard let buffer = device.makeBuffer(length: size, options: .storageModeShared) else {
                throw RenderError.gpu("no vertex buffer")
            }
            lock.withLock { madeNotKept += 1 }
            return Lease(buffer: buffer, isKept: false)
        }
        let (reusable, fits) = lock.withLock { () -> ((any MTLBuffer)?, Bool) in
            guard let buffer = idle.popLast() else { return (nil, false) }
            let farTooLarge = buffer.length >= size * 4
            smallFrames = farTooLarge ? smallFrames + 1 : 0
            return (buffer, buffer.length >= size && (!farTooLarge || smallFrames < shrinkAfter))
        }
        if let reusable, fits { return Lease(buffer: reusable, isKept: true) }
        guard let buffer = device.makeBuffer(length: size, options: .storageModeShared) else {
            // The other buffer is kept for the frames that fit in it.
            if let reusable {
                giveBack(Lease(buffer: reusable, isKept: true))
            } else {
                available.signal()
            }
            throw RenderError.gpu("no vertex buffer")
        }
        lock.withLock { made += 1 }
        return Lease(buffer: buffer, isKept: true)
    }

    /// Takes back the buffer of a frame, if it had one, when its commands complete. The
    /// commands must be committed, or the buffer is never given back. One that is not kept
    /// lives until then too.
    func giveBack(_ lease: Lease?, after commands: any MTLCommandBuffer) {
        guard let lease else { return }
        commands.addCompletedHandler { [self] _ in giveBack(lease) }
    }

    /// Takes back a buffer the GPU is done with. One that is not kept just goes.
    func giveBack(_ lease: Lease) {
        guard lease.isKept else { return }
        lock.withLock { idle.append(lease.buffer) }
        available.signal()
    }
}
