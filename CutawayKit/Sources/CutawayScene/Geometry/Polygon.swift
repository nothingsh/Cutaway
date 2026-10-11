/// Convex polygons in the plane. A polygon is its corners in the order they go round the
/// edge, either way round.
enum Polygon {
    /// An area at or below this, in square points, counts as none.
    static let areaEpsilon = 1e-9

    /// An overlap thinner than this, in points, counts as none: two layers that only share
    /// an edge or a corner do not overlap (C-SCENE-02), even where rounding at large
    /// coordinates leaves a sliver between them.
    static let slimmestOverlap = 1e-6

    /// Positive one way round, negative the other. Measured from the first corner, so that
    /// large coordinates do not drown the area in rounding.
    static func signedArea(_ points: [ScenePoint]) -> Double {
        guard let first = points.first else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            sum += (p.x - first.x) * (q.y - first.y) - (q.x - first.x) * (p.y - first.y)
        }
        return sum / 2
    }

    static func perimeter(_ points: [ScenePoint]) -> Double {
        var sum = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            sum += ((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)).squareRoot()
        }
        return sum
    }

    /// Whether two convex polygons share an area that is more than a sliver.
    static func overlap(_ a: [ScenePoint], _ b: [ScenePoint]) -> Bool {
        let sliver = slimmestOverlap * min(perimeter(a), perimeter(b))
        return overlapArea(a, b) > max(areaEpsilon, sliver)
    }

    /// The area two convex polygons share, by clipping one against each edge of the other.
    static func overlapArea(_ subject: [ScenePoint], _ clipper: [ScenePoint]) -> Double {
        let clipperArea = signedArea(clipper)
        guard abs(clipperArea) > areaEpsilon, abs(signedArea(subject)) > areaEpsilon else {
            return 0
        }
        // With a positive area, the inside is to the left of every edge.
        let edges = clipperArea > 0 ? clipper : clipper.reversed()
        var output = subject
        for i in edges.indices {
            let start = edges[i], end = edges[(i + 1) % edges.count]
            let input = output
            output = []
            guard !input.isEmpty else { break }
            for j in input.indices {
                let current = input[j], previous = input[(j + input.count - 1) % input.count]
                let currentSide = side(current, start, end)
                let previousSide = side(previous, start, end)
                if currentSide >= 0 {
                    if previousSide < 0 {
                        output.append(crossing(previous, previousSide, current, currentSide))
                    }
                    output.append(current)
                } else if previousSide >= 0 {
                    output.append(crossing(previous, previousSide, current, currentSide))
                }
            }
        }
        return output.count < 3 ? 0 : abs(signedArea(output))
    }

    /// Whether a convex polygon holds the point. Points on the edge count as inside; a
    /// polygon without area holds nothing.
    static func contains(_ polygon: [ScenePoint], _ point: ScenePoint) -> Bool {
        let area = signedArea(polygon)
        guard abs(area) > areaEpsilon else { return false }
        let sign: Double = area > 0 ? 1 : -1
        for i in polygon.indices where side(point, polygon[i], polygon[(i + 1) % polygon.count]) * sign < 0 {
            return false
        }
        return true
    }

    /// The same for the corners of a draw item, without an array: the pointer is tested
    /// against every layer at each move (C-SCALE-01). It gives what the array version gives,
    /// to the last bit: the area is summed term by term in the same order, the zero terms
    /// of the first corner included, since an infinite corner makes them not a number.
    static func contains(_ corners: Corners<ScenePoint>, _ point: ScenePoint) -> Bool {
        // Round the edge: top left, top right, bottom right, bottom left.
        let a = corners.topLeft, b = corners.topRight
        let c = corners.bottomRight, d = corners.bottomLeft
        var sum = 0.0
        sum += (a.x - a.x) * (b.y - a.y) - (b.x - a.x) * (a.y - a.y)
        sum += (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
        sum += (c.x - a.x) * (d.y - a.y) - (d.x - a.x) * (c.y - a.y)
        sum += (d.x - a.x) * (a.y - a.y) - (a.x - a.x) * (d.y - a.y)
        let area = sum / 2
        guard abs(area) > areaEpsilon else { return false }
        let sign: Double = area > 0 ? 1 : -1
        return !(side(point, a, b) * sign < 0 || side(point, b, c) * sign < 0
            || side(point, c, d) * sign < 0 || side(point, d, a) * sign < 0)
    }

    /// Positive when `p` is to the left of the line from `start` to `end`.
    private static func side(_ p: ScenePoint, _ start: ScenePoint, _ end: ScenePoint) -> Double {
        (end.x - start.x) * (p.y - start.y) - (end.y - start.y) * (p.x - start.x)
    }

    /// Where the segment from `p` to `q` crosses the line their sides were measured against.
    private static func crossing(
        _ p: ScenePoint, _ pSide: Double, _ q: ScenePoint, _ qSide: Double
    ) -> ScenePoint {
        let t = pSide / (pSide - qSide)
        return ScenePoint(x: p.x + t * (q.x - p.x), y: p.y + t * (q.y - p.y))
    }
}
