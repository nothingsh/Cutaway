import AppKit
import CutawayRender

// Looking at what is shown. For the app tests, which see only what is public, and for the
// package's tests. `renderer` is internal rather than private for `snapshot()`.
extension PreviewView {
    /// Draws what is on screen again, offscreen, at the window's pixel density.
    public func snapshot() throws -> RenderedImage {
        let scale = window?.backingScaleFactor ?? 1
        return try renderer.renderImage(
            drawList, textures: textures, style: style,
            pixelWidth: Int((bounds.width * scale).rounded()),
            pixelHeight: Int((bounds.height * scale).rounded()))
    }

    /// The middle of a drawn layer in `snapshot()`'s pixels, from the top left; nil when the
    /// layer is not drawn.
    public func imagePoint(ofCenterOf id: UInt64) -> CGPoint? {
        guard let center = drawList.items.first(where: { $0.layerID == id })?.center else {
            return nil
        }
        let scale = window?.backingScaleFactor ?? 1
        return CGPoint(x: center.x * scale, y: center.y * scale)
    }

    /// The corners of a drawn layer in `snapshot()`'s pixels: top left, top right, bottom left,
    /// bottom right; nil when the layer is not drawn.
    public func imageCorners(of id: UInt64) -> [CGPoint]? {
        guard let item = drawList.items.first(where: { $0.layerID == id }) else { return nil }
        let scale = window?.backingScaleFactor ?? 1
        return item.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
    }

    /// The corners of each mark drawn (C-LAYOUT-04) in `snapshot()`'s pixels, in the order of
    /// the draw list: top left, top right, bottom left, bottom right.
    public var imageMarkCorners: [[CGPoint]] {
        let scale = window?.backingScaleFactor ?? 1
        return drawList.marks.map { mark in
            mark.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        }
    }

    /// The colour the marks of views are drawn in.
    public var markPixel: Pixel { style.endBorder.pixel }

    /// Each distance measured (C-PREV-10): its value and the ends of its line in
    /// `snapshot()`'s pixels.
    public var imageDistances: [(value: Double, from: CGPoint, to: CGPoint)] {
        guard let drawn = drawList.measurement else { return [] }
        let scale = window?.backingScaleFactor ?? 1
        return zip(drawn.labels, drawn.distanceLines).map { label, line in
            (
                label.value, CGPoint(x: line.from.x * scale, y: line.from.y * scale),
                CGPoint(x: line.to.x * scale, y: line.to.y * scale)
            )
        }
    }

    /// The colour measurements are drawn in.
    public var measurePixel: Pixel { style.measure.pixel }

    /// The middle of a drawn layer in this view's coordinates.
    func viewPoint(ofCenterOf id: UInt64) -> NSPoint? {
        guard let center = drawList.items.first(where: { $0.layerID == id })?.center else {
            return nil
        }
        return NSPoint(x: center.x, y: isFlipped ? center.y : bounds.height - center.y)
    }
}
