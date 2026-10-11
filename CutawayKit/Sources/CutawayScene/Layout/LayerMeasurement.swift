/// A line between two points.
public struct Segment: Equatable, Sendable {
    public var from: ScenePoint
    public var to: ScenePoint

    public init(from: ScenePoint, to: ScenePoint) {
        self.from = from
        self.to = to
    }
}

/// One distance between two layers' boxes on one axis (C-SCENE-09), in window coordinates.
public struct Distance: Equatable, Sendable {
    public enum Axis: Equatable, Sendable {
        case horizontal
        case vertical
    }

    public var axis: Axis
    /// In points of the window; one that would be written as 0 is left out.
    public var value: Double
    /// The ends of the line, the smaller coordinate first.
    public var start: ScenePoint
    public var end: ScenePoint
    /// From a box's edge to an end of the line that is beyond the box.
    public var extensions: [Segment]

    public init(
        axis: Axis, value: Double, start: ScenePoint, end: ScenePoint, extensions: [Segment]
    ) {
        self.axis = axis
        self.value = value
        self.start = start
        self.end = end
        self.extensions = extensions
    }
}

/// What measuring two layers shows: the boxes around them and the distances between them.
public struct LayerMeasurement: Equatable, Sendable {
    /// The selected layer's box, then the other's.
    public var boxes: [SceneRect]
    /// The horizontal distances before the vertical ones, each the left or top one first.
    public var distances: [Distance]

    public init(boxes: [SceneRect], distances: [Distance]) {
        self.boxes = boxes
        self.distances = distances
    }
}

extension SceneLayout {
    /// The distances between the boxes around two layers' corners in window coordinates,
    /// on each axis: the gap between the facing edges when the boxes are apart, otherwise
    /// edge to edge on each side (C-SCENE-09). Nil when either layer is unknown or both are
    /// the same.
    public func measurement(from selected: UInt64, to other: UInt64) -> LayerMeasurement? {
        guard selected != other, let a = quad(of: selected)?.boundingBox,
              let b = quad(of: other)?.boundingBox
        else { return nil }
        let across = Self.distances(
            Span(a.minX, a.maxX), Span(b.minX, b.maxX),
            line: Self.lineAt(Span(a.minY, a.maxY), Span(b.minY, b.maxY)),
            across: (Span(a.minY, a.maxY), Span(b.minY, b.maxY)))
        let down = Self.distances(
            Span(a.minY, a.maxY), Span(b.minY, b.maxY),
            line: Self.lineAt(Span(a.minX, a.maxX), Span(b.minX, b.maxX)),
            across: (Span(a.minX, a.maxX), Span(b.minX, b.maxX)))
        func horizontal(_ d: AxisDistance) -> Distance {
            Distance(
                axis: .horizontal, value: d.value, start: ScenePoint(x: d.start, y: d.line),
                end: ScenePoint(x: d.end, y: d.line),
                extensions: d.extensions.map {
                    Segment(
                        from: ScenePoint(x: $0.at, y: $0.from), to: ScenePoint(x: $0.at, y: $0.to))
                })
        }
        func vertical(_ d: AxisDistance) -> Distance {
            Distance(
                axis: .vertical, value: d.value, start: ScenePoint(x: d.line, y: d.start),
                end: ScenePoint(x: d.line, y: d.end),
                extensions: d.extensions.map {
                    Segment(
                        from: ScenePoint(x: $0.from, y: $0.at), to: ScenePoint(x: $0.to, y: $0.at))
                })
        }
        return LayerMeasurement(
            boxes: [a, b], distances: across.map(horizontal) + down.map(vertical))
    }

    /// A range on one axis.
    private struct Span {
        var low: Double
        var high: Double

        init(_ low: Double, _ high: Double) {
            self.low = low
            self.high = high
        }

        var middle: Double { (low + high) / 2 }
        var length: Double { high - low }

        func contains(_ value: Double) -> Bool { low <= value && value <= high }

        /// The value moved into the range.
        func clamp(_ value: Double) -> Double { min(max(value, low), high) }
    }

    /// A distance on one axis, the line at `line` on the other.
    private struct AxisDistance {
        var value: Double
        var start: Double
        var end: Double
        var line: Double
        /// At `at` on this axis, from `from` to `to` on the other.
        var extensions: [(at: Double, from: Double, to: Double)]
    }

    /// Where on the other axis the line goes: the middle of the boxes' overlap there, or,
    /// when they do not overlap, the middle of the shorter one (the selected one's when they
    /// are as long).
    private static func lineAt(_ a: Span, _ b: Span) -> Double {
        let low = max(a.low, b.low), high = min(a.high, b.high)
        if low <= high { return (low + high) / 2 }
        return b.length < a.length ? b.middle : a.middle
    }

    /// The distances on one axis between `a` and `b`: the gap when they are apart, otherwise
    /// low edge to low edge and high to high. One that would be written as 0 is left out.
    /// Each end of a line is on an edge of one of the boxes; where the line is beyond that
    /// box on the other axis, an extension runs along the edge from the box to the line.
    private static func distances(
        _ a: Span, _ b: Span, line: Double, across: (a: Span, b: Span)
    ) -> [AxisDistance] {
        // Each pair: (coordinate, the box it is an edge of on the other axis).
        var pairs: [((Double, Span), (Double, Span))] = []
        if b.high < a.low {
            pairs = [((b.high, across.b), (a.low, across.a))]
        } else if a.high < b.low {
            pairs = [((a.high, across.a), (b.low, across.b))]
        } else {
            pairs = [((a.low, across.a), (b.low, across.b)), ((a.high, across.a), (b.high, across.b))]
        }
        return pairs.compactMap { first, second in
            let (start, end) = first.0 <= second.0 ? (first, second) : (second, first)
            let value = end.0 - start.0
            guard (value * 10).rounded() != 0 else { return nil }
            let extensions = [start, end].compactMap { edge -> (Double, Double, Double)? in
                let (at, box) = edge
                guard !box.contains(line) else { return nil }
                return (at, box.clamp(line), line)
            }
            return AxisDistance(
                value: value, start: start.0, end: end.0, line: line, extensions: extensions)
        }
    }
}
