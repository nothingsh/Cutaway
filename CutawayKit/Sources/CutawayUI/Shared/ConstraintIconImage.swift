import AppKit

/// The icons of the constraints in the attribute panel, in the colour of their marks on the
/// preview (`Theme.constraintEnd`): the Constraints section's, two edges with a span between
/// them (C-ATTR-17), and a layout guide's, a dashed square like its mark (C-LAYOUT-06). The
/// images draw themselves in the appearance they are drawn in.
@MainActor
enum ConstraintIconImage {
    private static var sections: [CGFloat: NSImage] = [:]
    private static var guides: [CGFloat: NSImage] = [:]

    /// The Constraints section's icon, `side` points square.
    static func section(side: CGFloat = 14) -> NSImage {
        if let image = sections[side] { return image }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            // The glyph takes 11 of 14 points, drawn on a 16-point grid.
            let scale = rect.width * 11 / 14 / 16
            let inset = (rect.width - 16 * scale) / 2
            let path = NSBezierPath()
            for (from, to) in [
                ((3, 3), (3, 13)), ((13, 3), (13, 13)), ((3, 8), (13, 8)),
                ((6, 6), (3, 8)), ((3, 8), (6, 10)), ((10, 6), (13, 8)), ((13, 8), (10, 10)),
            ] {
                path.move(to: NSPoint(x: inset + CGFloat(from.0) * scale, y: inset + CGFloat(from.1) * scale))
                path.line(to: NSPoint(x: inset + CGFloat(to.0) * scale, y: inset + CGFloat(to.1) * scale))
            }
            path.lineWidth = 1.5 * scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            Theme.constraintEnd.setStroke()
            path.stroke()
            return true
        }
        sections[side] = image
        return image
    }

    /// A layout guide's icon, `side` points square: dashed, as its mark is.
    static func guide(side: CGFloat = 13) -> NSImage {
        if let image = guides[side] { return image }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let radius = (rect.width / 4).rounded()
            let path = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            path.lineWidth = 1
            path.setLineDash([2, 1.5], count: 2, phase: 0)
            Theme.constraintEnd.setStroke()
            path.stroke()
            return true
        }
        guides[side] = image
        return image
    }
}
