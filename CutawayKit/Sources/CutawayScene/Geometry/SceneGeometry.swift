import Foundation

/// A point in points. Window and viewport coordinates have their origin at the top left and
/// y growing downwards (P-HIER-06).
public struct ScenePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Self(x: 0, y: 0)
}

public struct SceneSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Self(width: 0, height: 0)
}

public struct SceneRect: Equatable, Sendable {
    public var origin: ScenePoint
    public var size: SceneSize

    public init(origin: ScenePoint, size: SceneSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: ScenePoint(x: x, y: y), size: SceneSize(width: width, height: height))
    }

    public static let zero = Self(origin: .zero, size: .zero)

    public var minX: Double { origin.x }
    public var maxX: Double { origin.x + size.width }
    public var minY: Double { origin.y }
    public var maxY: Double { origin.y + size.height }
    public var center: ScenePoint {
        ScenePoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    /// Whether the two rectangles meet, edges included. A quick test before an exact one.
    func overlaps(_ other: Self) -> Bool {
        minX <= other.maxX && other.minX <= maxX && minY <= other.maxY && other.minY <= maxY
    }

    /// The smallest rectangle that holds both.
    func union(_ other: Self) -> Self {
        let left = min(minX, other.minX)
        let top = min(minY, other.minY)
        return Self(
            x: left, y: top,
            width: max(maxX, other.maxX) - left, height: max(maxY, other.maxY) - top)
    }
}

/// A 4x4 matrix with the layout of CATransform3D: a point is a row vector multiplied on the
/// left (P-HIER-06).
public struct SceneTransform: Equatable, Sendable {
    public var m11: Double, m12: Double, m13: Double, m14: Double
    public var m21: Double, m22: Double, m23: Double, m24: Double
    public var m31: Double, m32: Double, m33: Double, m34: Double
    public var m41: Double, m42: Double, m43: Double, m44: Double

    public init(
        m11: Double, m12: Double, m13: Double, m14: Double,
        m21: Double, m22: Double, m23: Double, m24: Double,
        m31: Double, m32: Double, m33: Double, m34: Double,
        m41: Double, m42: Double, m43: Double, m44: Double
    ) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.m14 = m14
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.m24 = m24
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.m34 = m34
        self.m41 = m41; self.m42 = m42; self.m43 = m43; self.m44 = m44
    }

    public static let identity = Self(
        m11: 1, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: 1, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: 1, m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 1)
}

/// The four corners of a layer's bounds in window coordinates.
public struct Quad: Equatable, Sendable {
    public var topLeft: ScenePoint
    public var topRight: ScenePoint
    public var bottomLeft: ScenePoint
    public var bottomRight: ScenePoint

    public init(
        topLeft: ScenePoint, topRight: ScenePoint, bottomLeft: ScenePoint,
        bottomRight: ScenePoint
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    public var center: ScenePoint {
        ScenePoint(
            x: (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4,
            y: (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4)
    }

    /// The corners in the order they go round the edge.
    var outline: [ScenePoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Whether every corner is finite and no farther than `limit` from the origin on either
    /// axis.
    func isWithin(_ limit: Double) -> Bool {
        outline.allSatisfy { abs($0.x) <= limit && abs($0.y) <= limit }
    }

    var boundingBox: SceneRect {
        let left = min(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x)
        let right = max(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x)
        let top = min(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
        let bottom = max(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
        return SceneRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// An affine map of the plane, with the row-vector convention of P-HIER-06:
/// (x, y) -> (x·a + y·c + tx, x·b + y·d + ty).
struct Affine2D: Equatable, Sendable {
    var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double

    static let identity = Self(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    static func translation(_ x: Double, _ y: Double) -> Self {
        Self(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    func apply(_ p: ScenePoint) -> ScenePoint {
        ScenePoint(x: p.x * a + p.y * c + tx, y: p.x * b + p.y * d + ty)
    }

    /// This map followed by `next`.
    func then(_ next: Self) -> Self {
        Self(
            a: a * next.a + b * next.c,
            b: a * next.b + b * next.d,
            c: c * next.a + d * next.c,
            d: c * next.b + d * next.d,
            tx: tx * next.a + ty * next.c + next.tx,
            ty: tx * next.b + ty * next.d + next.ty)
    }
}

/// From `a` at 0 to `b` at 1, giving exactly `a` and `b` there.
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    if t <= 0 { return a }
    if t >= 1 { return b }
    return a + (b - a) * t
}
