/// A corner in homogeneous clip space. The GPU divides by w, which makes the texture follow
/// the perspective.
public struct ClipPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

/// The four corners of a quad in the order a draw item takes them: top left, top right, bottom
/// left, bottom right. Held in place rather than in an array: every layer of every frame has
/// two sets, and an array each cost two allocations a layer (C-SCALE-01).
public struct Corners<Point: Equatable & Sendable>: RandomAccessCollection, Equatable, Sendable {
    public var topLeft: Point
    public var topRight: Point
    public var bottomLeft: Point
    public var bottomRight: Point

    public init(_ topLeft: Point, _ topRight: Point, _ bottomLeft: Point, _ bottomRight: Point) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { 4 }

    /// 0 to 3 in the order above.
    public subscript(index: Int) -> Point {
        switch index {
        case 0: topLeft
        case 1: topRight
        case 2: bottomLeft
        case 3: bottomRight
        default: preconditionFailure("a quad has four corners")
        }
    }
}

public enum Highlight: Equatable, Sendable {
    case none
    case hovered
    case selected
}

/// One layer to draw.
public struct DrawItem: Equatable, Sendable {
    public var layerID: UInt64
    /// The corners of the layer's bounds: top left, top right, bottom left, bottom right. The
    /// image's corners (0,0), (1,0), (0,1), (1,1) go with them (C-SCENE-06).
    public var corners: Corners<ClipPoint>
    /// The same corners in viewport points.
    public var points: Corners<ScenePoint>
    public var texture: TextureKey?
    /// The layer's opacity times its ancestors'. It applies to the image only.
    public var opacity: Double
    public var highlight: Highlight
    /// A layer that cannot be seen, drawn because hidden layers are shown (C-PREV-08). Its
    /// opacity is the one it would have if it were shown.
    public var isGhost: Bool

    public init(
        layerID: UInt64, corners: Corners<ClipPoint>, points: Corners<ScenePoint>,
        texture: TextureKey?,
        opacity: Double, highlight: Highlight, isGhost: Bool = false
    ) {
        self.layerID = layerID
        self.corners = corners
        self.points = points
        self.texture = texture
        self.opacity = opacity
        self.highlight = highlight
        self.isGhost = isGhost
    }

    /// The middle of the four corners in viewport points.
    public var center: ScenePoint {
        ScenePoint(
            x: (points.topLeft.x + points.topRight.x + points.bottomLeft.x + points.bottomRight.x) / 4,
            y: (points.topLeft.y + points.topRight.y + points.bottomLeft.y + points.bottomRight.y) / 4)
    }
}

/// Something pointed out on the preview besides the selection and the hover: the other end
/// of one of the selected layer's constraints (C-LAYOUT-04).
public enum SceneMark: Equatable, Sendable {
    /// A layer, by its corners.
    case layer(UInt64)
    /// A rectangle in a layer's bounds coordinates, on that layer's level: a layout guide
    /// (C-SCENE-08).
    case area(SceneRect, in: UInt64)

    /// The layer the mark is on.
    var layerID: UInt64 {
        switch self {
        case .layer(let id), .area(_, in: let id): id
        }
    }
}

/// A mark as the camera sees it.
public struct DrawMark: Equatable, Sendable {
    /// How a mark stands among the others while the pointer is on an end of a constraint, or
    /// on a constraint, in the attribute panel (C-LAYOUT-06, C-LAYOUT-07): those ends' marks
    /// stressed, the others faded.
    public enum Emphasis: Equatable, Sendable {
        case plain, emphasized, faded
    }

    public var mark: SceneMark
    /// Top left, top right, bottom left, bottom right, as for a `DrawItem`.
    public var corners: Corners<ClipPoint>
    /// The same corners in viewport points.
    public var points: Corners<ScenePoint>
    public var emphasis: Emphasis

    public init(
        mark: SceneMark, corners: Corners<ClipPoint>, points: Corners<ScenePoint>,
        emphasis: Emphasis = .plain
    ) {
        self.mark = mark
        self.corners = corners
        self.points = points
        self.emphasis = emphasis
    }
}

/// A line as the camera sees it, in viewport points and in clip space.
public struct DrawSegment: Equatable, Sendable {
    public var from: ScenePoint
    public var to: ScenePoint
    public var clipFrom: ClipPoint
    public var clipTo: ClipPoint

