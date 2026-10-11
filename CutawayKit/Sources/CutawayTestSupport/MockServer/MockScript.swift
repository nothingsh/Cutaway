import CutawayWire
import Foundation

/// A one-time signal for a `MockScript`'s `hold` step: the server waits there until a test
/// opens it. Lets a test look at what a client did with part of a response, without timing.
public actor MockGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Lets every server that waits at this gate, and every one that comes to it later, go on.
    public func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// The kind of message a frame carries, without its content.
public enum MessageKind: Equatable, Sendable {
    case none, hello, getAppIcon, appIcon, getHierarchy, hierarchy, getLayerDetails
    case layerDetailsChunk, streamEnd, cancel, error, appStateChanged
    case setAttribute, setAttributeResult, getSubtree

    public init(_ body: Body?) {
        switch body {
        case nil: self = .none
        case .hello: self = .hello
        case .getAppIcon: self = .getAppIcon
        case .appIcon: self = .appIcon
        case .getHierarchy: self = .getHierarchy
        case .hierarchy: self = .hierarchy
        case .getLayerDetails: self = .getLayerDetails
        case .layerDetailsChunk: self = .layerDetailsChunk
        case .streamEnd: self = .streamEnd
        case .cancel: self = .cancel
        case .error: self = .error
        case .appStateChanged: self = .appStateChanged
        case .setAttribute: self = .setAttribute
        case .setAttributeResult: self = .setAttributeResult
        case .getSubtree: self = .getSubtree
        }
    }
}

/// What a `MockServer` does on each connection.
public struct MockScript: Sendable {
    public enum Step: Sendable {
        /// Waits for the client's next frame, which must be of this kind. `as` is the request
        /// ID that later `send` steps use to refer to it; the client's real ID replaces it.
        case expect(MessageKind, as: UInt32)
        /// Sends a frame. Its request ID is replaced by the client's real ID for the matching
        /// `expect`; an ID no `expect` introduced, 0 in particular, is sent unchanged.
        case send(Frame)
        /// Sends bytes as they are, for frames that are not valid.
        case sendBytes(Data)
        /// Sends `count` frames, each made when its turn comes and not recorded in
        /// `sentPayloads`, so that a test can send more than it would want to hold (C-CONN-12).
        /// Request IDs are replaced as for `send`.
        case sendMany(count: Int, make: @Sendable (Int) -> Frame)
        case pause(Duration)
        /// Waits until the gate is open. A test that stops the server while it waits here
        /// leaves the connection's task waiting until the gate opens.
        case hold(MockGate)
        /// Closes the connection and ends the script.
        case close
        /// Answers every further frame by its content until the client leaves. Ends the
        /// script.
        case respond(MockResponder)
    }

    public var steps: [Step]
    /// Whether the server closes the connection after the last step. When false it stays
    /// connected until the client leaves, recording any further frames.
    public var closesWhenDone: Bool

    public init(steps: [Step], closesWhenDone: Bool = false) {
        self.steps = steps
        self.closesWhenDone = closesWhenDone
    }

    /// The frames of fixture scenarios, one scenario after another: client frames become
    /// `expect` steps and server frames become `send` steps (Protocol/fixtures/README.md).
    public static func fixtures(
        _ scenarios: String..., closesWhenDone: Bool = false
    ) throws -> Self {
        var steps: [Step] = []
        for scenario in scenarios {
            for fixture in try Fixtures.frames(scenario: scenario) {
                let frame = try FrameCodec.decode(fixture.payload)
                switch fixture.direction {
                case .clientToServer:
                    steps.append(.expect(MessageKind(frame.body), as: frame.requestID))
                case .serverToClient:
                    steps.append(.send(frame))
                }
            }
        }
        return Self(steps: steps, closesWhenDone: closesWhenDone)
    }
}

extension MockScript {
    /// The script with the attributes in every chunk it sends renamed (C-ATTR-03).
    public func renamingAttributes() -> MockScript {
        MockScript(
            steps: steps.map { step in
                guard case .send(let frame) = step, case .layerDetailsChunk(var chunk) = frame.body
                else { return step }
                chunk.details = chunk.details.map { detail in
                    var detail = detail
                    detail.attributeGroups = Fixtures.renamingAttributes(detail.attributeGroups)
                    return detail
                }
                return .send(Frame(requestID: frame.requestID, body: .layerDetailsChunk(chunk)))
            },
            closesWhenDone: closesWhenDone)
    }

    /// A `GetLayerDetails`, answered with one chunk of `details` and a completed end.
    public static func layerDetailsSteps(_ details: [LayerDetail], as requestID: UInt32) -> [Step] {
        [
            .expect(.getLayerDetails, as: requestID),
            .send(Frame(
                requestID: requestID,
                body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: details)))),
            .send(Frame(
                requestID: requestID,
                body: .streamEnd(StreamEnd(status: .completed, chunkCount: 1, error: nil)))),
        ]
    }
}

extension MockScript {
    /// The same script with the server's `Hello` giving `version` instead of the fixture's.
    public func serverSpeaking(_ version: Version) -> MockScript {
        var script = self
        for (index, step) in steps.enumerated() {
            guard case .send(var frame) = step, case .hello(var hello) = frame.body else { continue }
            hello.protocolVersion = version
            frame.body = .hello(hello)
            script.steps[index] = .send(frame)
            break
        }
        return script
    }
}
