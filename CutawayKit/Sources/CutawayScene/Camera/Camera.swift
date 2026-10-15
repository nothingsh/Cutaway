import Foundation

public enum Projection: Sendable {
    case orthographic
    case perspective
}

/// How the scene is looked at (C-SCENE-04). The scene is turned about the middle of its
/// content: first about the vertical axis, then about the horizontal one.
public struct Camera: Equatable, Sendable, CustomStringConvertible {
    public var projection: Projection
    /// About the vertical axis, in radians. Positive turns the layers' left edge towards the
    /// viewer, as if looking from the left.
    public var yaw: Double
    /// About the horizontal axis, in radians. Positive turns the top edge towards the
    /// viewer, as if looking from above.
    public var pitch: Double
    /// 1 fits the content into the viewport.
    public var zoom: Double
    /// In viewport points.
    public var pan: ScenePoint
    /// The distance between neighbouring levels, in points of the content.
    public var layerSpacing: Double

    public init(
        projection: Projection, yaw: Double, pitch: Double, zoom: Double, pan: ScenePoint,
        layerSpacing: Double
    ) {
        self.projection = projection
        self.yaw = yaw
        self.pitch = pitch
        self.zoom = zoom
        self.pan = pan
        self.layerSpacing = layerSpacing
    }

    /// 2D: the layers as the device shows them.
    public static let flat = Self(
        projection: .orthographic, yaw: 0, pitch: 0, zoom: 1, pan: .zero, layerSpacing: 0)

    /// The fixed 3D view of v0.1 (C-PREV-02): from the left and a little above, 50 points
    /// between levels (chosen by the user on the 3D baseline).
    public static let standard3D = Self(
        projection: .perspective, yaw: .pi / 6, pitch: .pi / 12, zoom: 1, pan: .zero,
        layerSpacing: 50)

    /// The space left around the content at zoom 1, in viewport points.
    public static let margin = 20.0

    /// The vertical field of view of the perspective projection.
    public static let fieldOfView = Double.pi / 6

    public var description: String {
        "\(projection) yaw \(yaw) pitch \(pitch) zoom \(zoom) pan (\(pan.x), \(pan.y)) "
            + "spacing \(layerSpacing)"
    }
}

extension Camera {
    /// How far the zoom goes either way (C-PREV-05).
    public static let zoomRange = 0.1...10.0
    /// The tilt stops when the layers are seen edge on from above or below (C-PREV-04).
    public static let pitchRange = -Double.pi / 2...Double.pi / 2
    /// Half a degree per point of drag.
    public static let rotationPerPoint = Double.pi / 360
    /// The layer spacing the interface offers (C-PREV-07).
    public static let spacingRange = 0.0...200.0

    /// Turned by a drag of (dx, dy) points (C-PREV-04): to the right turns the layers' left
    /// edge towards the viewer, down turns their top edge towards the viewer, as if the
    /// content were held and turned. The tilt stops at a quarter turn; the turn wraps.
    public func rotated(byDragOf dx: Double, _ dy: Double) -> Camera {
        var camera = self
        var yaw = (self.yaw + dx * Self.rotationPerPoint)
            .truncatingRemainder(dividingBy: 2 * .pi)
        if yaw >= .pi { yaw -= 2 * .pi } else if yaw < -.pi { yaw += 2 * .pi }
        camera.yaw = yaw
        camera.pitch = min(
            max(pitch + dy * Self.rotationPerPoint, Self.pitchRange.lowerBound),
            Self.pitchRange.upperBound)
        return camera
    }

    /// Moved by (dx, dy) viewport points, y down (C-PREV-06).
    public func panned(by dx: Double, _ dy: Double) -> Camera {
        var camera = self
        camera.pan = ScenePoint(x: pan.x + dx, y: pan.y + dy)
        return camera
    }

    /// Zoomed by `factor` within `zoomRange`, keeping what is under `point` where it is
    /// (C-PREV-05). `Framing` puts a seen point s at c + pan + (s − m) × fit × zoom, where c is
    /// the viewport's middle, and
    /// neither m nor fit depends on the zoom or the pan; so keeping P fixed needs
    /// pan′ = (P − c) − (P − c − pan) × zoom′ / zoom, whatever the content and the turn.
    public func zoomed(
        by factor: Double, about point: ScenePoint, in viewport: Viewport
    ) -> Camera {
        guard factor.isFinite, factor > 0, viewport.width > 0, viewport.height > 0 else {
            return self
        }
        let newZoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let ratio = newZoom / zoom
        let middle = viewport.middle
        let fromCenter = ScenePoint(x: point.x - middle.x, y: point.y - middle.y)
        var camera = self
        camera.zoom = newZoom
        camera.pan = ScenePoint(
            x: fromCenter.x - (fromCenter.x - pan.x) * ratio,
            y: fromCenter.y - (fromCenter.y - pan.y) * ratio)
        return camera
    }
}

/// The size of the view the scene is drawn into, in points.
public struct Viewport: Equatable, Sendable {
    public var width: Double
    public var height: Double
    /// What floats over the edges of the view: at zoom 1 the content fits between them, and
    /// without a pan it is centred between them.
    public var insets: Insets

    /// Room taken from each edge, in points.
    public struct Insets: Equatable, Sendable {
        public var top: Double
        public var left: Double
        public var bottom: Double
        public var right: Double

        public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }

        public static let zero = Self()
    }

    public init(width: Double, height: Double, insets: Insets = .zero) {
        self.width = width
        self.height = height
        self.insets = insets
    }

    /// Where the content's middle is without a pan: the middle of the room inside the insets.
    public var middle: ScenePoint {
        ScenePoint(
            x: insets.left + (width - insets.left - insets.right) / 2,
            y: insets.top + (height - insets.top - insets.bottom) / 2)
    }
}
