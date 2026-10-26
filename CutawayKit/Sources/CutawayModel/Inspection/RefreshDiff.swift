/// What a refresh changed (C-LIVE-05): the layers that are new, those whose node is not what
/// it was (geometry or any other field, as C-DET-06 judges a change), and how many went. A
/// layer whose screenshot alone changed is not in it: a node holds no image. The list and the
/// preview mark these for a moment; how long is theirs to say.
public struct RefreshDiff: Equatable, Sendable {
    public var added: Set<UInt64>
    public var changed: Set<UInt64>
    public var removed: Int
    /// Counts the refreshes that marked something: each new one starts the marks over.
    public var generation: Int

    public init(added: Set<UInt64>, changed: Set<UInt64>, removed: Int, generation: Int) {
        self.added = added
        self.changed = changed
        self.removed = removed
        self.generation = generation
    }

    /// The difference between `old` and `new` within `root`'s subtree, or the whole trees for
    /// nil; outside a subtree taken again both trees hold the same nodes. Nil when nothing
    /// differs.
    init?(from old: LayerTree, to new: LayerTree, within root: UInt64?, generation: Int) {
        var added = Set<UInt64>()
        var changed = Set<UInt64>()
        for layer in new.layers(within: root) {
            guard let before = old.node(layer.id) else {
                added.insert(layer.id)
                continue
            }
            if before != new.node(layer.id) { changed.insert(layer.id) }
        }
        let removed = old.layers(within: root).count { !new.contains($0.id) }
        guard !added.isEmpty || !changed.isEmpty || removed > 0 else { return nil }
        self.init(added: added, changed: changed, removed: removed, generation: generation)
    }

    /// Whether the layer is marked as new or changed.
    public func marks(_ id: UInt64) -> Bool {
        added.contains(id) || changed.contains(id)
    }
}
