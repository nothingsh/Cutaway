import CutawayWire

/// What a negotiated protocol version has (P-HELLO-04), in one place: the session refuses
/// requests the version does not have, and the inspection shows only what the app can do.
public struct ProtocolFeatures: Equatable, Sendable {
    /// `GetSubtree` and `SetAttribute`: protocol 0.3.
    public var sendsSubtrees: Bool
    public var changesAttributes: Bool
    /// `wantConstraints` and the constraints in a layer's detail: protocol 0.4.
    public var givesConstraints: Bool

    public init(negotiated version: Version) {
        let minor = { (n: UInt16) in version.major > 0 || version.minor >= n }
        sendsSubtrees = minor(3)
        changesAttributes = minor(3)
        givesConstraints = minor(4)
    }
}
