/// One layer in a frame: where it is in the window, on which level and how it is drawn. In a
/// transition the level need not be a whole number (C-SCENE-10).
struct Placement: Sendable {
    var id: UInt64
    var quad: Quad
    var level: Double
    var texture: TextureKey?
    /// The kind of image the layer is drawn with, whether or not the image is there yet.
    var kind: TextureKey.Kind
    /// As drawn: for a ghost, the opacity it would have if it were shown.
    var opacity: Double
    var isGhost: Bool
    var content: SceneLayer.Content
    /// Where the layer is in the order of the wire, which orders the layers of one level.
    var index: Int
    /// Which end of a transition the layer is drawn at; a still frame draws every layer at
    /// both.
    var drawnAt: Ends = .both

    enum Ends: Sendable {
        case both
        /// Only at the start: it leaves.
        case start
        /// Only at the end: it comes.
        case end
    }
}

/// A mark with the corners and the level it is drawn at.
struct PlacedMark: Sendable {
    var mark: SceneMark
    var quad: Quad
    var level: Double
}

/// A measurement with the levels of its two layers: the selected one's, which the distances
/// are drawn on, and the other's.
struct PlacedMeasurement: Sendable {
    var measurement: LayerMeasurement
    var selectedLevel: Double
    var otherLevel: Double
}

/// What a frame draws: the layers placed, the order to draw them in (indices into
/// `placements`, back to front), the layers highlighted, the marks and the measurement.
struct FrameContent {
    var placements: [Placement]
    var backToFront: [Int]
    var selected: UInt64?
    var hovered: UInt64?
    var marks: [PlacedMark]
    var measurement: PlacedMeasurement?
}

extension SceneLayout {
    /// The displayed layers as seen by the camera, back to front. Layers that overlap are on
    /// different levels, so going level by level keeps the order they are drawn in on the
    /// device; the camera decides which way round the levels go.
    ///
    /// The marks, in the order given, each where its rectangle is and on the level of its
    /// layer: for a layer inside a collapsed node, the node's level, since the node's image
    /// shows it there. A mark on a layer that is not in the picture (unknown, hidden while
    /// hidden layers are not shown, outside the focus) is left out (C-LAYOUT-04).
    ///
    /// The measurement between the selected layer and `measuring`, when both are in the
    /// picture and differ (C-SCENE-09, C-SCENE-12).
    public func project(
        camera: Camera, viewport: Viewport, selected: UInt64?, hovered: UInt64?,
        marks: [SceneMark] = [], measuring: UInt64? = nil
    ) -> DrawList {
        project(
            lens: Lens(camera), viewport: viewport, selected: selected, hovered: hovered,
            marks: marks, measuring: measuring)
    }

    /// The same through a lens, which may lie between the two projections (C-SCENE-10).
    public func project(
        lens: Lens, viewport: Viewport, selected: UInt64?, hovered: UInt64?,
        marks: [SceneMark] = [], measuring: UInt64? = nil
    ) -> DrawList {
        guard let stage, viewport.width > 0, viewport.height > 0 else { return .empty }
        let projector = Projector(lens: lens, stage: stage)
        let placements = drawOrder.map(placement(of:))
        let backToFront = projector.levelOrder(topLevel: levelRanges.count - 1).flatMap {
            levelRanges[$0]
        }
        let content = FrameContent(
            placements: placements, backToFront: backToFront, selected: selected,
            hovered: hovered, marks: placedMarks(marks) { level(of: $0).map(Double.init) },
            measurement: placedMeasurement(selected: selected, measuring: measuring))
        return Self.frame(content, projector: projector, lens: lens, viewport: viewport)
    }

    /// A drawn layer as it stands in this layout.
    func placement(of index: Int) -> Placement {
        let entry = entries[index]
        return Placement(
            id: entry.layer.id, quad: entry.quad, level: Double(entry.level),
            texture: texture(at: index), kind: Self.neededKind(for: entry),
            opacity: entry.isGhost ? entry.opacityIfShown : entry.opacity,
            isGhost: entry.isGhost, content: entry.layer.content, index: index)
    }

