import Foundation

/// What a projection needs to know of the content besides the lens: the middle of the box
/// around it, the box's size and the top level. They change when the expansion does, and in
/// a transition they go from one layout's to the other's (C-SCENE-10).
struct Stage: Equatable, Sendable {
    var center: ScenePoint
    var size: SceneSize
    var topLevel: Double

    init(contentBox: SceneRect, topLevel: Int) {
        center = contentBox.center
        size = contentBox.size
        self.topLevel = Double(topLevel)
    }

    /// The stage `progress` of the way to `end`.
    func interpolated(to end: Self, progress t: Double) -> Self {
        var stage = self
        stage.center = ScenePoint(
            x: lerp(center.x, end.center.x, t), y: lerp(center.y, end.center.y, t))
        stage.size = SceneSize(
            width: lerp(size.width, end.size.width, t),
            height: lerp(size.height, end.size.height, t))
        stage.topLevel = lerp(topLevel, end.topLevel, t)
        return stage
    }
}

/// How the camera sees the content, before it is fitted into the viewport. The
/// content is turned about its middle, the levels centred in depth; for a perspective
/// projection the camera stands at the content's half-diagonal over tan(fov / 2) from that
/// middle, far enough that no layer reaches it. A lens with less perspective stands that
/// distance over its perspective away, which tends to the orthographic projection
/// (C-SCENE-10).
struct Projector {
    private let center: ScenePoint
    private let middleLevel: Double
    private let cosYaw: Double, sinYaw: Double, cosPitch: Double, sinPitch: Double
    private let spacing: Double
    /// In points of the content, for a lens with perspective.
    private let distance: Double?

    init(lens: Lens, stage: Stage) {
        center = stage.center
        middleLevel = stage.topLevel / 2
        cosYaw = cos(lens.yaw)
        sinYaw = sin(lens.yaw)
        cosPitch = cos(lens.pitch)
        sinPitch = sin(lens.pitch)
        spacing = lens.layerSpacing
        let width = stage.size.width, height = stage.size.height
        let depth = stage.topLevel * lens.layerSpacing
        let radius = (width * width + height * height + depth * depth).squareRoot() / 2
        if lens.perspective > 0 {
            let full = radius > 0 ? radius / tan(Camera.fieldOfView / 2) : 1
            distance = full / lens.perspective
        } else {
            distance = nil
        }
    }

    /// A point as the camera sees it, in points of the content about the content's middle,
    /// and its w: the depth, 1 at the middle. Every point of the content has a w of at least
    /// 1 − tan(fov / 2).
    func look(at p: ScenePoint, level: Double) -> (point: ScenePoint, w: Double) {
        var x = p.x - center.x
        var y = p.y - center.y
        var z = (level - middleLevel) * spacing
        (x, z) = (x * cosYaw + z * sinYaw, -x * sinYaw + z * cosYaw)
        (y, z) = (y * cosPitch + z * sinPitch, -y * sinPitch + z * cosPitch)
        guard let distance else { return (ScenePoint(x: x, y: y), 1) }
        let w = (distance - z) / distance
        return (ScenePoint(x: x / w, y: y / w), w)
    }

    /// How far back a level is: the farther, the earlier it is drawn. Orthographic: lower
    /// levels are farther when the layers face the viewer, higher ones when they face away.
    /// Perspective: the distance from the camera to the level's plane, because the camera can
    /// stand between planes. Planes on opposite sides of the camera never cover each other,
    /// so their order is free. As the perspective goes to 0 the second tends to the first.
    func remoteness(ofLevel level: Double) -> Double {
        let facing = cosYaw * cosPitch
        guard let distance else { return facing >= 0 ? -level : level }
        return abs(distance * facing - (level - middleLevel) * spacing)
    }

    /// Whether a layer on level `a` is drawn before one on level `b`: the farther first, the
    /// lower of two as far.
    func drawsBefore(level a: Double, level b: Double) -> Bool {
        let ra = remoteness(ofLevel: a), rb = remoteness(ofLevel: b)
        return ra != rb ? ra > rb : a < b
    }

    /// The levels from back to front.
    func levelOrder(topLevel: Int) -> [Int] {
        (0...topLevel).sorted { drawsBefore(level: Double($0), level: Double($1)) }
    }
}

/// Puts what the camera sees into the viewport: the box around it centred, at the scale
/// that fits it with `Camera.margin` to spare, times the zoom, moved by the pan.
struct Framing {
    private let middle: ScenePoint
    private let scale: Double
    private let origin: ScenePoint
    private let viewport: Viewport

    init(seen: SceneRect, lens: Lens, viewport: Viewport) {
        let width = max(viewport.width - 2 * Camera.margin, 1)
        let height = max(viewport.height - 2 * Camera.margin, 1)
        let box = seen.size
        let fit: Double
        if box.width > 0, box.height > 0 {
            fit = min(width / box.width, height / box.height)
        } else if box.width > 0 {
            fit = width / box.width
        } else if box.height > 0 {
            fit = height / box.height
        } else {
            fit = 1
        }
        middle = seen.center
        scale = fit * lens.zoom
        origin = ScenePoint(
            x: viewport.width / 2 + lens.pan.x, y: viewport.height / 2 + lens.pan.y)
        self.viewport = viewport
    }

    /// The viewport point, and the corner in clip space with the same w.
    func place(_ seen: ScenePoint, w: Double) -> (point: ScenePoint, clip: ClipPoint) {
        let point = ScenePoint(
            x: origin.x + (seen.x - middle.x) * scale, y: origin.y + (seen.y - middle.y) * scale)
        let ndcX = point.x / viewport.width * 2 - 1
        let ndcY = 1 - point.y / viewport.height * 2
        return (point, ClipPoint(x: ndcX * w, y: ndcY * w, z: 0.5 * w, w: w))
    }
}
