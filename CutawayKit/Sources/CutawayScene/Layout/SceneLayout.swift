/// Where each layer is, which layers are displayed, on which level and with which image.
/// It depends on the layers and on which nodes are expanded, not on the camera: it is built
/// again when those change, and projected for every camera.
public struct SceneLayout: Sendable {
    struct Entry: Sendable {
        var layer: SceneLayer
        /// From the layer's bounds coordinates to the window's (P-HIER-06).
        var toWindow: Affine2D
        var quad: Quad
        var box: SceneRect
        /// Whether the quad covers any area. A layer without area is not drawn.
        var hasArea: Bool
        /// Whether the layer, and every ancestor, has a place in the window: its geometry is
        /// finite and its corners are within what the drawing layer can hold (C-SCENE-11). One
        /// that is not has no area and no corners.
        var isPlaceable: Bool
        var isDisplayed: Bool
        /// Whether it or an ancestor is hidden.
        var isHidden: Bool
        /// Whether it is the focused layer or inside it; every layer is when there is no focus.
        var isInFocus: Bool
        /// Whether it is displayed only because hidden layers are shown: it, or an ancestor,
        /// is hidden or has an opacity of 0 (C-PREV-08).
        var isGhost: Bool
        /// Whether the layer is in the set of expanded nodes the layout was built with.
        var isExpanded: Bool
        /// Whether the layer has sublayers in the tree, hidden ones included.
        var hasChildren: Bool
        /// The displayed layer that stands for this one: itself when it is displayed, the
        /// collapsed node it is inside of otherwise. Nil when it or an ancestor is hidden, and
        /// for a layer outside the focus.
        var standIn: Int?
        /// Meaningful for displayed layers.
        var level: Int
        var opacity: Double
        /// The opacity it would have if it were shown: an opacity of 0, its own or an
        /// ancestor's, counts as 1.
        var opacityIfShown: Double
    }

    /// The layers without their images: those are in `images`.
    let entries: [Entry]
    /// The images of each layer, by index into `entries`. Kept apart so that new images for a
    /// few layers copy neither the entries nor every layer's images (C-SCALE-02).
    var images: ChunkedArray<LayerTextures>
    let indexByID: [UInt64: Int]
    /// The index of each layer's parent, as the layout took it: nil for a root, and for a
    /// layer whose parent does not come before it. An ID that comes twice does not mislead
    /// it, as looking the parent up in `indexByID` would.
    let parentIndices: [Int?]
    /// The displayed layers, as indices into `entries`, in the order of the wire.
    let displayed: [Int]
    /// The displayed layers that have an area, by level, then in the order of the wire.
    let drawOrder: [Int]
    /// Where each level's layers are in `drawOrder`, by level.
    let levelRanges: [Range<Int>]
    /// The box around every displayed layer that has an area, in window coordinates. Nil when
    /// there is none.
    public let contentBox: SceneRect?
    /// The layers that are drawn, each with the kind of image it is drawn with, in the order
    /// of the wire: what the inspection asks the app for (C-DET-01). Layers the app does not
    /// let be captured are left out (C-DET-11).
    public let neededTextures: [TextureNeed]
    /// The nodes the layout was built with as expanded.
    let expanded: Set<UInt64>
    /// The focus it was built with; nil also for a focus that is not among the layers.
    let focus: UInt64?
    let showsHidden: Bool
    /// What a projection needs of the content; nil when no displayed layer has an area.
    let stage: Stage?
    /// The same for this layout and the copies with other images, and for no other layout.
    let build = Build()

    /// Tells one laying out of the layers from another.
    final class Build: Sendable {}

