// MARK: - Hierarchy changes (protocol 1.3)

/// Turns hierarchy change notifications on or off for the connection (P-WATCH-01). Answered with
/// `WatchHierarchyResult`.
public struct WatchHierarchy: Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}

/// Whether notifications are on once the request is done (P-WATCH-01).
public struct WatchHierarchyResult: Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}

/// An event: part of the hierarchy changed (P-WATCH-02, 03). As sent; a reader takes `whole`, or
/// no roots at all, as "get the whole hierarchy again".
public struct HierarchyChanged: Equatable, Sendable {
    /// The nodes whose subtrees changed, none in another's subtree.
    public var roots: [UInt64]
    public var whole: Bool

    public init(roots: [UInt64], whole: Bool) {
        self.roots = roots
        self.whole = whole
    }
}
