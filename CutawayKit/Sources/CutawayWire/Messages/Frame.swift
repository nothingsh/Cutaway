import Foundation

// The value types of the wire protocol. They mirror Protocol/schema/cutaway.fbs.
//
// How absent fields read (C-WIRE-04): scalars and enums take their default (0, false, the
// first enum member); strings, structs, sub-tables and unions are nil; vectors are empty.

/// One frame: the payload that follows the 4-byte length on the wire.
public struct Frame: Equatable, Sendable {
    /// 0 for the handshake, for events and for errors that answer no request.
    public var requestID: UInt32
    /// Nil when the frame carries no body.
    public var body: Body?

    public init(requestID: UInt32, body: Body?) {
        self.requestID = requestID
        self.body = body
    }
}

public enum Body: Equatable, Sendable {
    case hello(Hello)
    case getAppIcon
    case appIcon(AppIcon)
    case getHierarchy
    case hierarchy(Hierarchy)
    case getLayerDetails(GetLayerDetails)
    case layerDetailsChunk(LayerDetailsChunk)
    case streamEnd(StreamEnd)
    case cancel(Cancel)
    case error(ServerError)
    case appStateChanged(AppState)
    // Protocol 0.3
    case setAttribute(SetAttribute)
    case setAttributeResult(SetAttributeResult)
    case getSubtree(GetSubtree)
    // Protocol 1.2
    case getEnvironment
    case setEnvironment(SetEnvironment)
    case environment(Environment)
}