    /// Lays the layers out. With a focus, only that layer and what is inside it are displayed
    /// (C-HIER-05): the rest get no level, no image, no room in the content box, and cannot
    /// be hit. Where a layer is, and how opaque, still comes from all its ancestors. A focus
    /// that is not among the layers is no focus. With `showsHidden`, layers that cannot be
    /// seen (hidden, or of opacity 0, themselves or through an ancestor) are displayed as
    /// ghosts (C-PREV-08).
    public init(
        layers: [SceneLayer], expanded: Set<UInt64>, focus: UInt64? = nil,
        showsHidden: Bool = false
    ) {
        let (indexByID, parentIndex, hasChildren) = Self.parents(of: layers)
        let focus = focus.flatMap { indexByID[$0] == nil ? nil : $0 }

        var entries: [Entry] = []
        entries.reserveCapacity(layers.count)
        var displayed: [Int] = []
        var contentBox: SceneRect?

        for (index, layer) in layers.enumerated() {
            let parent = parentIndex[index]
            let local = Self.localToParent(layer)
            let map = parent.map { local.then(entries[$0].toWindow) } ?? local

            let b = layer.bounds
            let quad = Quad(
                topLeft: map.apply(ScenePoint(x: b.minX, y: b.minY)),
                topRight: map.apply(ScenePoint(x: b.maxX, y: b.minY)),
                bottomLeft: map.apply(ScenePoint(x: b.minX, y: b.maxY)),
                bottomRight: map.apply(ScenePoint(x: b.maxX, y: b.maxY)))

            let parentEntry = parent.map { entries[$0] }
            let isHidden = layer.isHidden || parentEntry?.isHidden == true
            let isFocusRoot = layer.id == focus
            let isInFocus = focus == nil || isFocusRoot || parentEntry?.isInFocus == true
            // The focused layer is displayed whatever its parent is: the parent is outside the
            // focus, not collapsed.
            let isCollapsedAbove =
                !isFocusRoot
                    && parentEntry.map { !$0.isDisplayed || !expanded.contains($0.layer.id) } ?? false
            // What takes a layer out of the picture, unless hidden layers are shown.
            let hides = isHidden && !showsHidden
            let isDisplayed = isInFocus && !hides && !isCollapsedAbove
            let standIn: Int? =
                hides || !isInFocus ? nil : (isDisplayed ? index : parentEntry?.standIn)
            let ownOpacity = Self.ownOpacity(layer.opacity)
            let opacity = ownOpacity * (parentEntry?.opacity ?? 1)
            let opacityIfShown =
                (ownOpacity == 0 ? 1 : ownOpacity) * (parentEntry?.opacityIfShown ?? 1)

            let box = quad.boundingBox
            let isPlaceable =
                (parentEntry?.isPlaceable ?? true)
                    && Self.hasFiniteGeometry(layer)
                    && quad.isWithin(Self.largestCoordinate)
            let hasArea =
                isPlaceable && abs(Polygon.signedArea(quad.outline)) > Polygon.areaEpsilon
            var entry = Entry(
                layer: layer, toWindow: map, quad: quad, box: box, hasArea: hasArea,
                isPlaceable: isPlaceable,
                isDisplayed: isDisplayed, isHidden: isHidden, isInFocus: isInFocus,
                isGhost: showsHidden && (isHidden || opacity == 0),
                isExpanded: expanded.contains(layer.id), hasChildren: hasChildren[index],
                standIn: standIn, level: 0, opacity: opacity,
                opacityIfShown: opacityIfShown)
            entry.layer.solo = nil
            entry.layer.group = nil
            entries.append(entry)
            if isDisplayed {
                displayed.append(index)
                if hasArea { contentBox = contentBox.map { $0.union(box) } ?? box }
            }
        }

        Self.assignLevels(&entries, displayed: displayed, contentBox: contentBox)
        let drawOrder = displayed.filter { entries[$0].hasArea }.sorted {
            (entries[$0].level, $0) < (entries[$1].level, $1)
        }
        let levelRanges = Self.levelRanges(of: drawOrder, in: entries)
        self.drawOrder = drawOrder
        self.levelRanges = levelRanges
        self.expanded = expanded
        self.focus = focus
        self.showsHidden = showsHidden
        self.stage = contentBox.map { Stage(contentBox: $0, topLevel: levelRanges.count - 1) }
        self.entries = entries
        self.images = ChunkedArray(layers.map { LayerTextures(solo: $0.solo, group: $0.group) })
        self.indexByID = indexByID
        self.parentIndices = parentIndex
        self.displayed = displayed
        self.contentBox = contentBox
        self.neededTextures = displayed.compactMap { index in
            let entry = entries[index]
            guard entry.hasArea, entry.layer.capturesImage else { return nil }
            return TextureNeed(layerID: entry.layer.id, kind: Self.neededKind(for: entry))
        }
    }

