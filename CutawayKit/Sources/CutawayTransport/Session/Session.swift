import CutawayWire
import Foundation
import os

public enum SessionEvent: Equatable, Sendable {
    case appStateChanged(AppState)
    /// The connection ended. This is the last event.
    case closed
}

package enum HandshakeOutcome: Equatable, Sendable {
    /// The session is ready for requests. `negotiated` is the version both sides work to:
    /// the lower of the two minor versions (P-HELLO-04).
    case ready(AppInfo, negotiated: Version)
    /// The major versions differ. The connection is closed (P-HELLO-03).
    case incompatible(local: Version, remote: Version, app: AppInfo?)
    /// The server already serves another client. The connection is closed (P-TRANS-03).
    case busy
}

/// One connection to one app: the handshake, then requests and their responses.
public actor Session {
    // What is not private here is internal only so that Session+Incoming.swift and
    // Session+Silence.swift can reach it. It belongs to Session alone.

    enum Phase { case idle, handshaking, ready, closed }

    enum ResponseKind { case appIcon, hierarchy, setAttributeResult, environment }

    /// A response and the buffer it arrived in.
    struct Received {
        var body: Body
        var payload: Data
    }

    struct SingleRequest {
        var expects: ResponseKind
        var continuation: CheckedContinuation<Received, any Error>
        /// When it was sent, on `clock` (C-CONN-13).
        var sentAt: Duration
    }

    /// Where a stream's chunks go: with or without the bytes of their frames. Streams that do
    /// not record drop the bytes at once, so the chunks they buffer cost no more than before.
    enum StreamSink {
        case plain(AsyncThrowingStream<[LayerDetail], any Error>.Continuation)
        case recorded(AsyncThrowingStream<Recorded<[LayerDetail]>, any Error>.Continuation)

        func yield(_ details: [LayerDetail], payload: Data) {
            switch self {
            case .plain(let continuation): continuation.yield(details)
            case .recorded(let continuation):
                continuation.yield(Recorded(value: details, payload: payload))
            }
        }

        func finish(throwing error: (any Error)? = nil) {
            switch self {
            case .plain(let continuation): continuation.finish(throwing: error)
            case .recorded(let continuation): continuation.finish(throwing: error)
            }
        }
    }

    struct StreamRequest {
        var continuation: StreamSink
        var nextSequence: UInt32 = 0
        var isCancelling = false
        /// When it was sent, on `clock` (C-CONN-13).
        var sentAt: Duration
    }

    enum Pending {
        case single(SingleRequest)
        case stream(StreamRequest)
    }

    let channel: any ByteChannel
    private let client: ClientInfo
    private let protocolVersion: Version
    let requestTimeout: Duration
    let clock: any SessionClock

    private(set) var phase = Phase.idle
    /// The version both sides work to, once the handshake succeeded (P-HELLO-04). Nil before
    /// that, and when the handshake failed.
    public private(set) var negotiatedVersion: Version?
    /// The buffer of the server's `Hello`, as received, once the handshake succeeded. An
    /// archive starts with it (Resources/ARCHIVE.md).
    public private(set) var serverHelloPayload: Data?
    private var handshakeTimedOut = false
    private var nextRequestID: UInt32 = 1
    var pending = PendingTable()
    var reader = FrameReader()
    var readTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?
    /// Untaken chunks by stream (C-CONN-12).
    var ledger: StreamLedger
    /// Closed while the readers are too far behind; the reading task waits there.
    private let readGate = ReadGate()
    /// When bytes last arrived, or silence otherwise stopped counting: the end of a pause,
    /// the start of the handshake (C-CONN-13).
    var lastHeard: Duration = .zero
    var watchdog: Task<Void, Never>?

    /// Where the session says why it ended a connection (C-CONN-10, P-FRAME-03). Nothing is
    /// shown; the log is for whoever looks into a connection that ended.
    static let log = Logger(subsystem: "dev.cutaway", category: "session")

    /// Frames leave through one queue and one task, so they reach the wire in the order their
    /// request IDs were assigned (P-REQ-01).
    private let outgoing: AsyncStream<Data>
    private let outgoingContinuation: AsyncStream<Data>.Continuation

    /// App state changes and the end of the connection. Meant for one consumer.
    public nonisolated let events: AsyncStream<SessionEvent>
    let eventContinuation: AsyncStream<SessionEvent>.Continuation

    /// `requestTimeout` is how long a request may go without a byte from the server
    /// (C-CONN-04, C-CONN-13).
    package init(
        channel: any ByteChannel, client: ClientInfo,
        protocolVersion: Version = ProtocolVersion.current,
        requestTimeout: Duration = .seconds(10)
    ) {
        self.init(
            channel: channel, client: client, protocolVersion: protocolVersion,
            requestTimeout: requestTimeout, clock: ContinuousSessionClock(), readLimit: .standard)
    }

    /// The same, with the clock silence is measured by and the limit on what waits for a
    /// reader given: for tests.
    package init(
        channel: any ByteChannel, client: ClientInfo,
        protocolVersion: Version = ProtocolVersion.current, requestTimeout: Duration = .seconds(10),
        clock: any SessionClock, readLimit: ReadLimit
    ) {
        self.channel = channel
        self.client = client
        self.protocolVersion = protocolVersion
        self.requestTimeout = requestTimeout
        self.clock = clock
        self.ledger = StreamLedger(limit: readLimit)
        let (outgoing, outgoingContinuation) = AsyncStream.makeStream(of: Data.self)
        self.outgoing = outgoing
        self.outgoingContinuation = outgoingContinuation
        let (events, eventContinuation) = AsyncStream.makeStream(of: SessionEvent.self)
        self.events = events
        self.eventContinuation = eventContinuation
    }

    deinit {
        channel.close()
        outgoingContinuation.finish()
        watchdog?.cancel()
        readGate.open()
        // A stream's reader holds the stream, not the session, so a stream can outlive it.
        pending.finishStreams(throwing: .disconnected)
        eventContinuation.finish()
    }

    // MARK: - Handshake

    /// Sends this side's `Hello` and waits for the server's first frame (C-CONN-03).
    package func handshake() async throws -> HandshakeOutcome {
        guard phase == .idle else {
            throw RequestError.protocolViolation("handshake() was called more than once")
        }
        phase = .handshaking
        lastHeard = clock.now()
        startWatchdog()
        startWriting()
        enqueue(Frame(requestID: 0, body: .hello(Hello(
            protocolVersion: protocolVersion, role: .client, client: client, app: nil))))

        let first: Frame
        let firstPayload: Data
        do {
            (first, firstPayload) = try await firstFrame()
            // close() or the timeout may have ended the session while the frame was on its
            // way. Bytes that a channel delivers after that do not revive it.
            guard phase == .handshaking else {
                throw handshakeTimedOut ? RequestError.timedOut : RequestError.disconnected
            }
        } catch {
            shutDown()
            throw error
        }

        switch first.body {
        case .hello(let hello) where hello.role == .server:
            guard let remote = hello.protocolVersion else {
                shutDown()
                throw RequestError.protocolViolation("the server's Hello has no protocol version")
            }
            guard remote.major == protocolVersion.major else {
                // P-HELLO-03: close, and send nothing else.
                shutDown()
                return .incompatible(local: protocolVersion, remote: remote, app: hello.app)
            }
            guard let app = hello.app else {
                shutDown()
                throw RequestError.protocolViolation("the server's Hello has no app info")
            }
            phase = .ready
            let negotiated = Version(
                major: remote.major, minor: min(remote.minor, protocolVersion.minor))
            negotiatedVersion = negotiated
            serverHelloPayload = firstPayload
            // Frames that arrived together with the Hello are already in the reader.
            drainReader()
            if phase == .ready { startReading() }
            return .ready(app, negotiated: negotiated)
        case .error(let error) where error.code == .busy:
            shutDown()
            return .busy
        default:
            shutDown()
            throw RequestError.protocolViolation(
                "expected the server's Hello, got \(Self.name(of: first.body))")
        }
    }

    private func firstFrame() async throws -> (Frame, Data) {
        while true {
            if let received = try bufferedFrame() { return received }
            let bytes: Data?
            do {
                bytes = try await channel.receive()
            } catch {
                bytes = nil
            }
            guard let bytes else {
                throw handshakeTimedOut ? RequestError.timedOut : RequestError.disconnected
            }
            lastHeard = clock.now()
            reader.append(bytes)
        }
    }

    func expireHandshake() {
        guard phase == .handshaking else { return }
        handshakeTimedOut = true
        // Ends the session at once: the receive that firstFrame() waits on throws, and a frame
        // that it still returns is refused by handshake().
        shutDown()
    }

    // MARK: - Requests

    /// Asks for the app's icon. Nil when the app has none (P-ICON-01).
    public func appIcon() async throws -> EncodedImage? {
        try await recordedAppIcon().value
    }

    /// `appIcon()`, with the bytes of the response.
    public func recordedAppIcon() async throws -> Recorded<EncodedImage?> {
        let received = try await request(.getAppIcon, expecting: .appIcon)
        guard case .appIcon(let icon) = received.body else {
            throw RequestError.protocolViolation("the response is not an AppIcon")
        }
        return Recorded(value: icon.image, payload: received.payload)
    }

    /// Asks for the layer tree, without screenshots or attributes.
    public func hierarchy() async throws -> Hierarchy {
        try await recordedHierarchy().value
    }

    /// `hierarchy()`, with the bytes of the response.
    public func recordedHierarchy() async throws -> Recorded<Hierarchy> {
        let received = try await request(.getHierarchy, expecting: .hierarchy)
        guard case .hierarchy(let hierarchy) = received.body else {
            throw RequestError.protocolViolation("the response is not a Hierarchy")
        }
        return Recorded(value: hierarchy, payload: received.payload)
    }

    /// Changes one attribute of one layer (P-SET-01). Returns the layer's attributes as the
    /// server read them after the change.
    public func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult {
        guard case .setAttributeResult(let result) =
            try await self.request(.setAttribute(request), expecting: .setAttributeResult).body
        else {
            throw RequestError.protocolViolation("the response is not a SetAttributeResult")
        }
        guard result.layerID == request.layerID else {
            throw RequestError.protocolViolation(
                "the result is for layer \(result.layerID), not \(request.layerID)")
        }
        return result
    }

    /// Asks for a layer and all its descendants (P-HIER-10). The first node is the layer.
    public func subtree(of rootID: UInt64) async throws -> Hierarchy {
        guard case .hierarchy(let hierarchy) =
            try await request(.getSubtree(GetSubtree(rootID: rootID)), expecting: .hierarchy).body
        else {
            throw RequestError.protocolViolation("the response is not a Hierarchy")
        }
        guard hierarchy.nodes.first?.id == rootID else {
            throw RequestError.protocolViolation("the subtree does not start at layer \(rootID)")
        }
        return hierarchy
    }

    /// Asks for the overrides of the app's trait environment and its current traits
    /// (P-ENV-01). Protocol 1.2: below it nothing is sent, and it throws `.unsupported`.
    public func environment() async throws -> Environment {
        try await environmentRequest(.getEnvironment).value
    }

    /// `environment()`, with the bytes of the response (C-ENV-04).
    public func recordedEnvironment() async throws -> Recorded<Environment> {
        try await environmentRequest(.getEnvironment)
    }

    /// Replaces every override of the app's trait environment (P-ENV-02); `.unspecified`
    /// removes them all. Returns the environment after the change. Protocol 1.2, as
    /// `environment()`.
    public func setEnvironment(_ overrides: Traits) async throws -> Environment {
        try await environmentRequest(.setEnvironment(SetEnvironment(overrides: overrides))).value
    }

    private func environmentRequest(_ body: Body) async throws -> Recorded<Environment> {
        guard phase == .ready else { throw RequestError.disconnected }
        // C-WIRE-12: a peer below 1.2 does not know the message.
        guard let negotiatedVersion, negotiatedVersion.minor >= 2 else {
            throw RequestError.unsupported
        }
        let received = try await request(body, expecting: .environment)
        guard case .environment(let environment) = received.body else {
            throw RequestError.protocolViolation("the response is not an Environment")
        }
        return Recorded(value: environment, payload: received.payload)
    }

    /// Asks for screenshots and attributes of layers. The response is a stream (P-REQ-03).
    public func layerDetails(_ request: GetLayerDetails) -> LayerDetailsStream {
        let (chunks, cancel) = openStream(request, sink: StreamSink.plain)
        return LayerDetailsStream(chunks: chunks, cancelAction: cancel)
    }

    /// `layerDetails(_:)`, with the bytes of each chunk's frame.
    public func recordedLayerDetails(_ request: GetLayerDetails) -> RecordedLayerDetailsStream {
        let (chunks, cancel) = openStream(request, sink: StreamSink.recorded)
        return RecordedLayerDetailsStream(chunks: chunks, cancelAction: cancel)
    }

    /// Sends a `GetLayerDetails` whose chunks come as `Element`s, which `sink` makes the
    /// session's way to hand them out. Returns the chunks and what cancels the request; a
    /// reader that stops reading cancels it as well.
    private func openStream<Element: Sendable>(
        _ request: GetLayerDetails,
        sink: (AsyncThrowingStream<Element, any Error>.Continuation) -> StreamSink
    ) -> (ChunkSequence<Element>, @Sendable () async -> Void) {
        let (chunks, continuation) = AsyncThrowingStream.makeStream(of: Element.self)
        let (id, cancel) = startStream(request, sink: sink(continuation))
        continuation.onTermination = { termination in
            guard case .cancelled = termination else { return }
            Task { await cancel() }
        }
        return (ChunkSequence(chunks, token: consumptionToken(for: id)), cancel)
    }

    /// What tells this session that the reader of stream `id` took a chunk, or let go of the
    /// stream (C-CONN-12). Nil `id`: a stream that was never sent.
    private func consumptionToken(for id: UInt32?) -> ConsumptionToken {
        guard let id else { return ConsumptionToken(onTake: {}, onRelease: {}) }
        return ConsumptionToken(
            onTake: { [weak self] in Task { await self?.took(from: id) } },
            onRelease: { [weak self] in Task { await self?.released(id) } })
    }

    /// Sends a `GetLayerDetails` whose chunks go to `sink`. Returns its request ID, nil when
    /// nothing was sent, and what cancels it. A reader that stops reading (its task cancelled,
    /// or the stream dropped) no longer wants the rest: the caller wires the stream's
    /// termination to the returned action (P-REQ-04).
    private func startStream(
        _ request: GetLayerDetails, sink: StreamSink
    ) -> (UInt32?, @Sendable () async -> Void) {
        guard phase == .ready else {
            sink.finish(throwing: RequestError.disconnected)
            return (nil, {})
        }
        let id = takeRequestID()
        pending.store(StreamRequest(continuation: sink, sentAt: clock.now()), for: id)
        startWatchdog()
        enqueue(Frame(requestID: id, body: .getLayerDetails(request)))
        return (id, { [weak self] in
            await self?.cancelStream(id)
        })
    }

    /// Closes the connection. Requests in flight end with `RequestError.disconnected`.
    public func close() {
        shutDown()
    }

    private func request(_ body: Body, expecting: ResponseKind) async throws -> Received {
        guard phase == .ready else { throw RequestError.disconnected }
        let id = takeRequestID()
        return try await withCheckedThrowingContinuation { continuation in
            pending.insert(
                SingleRequest(expects: expecting, continuation: continuation, sentAt: clock.now()),
                for: id)
            startWatchdog()
            enqueue(Frame(requestID: id, body: body))
        }
    }

    private func cancelStream(_ id: UInt32) {
        guard pending.markCancelling(id) else { return }
        // Cancel takes a request ID of its own (P-REQ-01). It goes out before the frames
        // already read are handed out: they may end the stream.
        enqueue(Frame(requestID: takeRequestID(), body: .cancel(Cancel(targetRequestID: id))))
        // What it left untaken holds nothing up any more; what still comes is dropped.
        ledger.forget(id)
        resumeReadingIfPossible()
    }

    private func takeRequestID() -> UInt32 {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    // MARK: - Backpressure (C-CONN-12)

    /// Whether some stream has as much waiting for its reader as is allowed.
    var isPaused: Bool { ledger.isPaused }

    /// Whether the reading task waits for the readers to catch up. For tests.
    package var isReadingPaused: Bool { readGate.isClosed }

    /// Requests sent that wait for their single answer. For tests (C-SCALE-02).
    package var pendingRequestCount: Int { pending.singleCount }

    /// Streams asked for that have not ended: not answered to the end, not cancelled to the
    /// end, not cut off. For tests (C-SCALE-02).
    package var openStreamCount: Int { pending.streamCount }

    /// Chunks that readers have not taken yet, over all streams. For tests.
    package var untakenChunkCount: Int { ledger.untakenChunkCount }

    private func took(from id: UInt32) {
        guard ledger.take(from: id) else { return }
        resumeReadingIfPossible()
    }

    /// Nothing holds the stream any more: what it left untaken goes, and a stream still under
    /// way is cancelled as a reader that stops reading cancels it.
    private func released(_ id: UInt32) {
        ledger.forget(id)
        cancelStream(id)
        resumeReadingIfPossible()
    }

    /// Hands out the frames already read, then lets the reading task go on, unless a reader is
    /// still too far behind.
    private func resumeReadingIfPossible() {
        guard phase == .ready, !isPaused else { return }
        drainReader()
        guard !isPaused, readGate.isClosed else { return }
        lastHeard = clock.now()
        readGate.open()
    }

    /// The gate to pass before the next read: closed while a reader is too far behind.
    func gateBeforeReading() -> ReadGate {
        if phase == .ready, isPaused { readGate.close() }
        return readGate
    }

    // MARK: - Writing

    private func enqueue(_ frame: Frame) {
        outgoingContinuation.yield(FrameCodec.encodeForStream(frame))
    }

    private func startWriting() {
        let channel = self.channel
        let outgoing = self.outgoing
        writeTask = Task {
            for await data in outgoing {
                // A failed send is not acted on here: the reading side notices that the
                // connection ended, after delivering what the peer sent before it closed.
                guard (try? await channel.send(data)) != nil else { return }
            }
        }
    }

    // MARK: - Ending

    /// The peer broke the protocol (C-CONN-10): the connection is closed, and the log says
    /// why.
    func violation(_ message: String) {
        Self.log.error("closing the connection: \(message, privacy: .public)")
        shutDown()
    }

    /// Closes the connection and ends everything that waits on it. Safe to call repeatedly.
    func shutDown() {
        guard phase != .closed else { return }
        phase = .closed
        channel.close()
        outgoingContinuation.finish()
        readTask?.cancel()
        watchdog?.cancel()
        watchdog = nil
        ledger.forgetAll()
        readGate.open()

        pending.endAll(throwing: .disconnected)
        eventContinuation.yield(.closed)
        eventContinuation.finish()
    }
}
