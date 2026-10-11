import CutawayTransport
import CutawayWire
import Foundation

/// A channel whose incoming bytes a test lines up, made only when they are read, and handed
/// over at most 64 KiB at a time, as a connection does (C-CONN-12). It counts what it handed
/// over and keeps what the session sent.
public actor MeteredChannel: ByteChannel {
    /// The most one receive returns, as `ConnectionChannel` asks for.
    public static let pieceLength = 65_536

    private var queue: [@Sendable () -> Data] = []
    private var current = Data()
    private var waiting: CheckedContinuation<Data?, Never>?
    private var ended = false

    /// Every byte handed to the session so far.
    public private(set) var deliveredByteCount = 0
    /// Every buffer the session sent, as sent (with the length prefix).
    public private(set) var sent: [Data] = []
    public private(set) var closeCount = 0

    public init() {}

    /// Whether a receive waits for bytes: the session wants more and there are none yet.
    public var isReceiving: Bool { waiting != nil }

    /// Lines up bytes to deliver after those already lined up.
    public func feed(_ bytes: Data) {
        feed { bytes }
    }

    /// Lines up bytes that are made when the session reaches them.
    public func feed(_ make: @escaping @Sendable () -> Data) {
        queue.append(make)
        deliverIfWaiting()
    }

    /// The peer closes the connection once what is lined up has been read.
    public func end() {
        ended = true
        deliverIfWaiting()
    }

    public func send(_ data: Data) async throws {
        sent.append(data)
    }

    public func receive() async throws -> Data? {
        if let piece = nextPiece() { return piece }
        if ended { return nil }
        return await withCheckedContinuation { waiting = $0 }
    }

    public nonisolated func close() {
        Task { await self.recordClose() }
    }

    /// The frames the session sent, decoded.
    public func sentFrames() -> [Frame] {
        sent.compactMap { try? FrameCodec.decode(Data($0.dropFirst(4))) }
    }

    private func recordClose() {
        closeCount += 1
        ended = true
        deliverIfWaiting()
    }

    private func nextPiece() -> Data? {
        while current.isEmpty, !queue.isEmpty {
            current = queue.removeFirst()()
        }
        guard !current.isEmpty else { return nil }
        let piece = Data(current.prefix(Self.pieceLength))
        current = Data(current.dropFirst(piece.count))
        deliveredByteCount += piece.count
        return piece
    }

    private func deliverIfWaiting() {
        guard let waiting else { return }
        if let piece = nextPiece() {
            self.waiting = nil
            waiting.resume(returning: piece)
        } else if ended {
            self.waiting = nil
            waiting.resume(returning: nil)
        }
    }
}

extension Frame {
    /// A chunk with one detail whose solo image holds `imageBytes` bytes of data, for tests of
    /// how much a session holds (C-CONN-12). The image is not one that decompresses: a session
    /// never looks inside it.
    public static func bulkyChunk(
        requestID: UInt32, sequence: UInt32, layerID: UInt64, imageBytes: Int
    ) -> Frame {
        let image = EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: 1, pixelHeight: 1, bytesPerRow: 4,
            scale: 1, data: Data(count: imageBytes))
        return Frame(requestID: requestID, body: .layerDetailsChunk(LayerDetailsChunk(
            sequence: sequence,
            details: [LayerDetail(
                layerID: layerID, status: .ok, solo: image, group: nil, attributeGroups: [])])))
    }
}