    /// The index of each layer, the index of each layer's parent, and whether each layer has
    /// sublayers.
    private static func parents(
        of layers: [SceneLayer]
    ) -> (indexByID: [UInt64: Int], parentIndex: [Int?], hasChildren: [Bool]) {
        var indexByID: [UInt64: Int] = [:]
        indexByID.reserveCapacity(layers.count)
        var parentIndex = [Int?](repeating: nil, count: layers.count)
        var hasChildren = [Bool](repeating: false, count: layers.count)
        for (index, layer) in layers.enumerated() {
            // A parent that does not come before its child makes the child a root.
            if layer.parentID != 0, let parent = indexByID[layer.parentID] {
                parentIndex[index] = parent
                hasChildren[parent] = true
            }
            indexByID[layer.id] = index
        }
        return (indexByID, parentIndex, hasChildren)
    }

    /// The positions in `drawOrder` of each level's layers.
    private static func levelRanges(of drawOrder: [Int], in entries: [Entry]) -> [Range<Int>] {
        var levelRanges: [Range<Int>] = []
        var start = 0
        for position in drawOrder.indices {
            let level = entries[drawOrder[position]].level
            let isLast = position == drawOrder.count - 1
            if isLast || entries[drawOrder[position + 1]].level != level {
                // Levels have no gaps: each one holds a layer that the next one overlaps.
                levelRanges.append(start..<(position + 1))
                start = position + 1
            }
        }
        return levelRanges
    }

    /// The textures the layout is drawn with, whatever the camera: those of the displayed
    /// layers that have an area and an image. The preview keeps these and no others
    /// (C-SCALE-02).
    public var drawnTextures: Set<TextureKey> {
        var textures = Set<TextureKey>(minimumCapacity: drawOrder.count)
        for index in drawOrder {
            if let texture = texture(at: index) { textures.insert(texture) }
        }
        return textures
    }

    /// The same layout with other images. Positions, levels and the draw order do not depend
    /// on images, so only the texture each layer is drawn with is chosen again.
    public func replacingTextures(_ textures: [UInt64: LayerTextures]) -> Self {
        var copy = self
        copy.images = ChunkedArray(entries.map { textures[$0.layer.id] ?? LayerTextures() })
        return copy
    }

    /// The same layout with other images for the layers in `ids` only, each with its entry
    /// in `textures` or no image; the others keep theirs. For a few layers, it costs what
    /// they cost (C-SCALE-02).
    public func replacingTextures(
        _ textures: [UInt64: LayerTextures], of ids: some Sequence<UInt64>
    ) -> Self {
        var copy = self
        for id in ids {
            guard let index = indexByID[id] else { continue }
            copy.images[index] = textures[id] ?? LayerTextures()
        }
        return copy
    }

    /// A layer's own opacity as it is drawn: within 0 and 1, and 1 when it is not a number
    /// (C-SCENE-06). Limited before it is multiplied down the tree, so that two negative
    /// values cannot make a visible layer.
    private static func ownOpacity(_ value: Double) -> Double {
        value.isNaN ? 1 : min(max(value, 0), 1)
    }

    /// C-SCENE-03 and P-DET-04: a collapsed node is drawn with its group; an expanded one with
    /// its solo. A layer without sublayers is drawn with its group, or its solo when it has no
    /// group: the two are the same picture, and the group is the kind asked for, so an older
    /// solo must not cover a newer group.
    func texture(at index: Int) -> TextureKey? {
        let entry = entries[index], images = images[index]
        guard entry.isDisplayed else { return nil }
        guard entry.isExpanded else { return images.group }
        guard entry.hasChildren else { return images.group ?? images.solo }
        return images.solo
    }

    /// The kind `texture(at:)` prefers. A leaf asks for its group: it equals the solo, and
    /// the app may send only the group for a layer without sublayers (P-DET-04).
    static func neededKind(for entry: Entry) -> TextureKey.Kind {
        entry.isExpanded && entry.hasChildren ? .solo : .group
    }

