import CutawayWire

public enum RequestError: Error, Equatable {
    /// No frame arrived for the request within the timeout.
    case timedOut
    /// The connection ended before the request did.
    case disconnected
    /// The stream ended because it was cancelled.
    case cancelled
    /// The app is not active, so it cannot capture (P-APP-01).
    case appNotActive(message: String?)
    case server(ServerError)
    /// The peer broke the protocol. The text is for logs. The connection is closed, except
    /// when only the content of an answer is wrong: the frame itself is valid and matched to
    /// its request, so there is no need to drop the connection.
    case protocolViolation(String)
    /// The layer named in the request does not exist (P-HIER-11, P-SET-03). Protocol 0.3.
    case layerNotFound(message: String?)
    /// The attribute does not exist or cannot be changed (P-SET-03). Protocol 0.3.
    case attributeNotEditable(message: String?)
    /// The server rejected the value (P-SET-03). Protocol 0.3.
    case invalidAttributeValue(message: String?)
    /// The source of the frames cannot answer this kind of request at all. Nothing was sent.
    /// A session never throws it; a source that stands in for one may.
    case unsupported
}
