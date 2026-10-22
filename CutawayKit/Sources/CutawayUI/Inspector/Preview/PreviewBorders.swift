import AppKit
import CutawayModel
import CutawayRender
import CutawayWire

/// How the preview outlines the layers (C-PREV-17): the options and the tree whose layers'
/// kinds give the colours. It sets the borders' part of a `RenderStyle`.
@MainActor
struct PreviewBorders {
    var options = BorderOptions()
    var tree = LayerTree.empty
    /// The layers' kinds as last worked out. Shared by the copies: it only remembers.
    private let icons = LayerIconMemo()

    /// How opaque a border in its kind's colour is: strong for the app's own classes, faint
    /// for the system's.
    static let appClassOpacity: Float = 0.95
    static let systemClassOpacity: Float = 0.42
    /// The colour of a layer that is not outlined.
    static let notOutlined = SIMD4<Float>(repeating: 0)

    /// Sets the borders of `style`, whose colours are the light or dark appearance's.
    func apply(to style: inout RenderStyle, dark: Bool) {
        style.drawsBorders = options.showsBorders
        style.bordersRecede = options.style == .byKind
        style.borderColors = borderColors(plain: style.border, dark: dark)
    }

    /// The layers whose border is not `plain`: by kind, every layer that is not a layer alone;
    /// with only the app's own classes, every layer that is not of one, which is not outlined.
    func borderColors(plain: SIMD4<Float>, dark: Bool) -> [UInt64: SIMD4<Float>] {
        let byKind = options.style == .byKind
        guard options.showsBorders, byKind || options.onlyAppClasses else { return [:] }
        var palette: [LayerIcon.Category: SIMD4<Float>] = [:]
        var colors: [UInt64: SIMD4<Float>] = [:]
        icons.forEachLayer(of: tree) { id, icon in
            if options.onlyAppClasses, !icon.isAppClass {
                colors[id] = Self.notOutlined
            } else if byKind, icon.category != .layer {
                let color: SIMD4<Float>
                if let known = palette[icon.category] {
                    color = known
                } else {
                    color = Self.color(of: icon.category, dark: dark)
                    palette[icon.category] = color
                }
                let opacity = icon.isAppClass ? Self.appClassOpacity : Self.systemClassOpacity
                colors[id] = color * opacity
            }
        }
        return colors
    }

    /// A kind's colour as the light or dark appearance has it, opaque and premultiplied: the
    /// colour of its icon (C-HIER-11).
    static func color(of category: LayerIcon.Category, dark: Bool) -> SIMD4<Float> {
        let dynamic = LayerIconImage.color(category)
        var resolved = dynamic
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = dynamic.usingColorSpace(.sRGB) ?? dynamic
        }
        return RenderStyle.premultiplied(
            Float(resolved.redComponent), Float(resolved.greenComponent),
            Float(resolved.blueComponent), 1)
    }
}

/// The icons of a tree's layers, each kept with the node it was worked out from. A tree that
/// comes again, as after every change of an attribute, has nearly every node as it was: their
/// icons are not worked out again, which matches each class name against some thirty endings.
@MainActor
final class LayerIconMemo {
    private var entries: [UInt64: (node: LayerNode, icon: LayerIcon)] = [:]

    /// Calls `body` with every layer of `tree` and its icon, in the tree's order. Layers no
    /// longer in the tree are forgotten.
    func forEachLayer(of tree: LayerTree, _ body: (UInt64, LayerIcon) -> Void) {
        var kept: [UInt64: (node: LayerNode, icon: LayerIcon)] = [:]
        kept.reserveCapacity(tree.ids.count)
        for id in tree.ids {
            guard let node = tree.node(id) else { continue }
            let icon: LayerIcon
            if let known = entries[id], known.node == node {
                icon = known.icon
            } else {
                icon = LayerIcon(node)
            }
            kept[id] = (node, icon)
            body(id, icon)
        }
        entries = kept
    }
}
