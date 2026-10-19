// MARK: - Control

public enum ErrorCode: Sendable {
    case unknown, malformedFrame, unexpectedMessage, busy, appNotActive, internalError
    // Protocol 0.3
    case layerNotFound, attributeNotEditable, invalidAttributeValue
    // Protocol 1.2
    case notSupported
}

public enum StreamStatus: Sendable { case completed, cancelled, failed }

public enum AppState: Sendable { case active, inactive, background }

/// The protocol's `Error` message.
public struct ServerError: Equatable, Sendable {
    public var code: ErrorCode
    /// English text for people. Never branch on it.
    public var message: String?

    public init(code: ErrorCode, message: String?) {
        self.code = code
        self.message = message
    }
}

public struct StreamEnd: Equatable, Sendable {
    public var status: StreamStatus
    public var chunkCount: UInt32
    /// Set when `status` is `.failed`.
    public var error: ServerError?

    public init(status: StreamStatus, chunkCount: UInt32, error: ServerError?) {
        self.status = status
        self.chunkCount = chunkCount
        self.error = error
    }
}

public struct Cancel: Equatable, Sendable {
    public var targetRequestID: UInt32

    public init(targetRequestID: UInt32) {
        self.targetRequestID = targetRequestID
    }
}
