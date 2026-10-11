import CutawayWire
import Foundation

/// Why a `Hierarchy` is not a tree (P-HIER-01, P-HIER-03).
public enum LayerTreeError: Error, Equatable, Sendable {
    /// The node at this position in `nodes` has the ID 0.
    case zeroID(index: Int)
    case duplicateID(UInt64)
    /// The node's parent does not come before it, or does not exist.
    case parentNotBefore(id: UInt64, parentID: UInt64)

    /// For the person looking at the list. Reads as the end of a sentence.
    public var explanation: String {
        switch self {
        case .zeroID(let index):
            return "node \(index) has the ID 0"
        case .duplicateID(let id):
            return "the ID \(id) appears more than once"
        case .parentNotBefore(let id, let parentID):
            return "layer \(id) does not come after its parent \(parentID)"
        }
    }
}

/// The layers of an app as a tree. Built once from a `Hierarchy` and not changed afterwards.
public struct LayerTree: Equatable, Sendable {
    // `Entry` and the getter of `entries` are internal only so that LayerTree+Subtree.swift
    // can reach them.

    struct Entry: Equatable, Sendable {
        var node: LayerNode
        var children: [UInt64] = []
        var isDimmed: Bool
    }

    public static let empty = Self()

    /// The root layers of the windows, back to front (P-HIER-02).
    public private(set) var roots: [UInt64] = []
    /// 0 when there is no key window.
    public private(set) var keyWindowID: UInt64 = 0
    /// Every layer, in the order of the wire: a layer's parent comes before it.
    public private(set) var ids: [UInt64] = []
    private(set) var entries: [UInt64: Entry] = [:]

    private init() {}

    /// Builds the tree in one pass, which the wire's pre-order allows (P-HIER-01). A
    /// hierarchy in which a layer comes before its parent, or that breaks P-HIER-03, is
    /// refused as a whole.
    public init(_ hierarchy: Hierarchy) throws(LayerTreeError) {
        keyWindowID = hierarchy.keyWindowID
        ids.reserveCapacity(hierarchy.nodes.count)
        entries.reserveCapacity(hierarchy.nodes.count)
        for (index, node) in hierarchy.nodes.enumerated() {
            guard node.id != 0 else { throw .zeroID(index: index) }
            guard entries[node.id] == nil else { throw .duplicateID(node.id) }

            // A layer nobody can see: hidden or fully transparent, itself or a layer it is
            // inside of (C-HIER-03).
            var isDimmed = node.isHidden || node.opacity == 0
            if node.parentID == 0 {
                roots.append(node.id)
            } else {
                // Only the flag is read: holding the parent's entry would keep a second
                // reference to its children, and every append would copy them.
                guard let parentIsDimmed = entries[node.parentID]?.isDimmed else {
                    throw .parentNotBefore(id: node.id, parentID: node.parentID)
                }
                isDimmed = isDimmed || parentIsDimmed
                entries[node.parentID]?.children.append(node.id)
            }
            entries[node.id] = Entry(node: node, isDimmed: isDimmed)
            ids.append(node.id)
        }
    }

    public var count: Int { ids.count }

    public var isEmpty: Bool { ids.isEmpty }

    public func contains(_ id: UInt64) -> Bool {
        entries[id] != nil
    }

    public func node(_ id: UInt64) -> LayerNode? {
        entries[id]?.node
    }

    /// Nil for a root layer, and for a layer that is not in the tree.
    public func parent(of id: UInt64) -> UInt64? {
        guard let parentID = entries[id]?.node.parentID, parentID != 0 else { return nil }
        return parentID
    }

    /// In the order of the wire: back to front (P-HIER-01).
    public func children(of id: UInt64) -> [UInt64] {
        entries[id]?.children ?? []
    }

    /// The view's readable class name; for a layer that backs no view, the layer's
    /// (C-HIER-01). Falls back to the raw names when the readable ones are missing. Nil when
    /// the layer has no name at all, or is not in the tree: the interface names it
    /// (C-LOC-01).
    public func title(of id: UInt64) -> String? {
        guard let node = entries[id]?.node else { return nil }
        // Name by name, without gathering them: the list asks for every row's title.
        if let name = node.viewDisplayClassName, !name.isEmpty { return name }
        if let name = node.viewClassName, !name.isEmpty { return name }
        if let name = node.displayClassName, !name.isEmpty { return name }
        if let name = node.className, !name.isEmpty { return name }
        return nil
    }

