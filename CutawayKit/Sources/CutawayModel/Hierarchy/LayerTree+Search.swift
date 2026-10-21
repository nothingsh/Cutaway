import CutawayWire
import Foundation

/// The rows a search leaves in the hierarchy list (C-HIER-04): the layers that match, and
/// their ancestors so that each match is shown where it is in the tree.
public struct HierarchyFilter: Equatable, Sendable {
    /// What is searched for, without the white space around it. Never empty.
    public let text: String
    public let matches: Set<UInt64>
    /// The matches and their ancestors, up to the root of the part of the tree searched.
    public let shown: Set<UInt64>

    /// Searches the part of the tree `layers(within:)` gives for `root`. Nil when the text is
    /// only white space: there is no search. `untitled` is what the interface calls a layer
    /// without a name.
    public init?(text: String, tree: LayerTree, within root: UInt64?, untitled: String = "") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var matches = Set<UInt64>()
        var shown = Set<UInt64>()
        for layer in tree.layers(within: root) where tree.matches(layer.id, trimmed, untitled: untitled) {
            matches.insert(layer.id)
            // Up the parents until one is shown already, whose ancestors then are too, or the
            // root of the part searched.
            var current: UInt64? = layer.id
            while let id = current, shown.insert(id).inserted, id != root {
                current = tree.parent(of: id)
            }
        }
        self.text = trimmed
        self.matches = matches
        self.shown = shown
    }
}

extension LayerTree {
    /// Whether the layer's title, a virtual node's name, one of its class names (the layer's,
    /// the view's and the view controller's, raw and readable), or one of the members that hold it as the list shows
    /// them ("Owner.name") contains the text, ignoring case (C-HIER-04, C-HIER-07). A layer
    /// without a class name has the title `untitled`, the interface's name for it. The
    /// comparison does not depend on the language settings, so it reads the same on every Mac.
    public func matches(_ id: UInt64, _ text: String, untitled: String = "") -> Bool {
        guard let node = node(id) else { return false }
        // Each name once: the readable and the raw names are often the same, and the title
        // is one of the class names unless the layer has none. Searched
        // one by one, without gathering them, for thousands of layers at every keystroke.
        func found(_ name: String?) -> Bool {
            guard let name, !name.isEmpty else { return false }
            return name.range(of: text, options: .caseInsensitive) != nil
        }
        // A virtual node's name, which only virtual nodes have (C-HIER-16).
        if found(node.name) { return true }
        let a = node.viewDisplayClassName, b = node.viewClassName
        let c = node.displayClassName, d = node.className
        let e = node.viewControllerDisplayClassName, f = node.viewControllerClassName
        if found(a) || (b != a && found(b)) || (c != a && c != b && found(c))
            || (d != a && d != b && d != c && found(d)) || found(e) || (f != e && found(f))
        {
            return true
        }
        let hasClassName =
            a?.isEmpty == false || b?.isEmpty == false || c?.isEmpty == false
                || d?.isEmpty == false
        if !hasClassName, found(untitled) { return true }
        guard !node.memberReferences.isEmpty else { return false }
        return memberTitles(of: id).contains(where: found)
    }

    /// The readable name of the view controller whose root view the layer backs, or its
    /// runtime name when the readable one is missing; nil when there is none (P-HIER-07,
    /// C-HIER-07).
    public func viewControllerTitle(of id: UInt64) -> String? {
        guard let node = node(id) else { return nil }
        return [node.viewControllerDisplayClassName, node.viewControllerClassName]
            .compactMap { $0 }.first { !$0.isEmpty }
    }

    /// "Owner.name" for each member that holds the layer or its view, nearest holder first
    /// (P-HIER-08, C-HIER-07). The owner is the class that declares the variable, readable if
    /// it can be; without one the variable's name stands alone. A member without a name is
    /// left out.
    public func memberTitles(of id: UInt64) -> [String] {
        node(id)?.memberReferences.compactMap { member in
            guard let name = member.name, !name.isEmpty else { return nil }
            let owner = [member.ownerDisplayClassName, member.ownerClassName]
                .compactMap { $0 }.first { !$0.isEmpty }
            return owner.map { "\($0).\(name)" } ?? name
        } ?? []
    }
}
