import CutawayScene
import CutawayWire

/// Why an answer to `GetSubtree` cannot replace a subtree of the tree (C-HIER-08).
public enum SubtreeError: Error, Equatable, Sendable {
    /// The answer has no nodes.
    case empty
    /// The answer's root is not in this tree.
    case rootNotInTree(UInt64)
    /// The answer's root has another parent than in this tree: it moved.
    case rootMoved(UInt64)
    /// A node of the answer whose parent is not an earlier node of the answer (P-HIER-10).
    case notInSubtree(id: UInt64, parentID: UInt64)
    /// What results is not a tree, for example because a layer from outside the subtree now
    /// also appears inside it: it moved in.
    case invalid(LayerTreeError)
}

extension LayerTree {
    /// The tree with the subtree rooted at the answer's first node replaced by the answer
    /// (P-HIER-10, C-HIER-08). Everything outside that subtree stays as it was, in the same
    /// place. The key window is the answer's.
    ///
    /// The old subtree's layers are left out and the answer goes where its root was; the tree
    /// is built again from the result. In the wire's pre-order the subtree is one run of
    /// `ids`, but only "parents first" is relied on, which `init` checks.
    public func replacingSubtree(with answer: Hierarchy) throws(SubtreeError) -> LayerTree {
        guard let root = answer.nodes.first else { throw .empty }
        guard let old = entries[root.id] else { throw .rootNotInTree(root.id) }
        guard root.parentID == old.node.parentID else { throw .rootMoved(root.id) }
        var inAnswer: Set<UInt64> = [root.id]
        for node in answer.nodes.dropFirst() {
            guard inAnswer.contains(node.parentID) else {
                throw .notInSubtree(id: node.id, parentID: node.parentID)
            }
            inAnswer.insert(node.id)
        }

        // A layer is inside the old subtree when its parent is: one pass, parents first.
        var inside: Set<UInt64> = [root.id]
        var nodes: [LayerNode] = []
        nodes.reserveCapacity(ids.count + answer.nodes.count)
        for id in ids {
            if id == root.id {
                nodes += answer.nodes
            } else if let parent = parent(of: id), inside.contains(parent) {
                inside.insert(id)
            } else if let entry = entries[id] {
                nodes.append(entry.node)
            }
        }
        do {
            return try LayerTree(Hierarchy(nodes: nodes, keyWindowID: answer.keyWindowID))
        } catch {
            throw .invalid(error)
        }
    }
}

extension LayerTree {
    /// For a subtree the user refreshed (C-DET-07): its layers' images and its ancestors'
    /// group images.
    static func needs(ofSubtree root: UInt64, in tree: LayerTree) -> [TextureNeed] {
        tree.layers(within: root).flatMap { bothKinds($0.id) }
            + tree.path(to: root).dropLast().map { TextureNeed(layerID: $0, kind: .group) }
    }

    /// For a window taken again after changes (C-DET-06): each changed layer with its subtree;
    /// every layer of the window whose node changed or that is new (one that left and came
    /// back still has this round's records); and the group images of everything above a
    /// layer that changed, moved, came or went, which may show it.
    static func needsAfterChanges(
        _ changed: Set<UInt64>, in root: UInt64, from old: LayerTree, to new: LayerTree
    ) -> [TextureNeed] {
        var needs: [TextureNeed] = []
        var touched = changed
        for id in changed where new.contains(id) {
            needs += new.layers(within: id).flatMap { bothKinds($0.id) }
        }
        for layer in new.layers(within: root)
            where !old.contains(layer.id) || old.node(layer.id) != new.node(layer.id)
        {
            needs += bothKinds(layer.id)
            touched.insert(layer.id)
        }
        for layer in old.layers(within: root) where !new.contains(layer.id) {
            touched.insert(layer.id)
        }
        var above = Set<UInt64>()
        for id in touched {
            // A layer that is gone is placed by the old tree; its ancestors still there count.
            let path = new.contains(id) ? new.path(to: id) : old.path(to: id)
            above.formUnion(path.dropLast().filter(new.contains))
        }
        needs += above.map { TextureNeed(layerID: $0, kind: .group) }
        return needs
    }

    private static func bothKinds(_ id: UInt64) -> [TextureNeed] {
        [TextureNeed(layerID: id, kind: .solo), TextureNeed(layerID: id, kind: .group)]
    }
}