    /// The marks whose layers have a level, with their corners.
    func placedMarks(_ marks: [SceneMark], level: (UInt64) -> Double?) -> [PlacedMark] {
        marks.compactMap { mark in
            guard let at = level(mark.layerID) else { return nil }
            let quad: Quad?
            switch mark {
            case .layer(let id): quad = self.quad(of: id)
            case .area(let rect, in: let id): quad = self.quad(of: rect, in: id)
            }
            return quad.map { PlacedMark(mark: mark, quad: $0, level: at) }
        }
    }

    /// The distances to draw, only between two layers in the picture, with their levels.
    func placedMeasurement(selected: UInt64?, measuring: UInt64?) -> PlacedMeasurement? {
        guard let selected, let measuring, let selectedLevel = level(of: selected),
              let otherLevel = level(of: measuring),
              let measurement = measurement(from: selected, to: measuring)
        else { return nil }
        return PlacedMeasurement(
            measurement: measurement, selectedLevel: Double(selectedLevel),
            otherLevel: Double(otherLevel))
    }

    /// One frame: the layers placed by the projector and fitted into the viewport, drawn in
    /// the order of `backToFront`, then the marks, then the measurement on its layers'
    /// levels. In a transition the view is fitted to what is seen
    /// of the layers drawn at the start, going over to what is seen of those drawn at the end
    /// as `progress` goes from 0 to 1, so that layers that come or go do not rescale it at
    /// once.
    static func frame(
        _ content: FrameContent, projector: Projector, lens: Lens, viewport: Viewport,
        progress: Double = 0
    ) -> DrawList {
        let placements = content.placements, backToFront = content.backToFront
        let selected = content.selected, hovered = content.hovered
        let marks = content.marks, measurement = content.measurement
        guard !placements.isEmpty else { return .empty }
        // What the camera sees of each corner, four per placement, and the box around it for
        // each end.
        var seen: [(point: ScenePoint, w: Double)] = []
        seen.reserveCapacity(placements.count * 4)
        var startBox = SeenBox(), endBox = SeenBox()
        // Spelt out corner by corner, with no array for each layer: this runs for every
        // frame of ten thousand layers, and arrays here doubled its time (C-SCALE-01).
        for placement in placements {
            let q = placement.quad
            let looked = (
                projector.look(at: q.topLeft, level: placement.level),
                projector.look(at: q.topRight, level: placement.level),
                projector.look(at: q.bottomLeft, level: placement.level),
                projector.look(at: q.bottomRight, level: placement.level))
            seen.append(looked.0)
            seen.append(looked.1)
            seen.append(looked.2)
            seen.append(looked.3)
            if placement.drawnAt != .end {
                startBox.add(looked.0.point)
                startBox.add(looked.1.point)
                startBox.add(looked.2.point)
                startBox.add(looked.3.point)
            }
            if placement.drawnAt != .start {
                endBox.add(looked.0.point)
                endBox.add(looked.1.point)
                endBox.add(looked.2.point)
                endBox.add(looked.3.point)
            }
        }
        let framing = Framing(
            seen: SeenBox.interpolated(startBox, endBox, progress: progress), lens: lens,
            viewport: viewport)

        var items: [DrawItem] = []
        items.reserveCapacity(placements.count)
        for position in backToFront {
            let placement = placements[position]
            let first = position * 4
            let placed = (
                framing.place(seen[first].point, w: seen[first].w),
                framing.place(seen[first + 1].point, w: seen[first + 1].w),
                framing.place(seen[first + 2].point, w: seen[first + 2].w),
                framing.place(seen[first + 3].point, w: seen[first + 3].w))
            let corners = Corners(placed.0.clip, placed.1.clip, placed.2.clip, placed.3.clip)
            let points = Corners(placed.0.point, placed.1.point, placed.2.point, placed.3.point)
            let id = placement.id
            let highlight: Highlight =
                id == selected ? .selected : (id == hovered ? .hovered : .none)
            items.append(
                DrawItem(
                    layerID: id, corners: corners, points: points, texture: placement.texture,
                    opacity: placement.opacity, highlight: highlight,
                    isGhost: placement.isGhost, content: placement.content))
        }

        let drawnMarks = marks.map { placed in
            draw(placed) { point, level in
                let looked = projector.look(at: point, level: level)
                return framing.place(looked.point, w: looked.w)
            }
        }

        let drawnMeasurement = measurement.map { placed in
            // A copy of the other box joined to it only where the levels can be told apart.
            let joins = placed.selectedLevel != placed.otherLevel && lens.layerSpacing != 0
                && !lens.facesSquareOn
            return draw(placed, joiningLevels: joins, viewport: viewport) { point, level in
                let looked = projector.look(at: point, level: level)
                return framing.place(looked.point, w: looked.w)
            }
        }
        return DrawList(
            items: items, marks: drawnMarks, measurement: drawnMeasurement, viewport: viewport,
            facesSquareOn: lens.facesSquareOn)
    }

