import AppKit
import CutawayModel

/// Draws a layer's icon (C-HIER-11): a rounded square in the colour of its kind with the glyph
/// of its class in it. Filled for the app's own class, outlined for the system's, dashed for a
/// layer that backs no view. The images draw themselves in the appearance they are drawn in.
@MainActor
enum LayerIconImage {
    private struct Key: Hashable {
        var icon: LayerIcon
        var side: CGFloat
        var isSelected: Bool
    }

    /// The colour a glyph is drawn in. Resolved when the glyph is drawn, in the appearance it
    /// is drawn in.
    enum Tint: Hashable {
        case white
        case secondary
        /// The kind's colour in the appearance drawn in.
        case category(LayerIcon.Category)
        /// The kind's colour as the light appearance has it.
        case lightCategory(LayerIcon.Category)
    }

    private struct TintKey: Hashable {
        var glyph: LayerIcon.Glyph
        var tint: Tint
    }

    private static var images: [Key: NSImage] = [:]
    private static var glyphs: [LayerIcon.Glyph: NSImage] = [:]
    private static var tintedGlyphs: [TintKey: NSImage] = [:]

    /// How much of the square's side the glyph takes.
    nonisolated static let glyphShare: CGFloat = 0.8

    /// The icon, `side` points square. `isSelected` is for a row whose background is the
    /// accent colour: a filled square gets a white edge, an outlined one a white fill.
    static func image(_ icon: LayerIcon, side: CGFloat = 16, isSelected: Bool = false) -> NSImage {
        let key = Key(icon: icon, side: side, isSelected: isSelected)
        if let image = images[key] { return image }
        let glyph = tintedGlyph(icon.glyph, tint(of: icon, isSelected: isSelected))
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            draw(icon, glyph: glyph, in: rect, isSelected: isSelected)
            return true
        }
        images[key] = image
        return image
    }

    /// The glyph's image from the asset catalog, a template drawn in black on clear; nil when
    /// the asset is missing.
    static func glyph(_ glyph: LayerIcon.Glyph) -> NSImage? {
        if let image = glyphs[glyph] { return image }
        guard let image = Bundle.module.image(forResource: glyph.rawValue) else { return nil }
        glyphs[glyph] = image
        return image
    }

    /// A device's glyph, drawn like the classes' glyphs. The raw value names its image.
    enum DeviceGlyph: String, CaseIterable {
        case simulator = "deviceSimulator"
        case phone = "devicePhone"
    }

    private struct DeviceKey: Hashable {
        var glyph: DeviceGlyph
        var category: LayerIcon.Category
        var side: CGFloat
    }

    private static var deviceTiles: [DeviceKey: NSImage] = [:]

    /// A filled square in the colour of `category` with a device's glyph in white, `side`
    /// points square: the header of a group in the app list (C-LIST-04).
    static func deviceTile(_ glyph: DeviceGlyph, _ category: LayerIcon.Category, side: CGFloat) -> NSImage {
        let key = DeviceKey(glyph: glyph, category: category, side: side)
        if let image = deviceTiles[key] { return image }
        let white = deviceGlyph(glyph).map { template in
            NSImage(size: template.size, flipped: false) { rect in
                template.draw(in: rect)
                NSColor.white.setFill()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        // Drawn as an app's class of that kind: a filled square under a white glyph.
        let square = LayerIcon(category, .view, isAppClass: true)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            draw(square, glyph: white, in: rect, isSelected: false)
            return true
        }
        deviceTiles[key] = image
        return image
    }

    /// A device glyph's image from the asset catalog, a template drawn in black on clear; nil
    /// when the asset is missing.
    static func deviceGlyph(_ glyph: DeviceGlyph) -> NSImage? {
        Bundle.module.image(forResource: glyph.rawValue)
    }

    /// The glyph in one colour, made once for each glyph and tint.
    static func tintedGlyph(_ glyph: LayerIcon.Glyph, _ tint: Tint) -> NSImage? {
        let key = TintKey(glyph: glyph, tint: tint)
        if let image = tintedGlyphs[key] { return image }
        guard let template = self.glyph(glyph) else { return nil }
        let image = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color(of: tint).setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tintedGlyphs[key] = image
        return image
    }

    /// The glyph's colour: white on a filled square, the kind's colour on an outlined one
    /// (the light one on the white of a selected row), grey in a layer's dashed square.
    static func tint(of icon: LayerIcon, isSelected: Bool) -> Tint {
        if icon.category == .layer { return isSelected ? .white : .secondary }
        if icon.isAppClass { return .white }
        return isSelected ? .lightCategory(icon.category) : .category(icon.category)
    }

    /// Where the glyph goes in a square: in the middle, `glyphShare` of its side.
    nonisolated static func glyphRect(in rect: NSRect) -> NSRect {
        let inset = rect.width * (1 - glyphShare) / 2
        return rect.insetBy(dx: inset, dy: inset)
    }

    private nonisolated static func color(of tint: Tint) -> NSColor {
        switch tint {
        case .white: .white
        case .secondary: .secondaryLabelColor
        case .category(let category): color(category)
        case .lightCategory(let category): light(color(category))
        }
    }

    /// The colour of a kind; a dynamic system colour.
    nonisolated static func color(_ category: LayerIcon.Category) -> NSColor {
        switch category {
        case .window: .systemIndigo
        case .controller: .systemOrange
        case .text: .systemBlue
        case .control: .systemGreen
        case .image: .systemPink
        case .scroll: .systemPurple
        case .bar: .systemTeal
        case .content: .systemBrown
        case .container: .systemGray
        case .layer: .tertiaryLabelColor
        }
    }

    /// A colour as the light appearance has it: the filled squares keep their deeper colour in
    /// the dark too, under a white glyph.
    private nonisolated static func light(_ color: NSColor) -> NSColor {
        var resolved = color
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private nonisolated static func draw(
        _ icon: LayerIcon, glyph: NSImage?, in rect: NSRect, isSelected: Bool
    ) {
        let radius = (rect.width / 4).rounded()
        switch (icon.category, icon.isAppClass) {
        case (.layer, _):
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            path.lineWidth = 1
            path.setLineDash([2, 1.5], count: 2, phase: 0)
            (isSelected ? NSColor.white : .tertiaryLabelColor).setStroke()
            path.stroke()
        case (_, true):
            let fill = light(color(icon.category))
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            if isSelected {
                let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5,
                                        yRadius: radius - 0.5)
                edge.lineWidth = 1
                NSColor.white.setStroke()
                edge.stroke()
            }
        case (_, false):
            let color = isSelected ? light(color(icon.category)) : color(icon.category)
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: radius - 0.6,
                                    yRadius: radius - 0.6)
            if isSelected {
                NSColor.white.setFill()
                path.fill()
            }
            path.lineWidth = 1.2
            color.setStroke()
            path.stroke()
        }
        glyph?.draw(in: glyphRect(in: rect))
    }
}
