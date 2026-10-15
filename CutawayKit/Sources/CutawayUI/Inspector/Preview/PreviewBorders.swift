import AppKit
import CutawayModel
import CutawayRender

/// How the preview outlines the layers (C-PREV-17): the options and the tree whose layers'
/// kinds give the colours. It sets the borders' part of a `RenderStyle`.
@MainActor
struct PreviewBorders {
    var options = BorderOptions()
    var tree = LayerTree.empty

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
        for layer in tree.layers(within: nil) {
            let icon = LayerIcon(tree.node(layer.id))
            if options.onlyAppClasses, !icon.isAppClass {
                colors[layer.id] = Self.notOutlined
            } else if byKind, icon.category != .layer {
                let color: SIMD4<Float>
                if let known = palette[icon.category] {
                    color = known
                } else {
                    color = Self.color(of: icon.category, dark: dark)
                    palette[icon.category] = color
                }
                let opacity = icon.isAppClass ? Self.appClassOpacity : Self.systemClassOpacity
                colors[layer.id] = color * opacity
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