    /// The largest coordinate a corner may have: the drawing layer holds corners as `Float`,
    /// and a larger one would become infinite there (C-SCENE-11).
    static let largestCoordinate = Double(Float.greatestFiniteMagnitude)

    /// Whether every number the layer is placed with is finite, the parts of the transform
    /// the projection does not use included: any of them not being finite says the layer's
    /// geometry is broken (C-SCENE-11).
    private static func hasFiniteGeometry(_ layer: SceneLayer) -> Bool {
        let b = layer.bounds
        let t = layer.transform
        return [
            b.origin.x, b.origin.y, b.size.width, b.size.height,
            layer.position.x, layer.position.y, layer.anchorPoint.x, layer.anchorPoint.y,
            t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24,
            t.m31, t.m32, t.m33, t.m34, t.m41, t.m42, t.m43, t.m44,
        ].allSatisfy(\.isFinite)
    }

    /// P-HIER-06: subtract the anchor point, apply the transform, add the position.
    private static func localToParent(_ layer: SceneLayer) -> Affine2D {
        let b = layer.bounds
        let anchorX = b.origin.x + layer.anchorPoint.x * b.size.width
        let anchorY = b.origin.y + layer.anchorPoint.y * b.size.height
        let t = layer.transform
        return Affine2D.translation(-anchorX, -anchorY)
            .then(Affine2D(a: t.m11, b: t.m12, c: t.m21, d: t.m22, tx: t.m41, ty: t.m42))
            .then(.translation(layer.position.x, layer.position.y))
    }

    /// C-SCENE-02: one above the highest level among the displayed layers drawn before this
    /// one that overlap it, or 0. The layers already placed are filed by their boxes in the
    /// cells of a grid over the content box, each cell's layers from the highest level down,
    /// and those on many cells in a list of their own, kept the same way. A layer looks only
    /// in the cells under its box, and in each only until the levels left could not beat the
    /// highest overlap found: layers side by side (the cells of a list, what is inside each)
    /// are not compared with one another, which comparing every pair would do for thousands of
    /// layers.
    private static func assignLevels(
        _ entries: inout [Entry], displayed: [Int], contentBox: SceneRect?
    ) {
        guard let contentBox else {
            // No displayed layer has an area: every one is on level 0.
            for index in displayed { entries[index].level = 0 }
            return
        }
        let grid = LevelGrid(contentBox: contentBox, count: displayed.count)
        // What the search reads, out of the entries, by index into `entries`.
        var levels = [Int](repeating: 0, count: entries.count)
        var boxes = [SceneRect](repeating: .zero, count: entries.count)
        var outlines = [[ScenePoint]](repeating: [], count: entries.count)
        // When each layer was last compared, so that one in several cells is compared once.
        var lastQuery = [Int](repeating: -1, count: entries.count)
        var cells = [[Int]](repeating: [], count: grid.columns * grid.rows)
        var large: [Int] = []

        for (query, index) in displayed.enumerated() {
            // A layer without area overlaps nothing; it gets level 0 and no place, so that
            // corners that are not finite are never compared with the others' (C-SCENE-11).
            guard entries[index].hasArea else {
                entries[index].level = 0
                continue
            }
            let box = entries[index].box
            let outline = entries[index].quad.outline
            let covered = grid.cells(under: box)
            var level = 0
            // Goes down a list until its levels cannot raise `level`, stopping at an overlap.
            func search(_ list: [Int]) {
                for other in list {
                    let theirs = levels[other]
                    if theirs < level { return }
                    if lastQuery[other] == query { continue }
                    lastQuery[other] = query
                    if boxes[other].overlaps(box), Polygon.overlap(outline, outlines[other]) {
                        level = theirs + 1
                        return
                    }
                }
            }
            search(large)
            for row in covered.rows {
                for column in covered.columns { search(cells[row * grid.columns + column]) }
            }
            entries[index].level = level
            levels[index] = level
            boxes[index] = box
            outlines[index] = outline
            // Puts the layer after every one of its level or higher.
            func file(_ list: inout [Int]) {
                var low = 0, high = list.count
                while low < high {
                    let middle = (low + high) / 2
                    if levels[list[middle]] >= level { low = middle + 1 } else { high = middle }
                }
                list.insert(index, at: low)
            }
            if covered.count > LevelGrid.largestFiled {
                file(&large)
            } else {
                for row in covered.rows {
                    for column in covered.columns { file(&cells[row * grid.columns + column]) }
                }
            }
        }
    }