    /// The mark with its corners placed on its level by `place`.
    private static func draw(
        _ placed: PlacedMark, place: (ScenePoint, Double) -> (point: ScenePoint, clip: ClipPoint)
    ) -> DrawMark {
        let q = placed.quad
        let tl = place(q.topLeft, placed.level), tr = place(q.topRight, placed.level)
        let bl = place(q.bottomLeft, placed.level), br = place(q.bottomRight, placed.level)
        return DrawMark(
            mark: placed.mark, corners: Corners(tl.clip, tr.clip, bl.clip, br.clip),
            points: Corners(tl.point, tr.point, bl.point, br.point))
    }

    /// The measurement with each window point placed on a level by `place`. The selected
    /// layer's box and the lines between the boxes go on the selected layer's level, the other
    /// box on its own; with `joiningLevels`, a dashed copy of the other box on the selected
    /// layer's level and a dotted link from each of its corners to the copy's. The ticks stand
    /// across their line on the screen and are measured in viewport points, so that they keep
    /// their length.
    private static func draw(
        _ placed: PlacedMeasurement, joiningLevels: Bool, viewport: Viewport,
        place: (ScenePoint, Double) -> (point: ScenePoint, clip: ClipPoint)
    ) -> DrawMeasurement {
        let measurement = placed.measurement
        typealias Placed = (point: ScenePoint, clip: ClipPoint)
        func segment(_ from: Placed, _ to: Placed) -> DrawSegment {
            DrawSegment(from: from.point, to: to.point, clipFrom: from.clip, clipTo: to.clip)
        }
        func onScreen(_ from: ScenePoint, _ to: ScenePoint) -> DrawSegment {
            DrawSegment(
                from: from, to: to, clipFrom: viewport.clip(from), clipTo: viewport.clip(to))
        }
        func onSelected(_ p: ScenePoint) -> Placed { place(p, placed.selectedLevel) }
        func onOther(_ p: ScenePoint) -> Placed { place(p, placed.otherLevel) }
        func edges(_ box: SceneRect, _ on: (ScenePoint) -> Placed) -> [DrawSegment] {
            let corners = Self.corners(of: box).map(on)
            return corners.indices.map { segment(corners[$0], corners[($0 + 1) % 4]) }
        }

        let boxes = measurement.boxes
        var lines = edges(boxes[0], onSelected) + edges(boxes[1], onOther)
        var dashes: [DrawSegment] = []
        var distanceLines: [DrawSegment] = []
        var labels: [DrawDistanceLabel] = []
        let half = DrawMeasurement.tickLength / 2
        for distance in measurement.distances {
            let line = segment(onSelected(distance.start), onSelected(distance.end))
            lines.append(line)
            distanceLines.append(line)
            // Across the line as it lies on the screen: down for one across, right for one
            // down when they lie straight, as in 2D.
            let dx = line.to.x - line.from.x, dy = line.to.y - line.from.y
            let length = (dx * dx + dy * dy).squareRoot()
            let ux = length > 0 ? dx / length : (distance.axis == .horizontal ? 1 : 0)
            let uy = length > 0 ? dy / length : (distance.axis == .horizontal ? 0 : 1)
            let across =
                distance.axis == .horizontal
                    ? ScenePoint(x: -uy, y: ux) : ScenePoint(x: uy, y: -ux)
            for end in [line.from, line.to] {
                lines.append(
                    onScreen(
                        ScenePoint(x: end.x - across.x * half, y: end.y - across.y * half),
                        ScenePoint(x: end.x + across.x * half, y: end.y + across.y * half)))
            }
            dashes += distance.extensions.map { segment(onSelected($0.from), onSelected($0.to)) }
            let middle = ScenePoint(
                x: (distance.start.x + distance.end.x) / 2,
                y: (distance.start.y + distance.end.y) / 2)
            labels.append(
                DrawDistanceLabel(
                    value: distance.value, axis: distance.axis, middle: onSelected(middle).point))
        }
        var links: [DrawSegment] = []
        if joiningLevels {
            dashes += edges(boxes[1], onSelected)
            links = Self.corners(of: boxes[1]).map { segment(onOther($0), onSelected($0)) }
        }
        return DrawMeasurement(
            measurement: measurement, lines: lines, dashes: dashes, links: links,
            distanceLines: distanceLines, labels: labels)
    }

