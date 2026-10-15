/// Where the preview's tag of a layer goes (C-PREV-16): upright, at the corner of the layer
/// that is highest on screen, the one further left of two as high; just above that corner, or
/// inside the layer under it when the corner is too near the top of the viewport; never past
/// the viewport's left edge.
public enum TagPlacement {
    /// The room between the corner and the tag above it.
    public static let gap = 4.0
    /// How far into the layer a tag goes when there is no room above.
    public static let inset = 3.0
    /// How far below the viewport's top a corner must be for the tag to go above it.
    public static let roomAbove = 24.0

    /// The top left of a tag of `size` for a layer at `corners`, in viewport points, y down.
    public static func origin(for corners: Corners<ScenePoint>, size: SceneSize) -> ScenePoint {
        let corner = anchor(of: corners)
        var origin = corner.y < roomAbove
            ? ScenePoint(x: corner.x + inset, y: corner.y + inset)
            : ScenePoint(x: corner.x, y: corner.y - gap - size.height)
        origin.x = max(origin.x, 0)
        return origin
    }

    /// The corner highest on screen; of two as high, the one further left.
    public static func anchor(of corners: Corners<ScenePoint>) -> ScenePoint {
        corners.min { a, b in a.y != b.y ? a.y < b.y : a.x < b.x } ?? corners.topLeft
    }
}