    /// Whether the two are the same laying out of the layers, with the same or other images.
    public func isSameBuild(as other: Self) -> Bool {
        build === other.build
    }

    /// Whether the two were built with other nodes expanded: the one thing that makes a
    /// transition from one to the other (C-SCENE-10). Cheap next to `presentation`.
    public func expandsOtherNodes(than other: Self) -> Bool {
        expanded != other.expanded
    }

    /// Whether the two lay out the same layers in the same places with the same focus and
    /// the same rule for hidden layers, whatever their images: only the expansion can tell
    /// them apart, and then one can turn into the other (C-SCENE-10). The entries' layers
    /// hold no images.
    func showsSameLayers(as other: Self) -> Bool {
        guard focus == other.focus, showsHidden == other.showsHidden,
              entries.count == other.entries.count
        else { return false }
        for index in entries.indices where entries[index].layer != other.entries[index].layer {
            return false
        }
        return true
    }

    /// Whether the two hold the layers' places in the same storage: one is the other with
    /// other images. For tests.
    func sharesGeometry(with other: Self) -> Bool {
        entries.withUnsafeBufferPointer { mine in
            other.entries.withUnsafeBufferPointer { theirs in mine.baseAddress == theirs.baseAddress }
        }
    }

    /// How many images, and references to parts of them, were copied to make this from
    /// `other`. For tests.
    func imagesCopied(since other: Self) -> Int {
        images.copiedElements(since: other.images)
    }

    private func entry(_ id: UInt64) -> Entry? {
        indexByID[id].map { entries[$0] }
    }

    /// The layer's corners in window coordinates, whether it is displayed or not. Nil for an
    /// unknown layer and for one that cannot be placed (C-SCENE-11).
    public func quad(of id: UInt64) -> Quad? {
        entry(id).flatMap { $0.isPlaceable ? $0.quad : nil }
    }

    /// The corners of a rectangle given in the layer's bounds coordinates, in window
    /// coordinates: the same map as the layer's own corners (P-HIER-06). Nil for an unknown
    /// layer. A layout guide is placed this way, in its owner (C-SCENE-08).
    public func quad(of rect: SceneRect, in id: UInt64) -> Quad? {
        guard let entry = entry(id), entry.isPlaceable else { return nil }
        let map = entry.toWindow
        let quad = Quad(
            topLeft: map.apply(ScenePoint(x: rect.minX, y: rect.minY)),
            topRight: map.apply(ScenePoint(x: rect.maxX, y: rect.minY)),
            bottomLeft: map.apply(ScenePoint(x: rect.minX, y: rect.maxY)),
            bottomRight: map.apply(ScenePoint(x: rect.maxX, y: rect.maxY)))
        return quad.isWithin(Self.largestCoordinate) ? quad : nil
    }

    /// Whether the layer is drawn: neither it nor an ancestor is hidden, and every ancestor
    /// is expanded.
    public func isDisplayed(_ id: UInt64) -> Bool {
        entry(id)?.isDisplayed ?? false
    }

    /// The level of a displayed layer; for a layer inside a collapsed node, the level of that
    /// node. Nil for a hidden layer.
    public func level(of id: UInt64) -> Int? {
        guard let standIn = entry(id)?.standIn else { return nil }
        return entries[standIn].level
    }

    /// The image a displayed layer is drawn with, if any.
    public func texture(of id: UInt64) -> TextureKey? {
        indexByID[id].flatMap(texture(at:))
    }

    /// Whether a displayed layer is one that cannot be seen, shown because hidden layers
    /// are (C-PREV-08).
    public func isGhost(_ id: UInt64) -> Bool {
        entry(id).map { $0.isDisplayed && $0.isGhost } ?? false
    }

    /// The layer's opacity times that of every ancestor.
    public func opacity(of id: UInt64) -> Double? {
        entry(id)?.opacity
    }
}
