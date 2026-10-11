import Foundation

/// A camera whose projection can lie between orthographic and perspective, so that one
/// camera can turn into another a little at a time (C-SCENE-10). A `Camera` is a lens with no
/// perspective or full perspective.
public struct Lens: Equatable, Sendable {
    /// About the vertical axis, in radians, as `Camera.yaw`.
    public var yaw: Double
    /// About the horizontal axis, in radians, as `Camera.pitch`.
    public var pitch: Double
    public var zoom: Double
    public var pan: ScenePoint
    public var layerSpacing: Double
    /// 0 for the orthographic projection, 1 for the perspective one of `Camera.fieldOfView`.
    public var perspective: Double

    public init(_ camera: Camera) {
        yaw = camera.yaw
        pitch = camera.pitch
        zoom = camera.zoom
        pan = camera.pan
        layerSpacing = camera.layerSpacing
        perspective = camera.projection == .perspective ? 1 : 0
    }

    /// Whether it looks square on at the layers without perspective: the 2D view, the only
    /// one distances are measured in (C-PREV-10).
    var facesSquareOn: Bool {
        perspective == 0 && yaw == 0 && pitch == 0
    }

    /// The lens `progress` of the way to `end`: exactly this one at 0 and `end` at 1. The turn
    /// about the vertical axis goes the shorter way round; the zoom goes by equal ratios, so
    /// that zooming in tenfold takes as long as zooming out tenfold.
    public func interpolated(to end: Self, progress t: Double) -> Self {
        if t <= 0 { return self }
        if t >= 1 { return end }
        var lens = self
        var turn = (end.yaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
        var yaw = self.yaw + turn * t
        if yaw >= .pi { yaw -= 2 * .pi } else if yaw < -.pi { yaw += 2 * .pi }
        lens.yaw = yaw
        lens.pitch = lerp(pitch, end.pitch, t)
        lens.zoom =
            zoom > 0 && end.zoom > 0 ? zoom * pow(end.zoom / zoom, t) : lerp(zoom, end.zoom, t)
        lens.pan = ScenePoint(x: lerp(pan.x, end.pan.x, t), y: lerp(pan.y, end.pan.y, t))
        lens.layerSpacing = lerp(layerSpacing, end.layerSpacing, t)
        lens.perspective = lerp(perspective, end.perspective, t)
        return lens
    }
}
