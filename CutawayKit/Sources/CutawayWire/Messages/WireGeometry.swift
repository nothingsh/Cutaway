/// Geometry as it travels on the wire. Units are points; see P-HIER-06.

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Self(x: 0, y: 0)
}

public struct Size: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Self(width: 0, height: 0)
}

public struct Rect: Equatable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public static let zero = Self(origin: .zero, size: .zero)
}

public struct Insets: Equatable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = Self(top: 0, left: 0, bottom: 0, right: 0)
}

public struct Color: Equatable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let zero = Self(red: 0, green: 0, blue: 0, alpha: 0)
}

/// A row-major 4x4 matrix with the layout of CATransform3D.
public struct Transform3D: Equatable, Sendable {
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

    public static let zero = Self(
        m11: 0, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: 0, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: 0, m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 0)
}
