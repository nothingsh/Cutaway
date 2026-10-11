import CutawayWire
import Foundation

// `startReading()`, `drainReader()`, `bufferedFrame()` and `name(of:)` are internal only so
// Session.swift can call them.
extension Session {
    // MARK: - Reading

    func startReading() {
        let channel = self.channel
        readTask = Task { [weak self] in
            while true {
                // Not a byte more while a reader is too far behind (C-CONN-12). The wait holds
                // the gate, not the session.
                guard let gate = await self?.gateBeforeReading() else { return }
                await gate.pass()
                let bytes: Data?
                do {
                    bytes = try await channel.receive()
                } catch {
                    bytes = nil
                }
                guard let bytes else { break }
                guard let self else { return }
                await self.ingest(bytes)
            }
            await self?.shutDown()
        }
    }

    private func ingest(_ bytes: Data) {
        lastHeard = clock.now()
        reader.append(bytes)
        drainReader()
    }

    /// Hands out the complete frames in the reader. Stops while a reader is too far behind;
    /// the rest waits in the reader until it catches up.
    func drainReader() {
        do {
            while phase == .ready, !isPaused, let (frame, payload) = try bufferedFrame() {
                handle(frame, payload: payload)
            }
        } catch {
            // A frame that is too long or does not verify (P-FRAME-03).
            Self.log.error("closing the connection: \(String(describing: error), privacy: .public)")
            shutDown()
        }
    }

    /// The next complete frame in the reader, decoded, with its buffer. The buffer is the
    /// reader's own copy; keeping it for a recorded request copies nothing more.
    func bufferedFrame() throws -> (Frame, Data)? {
        do {
            guard let payload = try reader.nextPayload() else { return nil }
            return (try FrameCodec.decode(payload), payload)
        } catch {
            throw RequestError.protocolViolation(String(describing: error))
        }
    }

    // MARK: - Incoming frames

    private func handle(_ frame: Frame, payload: Data) {
        guard let body = frame.body else {
            violation("a frame without a body")
            return
        }
        switch body {
        case .hello, .getAppIcon, .getHierarchy, .getLayerDetails, .cancel, .setAttribute,
             .getSubtree:
            // C-CONN-10: a second Hello, or a message only a client sends.
            violation("the server sent \(Self.name(of: body))")
        case .appStateChanged(let state):
            eventContinuation.yield(.appStateChanged(state))
        case .appIcon, .hierarchy, .setAttributeResult:
            complete(frame.requestID, with: Received(body: body, payload: payload))
        case .error(let error):
            fail(frame.requestID, with: error)
        case .layerDetailsChunk(let chunk):
            receive(chunk, payload: payload, for: frame.requestID)
        case .streamEnd(let end):
            finish(frame.requestID, with: end)
        }
    }

    private func complete(_ id: UInt32, with received: Received) {
        let body = received.body
        switch pending[id] {
        case .single(let request):
            let matches: Bool
            switch (request.expects, body) {
            case (.appIcon, .appIcon), (.hierarchy, .hierarchy),
                 (.setAttributeResult, .setAttributeResult):
                matches = true
            default: matches = false
            }
            pending.remove(id)
            guard matches else {
                let error = RequestError.protocolViolation(
                    "request \(id) was answered with \(Self.name(of: body))")
                request.continuation.resume(throwing: error)
                violation("request \(id) was answered with \(Self.name(of: body))")
                return
            }
            request.continuation.resume(returning: received)
        case .stream:
            violation("stream \(id) was answered with \(Self.name(of: body))")
        case nil:
            // The request timed out earlier. A late response is dropped.
            break
        }
    }

    private func fail(_ id: UInt32, with error: ServerError) {
        // Nothing happens for an error that answers no request (request ID 0), or a late one.
        pending.end(id, throwing: Self.requestError(for: error))
    }

    private func receive(_ chunk: LayerDetailsChunk, payload: Data, for id: UInt32) {
        switch pending[id] {
        case .stream(var stream):
            guard chunk.sequence == stream.nextSequence else {
                pending.remove(id)
                stream.continuation.finish(throwing: RequestError.protocolViolation(
                    "chunk \(chunk.sequence) arrived where \(stream.nextSequence) was due"))
                violation("chunk \(chunk.sequence) arrived where \(stream.nextSequence) was due")
                return
            }
            stream.nextSequence += 1
            if !stream.isCancelling {
                stream.continuation.yield(chunk.details, payload: payload)
                ledger.add(chunkOf: payload.count, to: id)
            }
            pending.store(stream, for: id)
        case .single:
            violation("request \(id) is not a stream but received a chunk")
        case nil:
            break
        }
    }

    private func finish(_ id: UInt32, with end: StreamEnd) {
        switch pending[id] {
        case .stream(let stream):
            pending.remove(id)
            guard end.chunkCount == stream.nextSequence else {
                stream.continuation.finish(throwing: RequestError.protocolViolation(
                    "StreamEnd counts \(end.chunkCount) chunks, \(stream.nextSequence) arrived"))
                violation("StreamEnd counts \(end.chunkCount) chunks, \(stream.nextSequence) arrived")
                return
            }
            switch end.status {
            case .completed where !stream.isCancelling:
                stream.continuation.finish()
            case .completed, .cancelled:
                // A stream that completed after it was cancelled lost the chunks that were
                // dropped in between, so it is not reported as complete.
                stream.continuation.finish(throwing: RequestError.cancelled)
            case .failed:
                stream.continuation.finish(
                    throwing: end.error.map(Self.requestError(for:))
                        ?? RequestError.server(ServerError(code: .unknown, message: nil)))
            }
        case .single:
            violation("request \(id) is not a stream but received a StreamEnd")
        case nil:
            break
        }
    }

    private static func requestError(for error: ServerError) -> RequestError {
        // C-CONN-08, C-CONN-11: these are states of the app or answers about the request,
        // not failures of the connection.
        switch error.code {
        case .appNotActive: .appNotActive(message: error.message)
        case .layerNotFound: .layerNotFound(message: error.message)
        case .attributeNotEditable: .attributeNotEditable(message: error.message)
        case .invalidAttributeValue: .invalidAttributeValue(message: error.message)
        default: .server(error)
        }
    }

    static func name(of body: Body?) -> String {
        switch body {
        case nil: return "no body"
        case .hello: return "Hello"
        case .getAppIcon: return "GetAppIcon"
        case .appIcon: return "AppIcon"
        case .getHierarchy: return "GetHierarchy"
        case .hierarchy: return "Hierarchy"
        case .getLayerDetails: return "GetLayerDetails"
        case .layerDetailsChunk: return "LayerDetailsChunk"
        case .streamEnd: return "StreamEnd"
        case .cancel: return "Cancel"
        case .error: return "Error"
        case .appStateChanged: return "AppStateChanged"
        case .setAttribute: return "SetAttribute"
        case .setAttributeResult: return "SetAttributeResult"
        case .getSubtree: return "GetSubtree"
        }
    }
}
