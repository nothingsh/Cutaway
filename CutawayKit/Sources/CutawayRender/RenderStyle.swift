import CutawayScene
import Metal

/// The colours of the preview, premultiplied RGBA from 0 to 1.
public struct RenderStyle: Equatable, Sendable {
    public var background: SIMD4<Float>
    /// Around every displayed layer, above its image.
    public var border: SIMD4<Float>
    public var hoveredFill: SIMD4<Float>
    public var hoveredBorder: SIMD4<Float>
    public var selectedFill: SIMD4<Float>
    public var selectedBorder: SIMD4<Float>
    /// A layer that cannot be seen, drawn because hidden layers are shown (C-REND-06): its
    /// image at this opacity, under a tint, with a border of its own.
    public var ghostImageOpacity: Float
    public var ghostFill: SIMD4<Float>
    public var ghostBorder: SIMD4<Float>
    /// The other ends of the selected layer's constraints (C-REND-07): a view is outlined, a
    /// layout guide tinted and outlined with dashes. Drawn whether or not borders are.
    public var endBorder: SIMD4<Float>
    public var guideFill: SIMD4<Float>
    public var guideBorder: SIMD4<Float>
    /// Measuring two layers (C-REND-08): the lines, their ticks, the boxes and, dashed, the
    /// extensions. Drawn whether or not borders are.
    public var measure: SIMD4<Float>
    /// Whether layers that are not highlighted are outlined (C-PREV-09).
    public var drawsBorders: Bool
    /// How wide every line is, in viewport points: the borders, the marks and the
    /// measurement. A point is two pixels on a Retina display: a line that wide has a pixel
    /// it wholly covers wherever it falls, so that it does not pulse as it moves.
    public var lineWidth: Float = 1

    public init(
        background: SIMD4<Float>, border: SIMD4<Float>, hoveredFill: SIMD4<Float>,
        hoveredBorder: SIMD4<Float>, selectedFill: SIMD4<Float>, selectedBorder: SIMD4<Float>,
        ghostImageOpacity: Float, ghostFill: SIMD4<Float>, ghostBorder: SIMD4<Float>,
        endBorder: SIMD4<Float>, guideFill: SIMD4<Float>, guideBorder: SIMD4<Float>,
        measure: SIMD4<Float>, drawsBorders: Bool = true
    ) {
        self.background = background
        self.border = border
        self.hoveredFill = hoveredFill
        self.hoveredBorder = hoveredBorder
        self.selectedFill = selectedFill
        self.selectedBorder = selectedBorder
        self.ghostImageOpacity = ghostImageOpacity
        self.ghostFill = ghostFill
        self.ghostBorder = ghostBorder
        self.endBorder = endBorder
        self.guideFill = guideFill
        self.guideBorder = guideBorder
        self.measure = measure
        self.drawsBorders = drawsBorders
    }

    /// A dark, opaque background; white borders at 28%, a point wide; a blue tint for the layer under the
    /// pointer and a stronger one for the selected layer, light enough to see the image
    /// through. Layers that cannot be seen: half as strong, tinted and outlined in orange.
    /// The ends of constraints in sRGB #BF5AF2: opaque around a view; a guide tinted at 12%
    /// and outlined at 80%, so that its edge differs from a view's. Measuring in opaque sRGB
    /// #FF375F.
    public static let standard = Self(
        background: premultiplied(0.165, 0.165, 0.176, 1),
        border: premultiplied(1, 1, 1, 0.28),
        hoveredFill: premultiplied(0, 0.48, 1, 0.18),
        hoveredBorder: premultiplied(0, 0.48, 1, 0.9),
        selectedFill: premultiplied(0, 0.48, 1, 0.35),
        selectedBorder: premultiplied(0, 0.48, 1, 1),
        ghostImageOpacity: 0.5,
        ghostFill: premultiplied(1, 0.62, 0.04, 0.15),
        ghostBorder: premultiplied(1, 0.62, 0.04, 0.7),
        endBorder: premultiplied(191 / 255, 90 / 255, 242 / 255, 1),
        guideFill: premultiplied(191 / 255, 90 / 255, 242 / 255, 0.12),
        guideBorder: premultiplied(191 / 255, 90 / 255, 242 / 255, 0.8),
        measure: premultiplied(255 / 255, 55 / 255, 95 / 255, 1))

    /// The app's preview: the standard highlights on a background that follows the system's
    /// appearance, sRGB #19191B when dark and #E6E6E9 when light. On the light background the
    /// borders are black at 20%, as white ones would not show, and the ends of constraints a
    /// darker purple, #9A3FD0, with the guide's tint at 10%, and measuring a darker red,
    /// #E0234E.
    public static func preview(dark: Bool, drawsBorders: Bool = true) -> Self {
        var style = standard
        style.background = dark
            ? premultiplied(25 / 255, 25 / 255, 27 / 255, 1)
            : premultiplied(230 / 255, 230 / 255, 233 / 255, 1)
        if !dark {
            style.border = premultiplied(0, 0, 0, 0.2)
            style.endBorder = premultiplied(154 / 255, 63 / 255, 208 / 255, 1)
            style.guideFill = premultiplied(154 / 255, 63 / 255, 208 / 255, 0.1)
            style.guideBorder = premultiplied(154 / 255, 63 / 255, 208 / 255, 0.8)
            style.measure = premultiplied(224 / 255, 35 / 255, 78 / 255, 1)
        }
        style.drawsBorders = drawsBorders
        return style
    }

    public static func premultiplied(
        _ red: Float, _ green: Float, _ blue: Float, _ alpha: Float
    ) -> SIMD4<Float> {
        SIMD4(red * alpha, green * alpha, blue * alpha, alpha)
    }

    /// The tint over an item: its highlight's, or for a ghost the ghost tint (C-REND-06).
    func fill(for item: DrawItem) -> SIMD4<Float>? {
        switch item.highlight {
        case .none: item.isGhost ? ghostFill : nil
        case .hovered: hoveredFill
        case .selected: selectedFill
        }
    }

    /// The item's border; nil when borders are off and the item is not highlighted
    /// (C-PREV-09).
    func border(for item: DrawItem) -> SIMD4<Float>? {
        switch item.highlight {
        case .none: drawsBorders ? (item.isGhost ? ghostBorder : border) : nil
        case .hovered: hoveredBorder
        case .selected: selectedBorder
        }
    }

    /// How opaque an item's image is drawn: its own opacity, and less for a ghost.
    func imageOpacity(for item: DrawItem) -> Float {
        Float(item.opacity) * (item.isGhost ? ghostImageOpacity : 1)
    }

    public var clearColor: MTLClearColor {
        MTLClearColor(
            red: Double(background.x), green: Double(background.y), blue: Double(background.z),
            alpha: Double(background.w))
    }
}