    public init(from: ScenePoint, to: ScenePoint, clipFrom: ClipPoint, clipTo: ClipPoint) {
        self.from = from
        self.to = to
        self.clipFrom = clipFrom
        self.clipTo = clipTo
    }
}

/// Where a distance's value is written: the middle of its line, in viewport points.
public struct DrawDistanceLabel: Equatable, Sendable {
    public var value: Double
    public var axis: Distance.Axis
    public var middle: ScenePoint

    public init(value: Double, axis: Distance.Axis, middle: ScenePoint) {
        self.value = value
        self.axis = axis
        self.middle = middle
    }
}

/// Measuring two layers as the camera sees it (C-SCENE-09, C-SCENE-12). The selected layer's
/// box and everything between the boxes lie on the selected layer's level; the other box lies
/// on its own.
public struct DrawMeasurement: Equatable, Sendable {
    /// The values, in window coordinates.
    public var measurement: LayerMeasurement
    /// Drawn solid: the four edges of each box, then each distance's line followed by a tick
    /// across its start and one across its end.
    public var lines: [DrawSegment]
    /// Drawn dashed: the distances' extensions, then, when the other layer is on another level
    /// that can be told apart, the four edges of its box carried to the selected layer's level.
    public var dashes: [DrawSegment]
    /// Drawn dotted: with that copy, from each corner of the other box to the same corner of
    /// the copy, in the order top left, top right, bottom right, bottom left.
    public var links: [DrawSegment]
    /// Each distance's line, in the order of the distances; also among `lines`.
    public var distanceLines: [DrawSegment]
    /// One for each distance, in the same order.
    public var labels: [DrawDistanceLabel]

    public init(
        measurement: LayerMeasurement, lines: [DrawSegment], dashes: [DrawSegment],
        links: [DrawSegment] = [], distanceLines: [DrawSegment], labels: [DrawDistanceLabel]
    ) {
        self.measurement = measurement
        self.lines = lines
        self.dashes = dashes
        self.links = links
        self.distanceLines = distanceLines
        self.labels = labels
    }

    /// How long a tick across an end of a distance's line is, in viewport points.
    static let tickLength = 6.0
}

/// What to draw: the layers back to front, then the marks over all of them, then the
/// measurement over everything.
public struct DrawList: Equatable, Sendable {
    public var items: [DrawItem]
    public var marks: [DrawMark]
    public var measurement: DrawMeasurement?
    /// The viewport the list was projected into: how many points the target's pixels cover.
    /// Nil for a list made by hand.
    public var viewport: Viewport?
    /// Whether the lens faced the layers square on without perspective, as in 2D: their edges
    /// then lie straight across or down the screen and stay there.
    public var facesSquareOn: Bool

    public init(
        items: [DrawItem], marks: [DrawMark] = [], measurement: DrawMeasurement? = nil,
        viewport: Viewport? = nil, facesSquareOn: Bool = false
    ) {
        self.items = items
        self.marks = marks
        self.measurement = measurement
        self.viewport = viewport
        self.facesSquareOn = facesSquareOn
    }

    public static let empty = Self(items: [])

    /// The list with `selected` and `hovered` highlighted in place of the layers it
    /// highlights: what projecting again with them gives when nothing else changed and
    /// nothing is measured, since a measurement starts at the selected layer. A new selection
    /// or hover then costs no projection (C-SCALE-01); only the items whose highlight changes
    /// are written.
    public func rehighlighting(selected: UInt64?, hovered: UInt64?) -> Self {
        var list = self
        for index in list.items.indices {
            let id = list.items[index].layerID
            let highlight: Highlight =
                id == selected ? .selected : (id == hovered ? .hovered : .none)
            if list.items[index].highlight != highlight { list.items[index].highlight = highlight }
        }
        return list
    }

    /// The list with `marks` stressed and the other marks faded, or every mark plain when the
    /// list has none of them (C-LAYOUT-06, C-LAYOUT-07). Nothing is projected again.
    public func emphasizing(_ marks: [SceneMark]) -> Self {
        var list = self
        let stressed = marks.filter { mark in list.marks.contains { $0.mark == mark } }
        for index in list.marks.indices {
            let emphasis: DrawMark.Emphasis = if stressed.isEmpty {
                .plain
            } else if stressed.contains(list.marks[index].mark) {
                .emphasized
            } else {
                .faded
            }
            list.marks[index].emphasis = emphasis
        }
        return list
    }
}