    /// Whether the list shows the layer in a weaker style (C-HIER-03).
    public func isDimmed(_ id: UInt64) -> Bool {
        entries[id]?.isDimmed ?? false
    }

    /// The layers with sublayers that start expanded (C-HIER-09): the tree opens down to the
    /// view controllers on show, the innermost ones included, and no further. A view
    /// controller is on show when its root view is not dimmed and is in the key window, or
    /// in any window when the key window is not in the tree. Without any, every layer of
    /// those windows that is not dimmed opens. Everything else, other windows too, starts
    /// collapsed.
    public func defaultExpansion() -> Set<UInt64> {
        let windows: Set<UInt64> = entries[keyWindowID] != nil ? [keyWindowID] : Set(roots)
        // Each layer's window, parents first as on the wire.
        var windowOf: [UInt64: UInt64] = [:]
        windowOf.reserveCapacity(ids.count)
        var shown: [UInt64] = []
        for id in ids {
            let window = parent(of: id).flatMap { windowOf[$0] } ?? id
            windowOf[id] = window
            guard windows.contains(window), let entry = entries[id], !entry.isDimmed else {
                continue
            }
            if viewControllerTitle(of: id) != nil { shown.append(id) }
        }
        guard !shown.isEmpty else {
            return Set(ids.filter { id in
                guard let entry = entries[id] else { return false }
                return !entry.children.isEmpty && !entry.isDimmed
                    && windowOf[id].map(windows.contains) == true
            })
        }
        // Every layer above a view controller on show. The climb stops at a layer already
        // marked, so that each layer is marked once.
        var above = Set<UInt64>()
        for id in shown {
            var current = parent(of: id)
            while let ancestor = current, above.insert(ancestor).inserted {
                current = parent(of: ancestor)
            }
        }
        // The innermost: no view controller on show below them.
        let innermost = shown.filter { !above.contains($0) && !children(of: $0).isEmpty }
        return above.union(innermost)
    }
}

/// A layer and how deep it is in the part of the tree it was found in: 0 for that part's root.
public struct LayerDepth: Equatable, Sendable {
    public let id: UInt64
    public let depth: Int

    public init(id: UInt64, depth: Int) {
        self.id = id
        self.depth = depth
    }
}

extension LayerTree {
    /// The layers of a part of the tree with their depths there, in the order of the wire:
    /// for nil the whole tree, each window's root layer at depth 0; otherwise `root` at depth
    /// 0 and everything inside it. Empty for a root that is not in the tree.
    public func layers(within root: UInt64?) -> [LayerDepth] {
        if let root, !contains(root) { return [] }
        var depths: [UInt64: Int] = [:]
        var result: [LayerDepth] = []
        for id in ids {
            let depth: Int
            if id == root {
                depth = 0
            } else if let parent = parent(of: id) {
                // A layer's parent comes before it, so a parent inside the part has its depth.
                guard let parentDepth = depths[parent] else { continue }
                depth = parentDepth + 1
            } else if root == nil {
                depth = 0
            } else {
                continue
            }
            depths[id] = depth
            result.append(LayerDepth(id: id, depth: depth))
        }
        return result
    }

    /// From the window's root layer down to the layer, both included. Empty for a layer that
    /// is not in the tree.
    public func path(to id: UInt64) -> [UInt64] {
        guard contains(id) else { return [] }
        var path = [id]
        var current = parent(of: id)
        while let ancestor = current {
            path.append(ancestor)
            current = parent(of: ancestor)
        }
        return path.reversed()
    }

    /// Whether the layer is `root` or inside it.
    public func isWithin(_ id: UInt64, root: UInt64) -> Bool {
        guard contains(id) else { return false }
        var current: UInt64? = id
        while let layer = current {
            if layer == root { return true }
            current = parent(of: layer)
        }
        return false
    }
}

extension LayerTree {
    /// The row that stands for a layer in the list: the layer itself, or the outermost
    /// collapsed node it is inside of, looking no higher than the focus.
    static func standIn(
        for id: UInt64, in tree: LayerTree, expansion: [UInt64: Bool], focus: UInt64?
    ) -> UInt64 {
        var result = id
        var current = id == focus ? nil : tree.parent(of: id)
        while let ancestor = current {
            if expansion[ancestor] == false { result = ancestor }
            current = ancestor == focus ? nil : tree.parent(of: ancestor)
        }
        return result
    }
}