    /// Top left, top right, bottom right, bottom left: round the box.
    private static func corners(of box: SceneRect) -> [ScenePoint] {
        [
            ScenePoint(x: box.minX, y: box.minY), ScenePoint(x: box.maxX, y: box.minY),
            ScenePoint(x: box.maxX, y: box.maxY), ScenePoint(x: box.minX, y: box.maxY),
        ]
    }
}

extension Viewport {
    /// A viewport point in clip space, with a w of 1.
    func clip(_ point: ScenePoint) -> ClipPoint {
        ClipPoint(x: point.x / width * 2 - 1, y: 1 - point.y / height * 2, z: 0.5, w: 1)
    }
}

/// The box around the points the camera sees.
private struct SeenBox {
    var low = ScenePoint(x: Double.infinity, y: Double.infinity)
    var high = ScenePoint(x: -Double.infinity, y: -Double.infinity)

    var isEmpty: Bool { low.x > high.x }

    mutating func add(_ p: ScenePoint) {
        low = ScenePoint(x: min(low.x, p.x), y: min(low.y, p.y))
        high = ScenePoint(x: max(high.x, p.x), y: max(high.y, p.y))
    }

    /// The box `progress` of the way from `start` to `end`; either one when the other holds
    /// nothing.
    static func interpolated(_ start: Self, _ end: Self, progress t: Double) -> SceneRect {
        let a = start.isEmpty ? end : start, b = end.isEmpty ? start : end
        let low = ScenePoint(x: lerp(a.low.x, b.low.x, t), y: lerp(a.low.y, b.low.y, t))
        let high = ScenePoint(x: lerp(a.high.x, b.high.x, t), y: lerp(a.high.y, b.high.y, t))
        return SceneRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y)
    }
}

extension DrawList {
    /// The frontmost layer whose projected corners hold the point, in viewport points
    /// (C-SCENE-05). Only displayed layers that are not hidden are in a draw list, so those
    /// are the only ones that can be hit.
    public func layer(at point: ScenePoint) -> UInt64? {
        for item in items.reversed() where Polygon.contains(item.points, point) {
            return item.layerID
        }
        return nil
    }
}

extension SceneLayout {
    /// The frontmost layer under a point of the viewport, worked out on the CPU.
    public func hitTest(point: ScenePoint, camera: Camera, viewport: Viewport) -> UInt64? {
        project(camera: camera, viewport: viewport, selected: nil, hovered: nil).layer(at: point)
    }
}
