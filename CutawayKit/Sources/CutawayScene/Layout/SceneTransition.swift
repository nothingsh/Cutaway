/// The picture on screen, still or in the middle of a transition: which layers are drawn,
/// where, on which level and with which image (C-SCENE-10). A transition starts from one, so
/// that a change in the middle of another starts from what is shown.
public struct ScenePresentation: Sendable {
    /// The layout shown, or the one a transition is on its way to.
    let layout: SceneLayout
    let placements: [Placement]
    let stage: Stage?
}

extension SceneLayout {
    /// The layout standing still.
    public var presentation: ScenePresentation {
        ScenePresentation(layout: self, placements: drawOrder.map(placement(of:)), stage: stage)
    }

    /// The layer's parent among the layers, as the layout took it: a parent that does not
    /// come before its child makes the child a root.
    func parentIndex(of index: Int) -> Int? {
        let parentID = entries[index].layer.parentID
        guard parentID != 0, let parent = indexByID[parentID], parent < index else { return nil }
        return parent
    }

    /// The layer's newest image of a kind, as this layout holds it. A layer without
    /// sublayers drawn with its group is drawn with its solo when it has no group, as
    /// `texture(at:)` does.
    func currentTexture(_ kind: TextureKey.Kind, of index: Int) -> TextureKey? {
        let images = images[index]
        switch kind {
        case .solo: return images.solo
        case .group: return images.group ?? (entries[index].hasChildren ? nil : images.solo)
        }
    }
}

/// From the picture on screen to a layout of the same layers with other nodes expanded
/// (C-SCENE-10). Every layer drawn at either end moves from its level at the start to its
/// level at the end; a layer drawn at one end only stands, at the other, on the level of its
/// nearest ancestor drawn there, where that ancestor's image shows it. A layer being expanded
/// takes its end image at once, its sublayers rising out of it; a layer being collapsed keeps
/// its image until the end, its sublayers coming down onto it, and only then do they go and
/// it takes its end image. The progress is eased already, from 0 to 1.
public struct SceneTransition: Sendable {
    private struct Move: Sendable {
        /// Its level and image are those of the start.
        var placement: Placement
        var from: Double
        var to: Double
        var endTexture: TextureKey?
        var endKind: TextureKey.Kind
        /// Whether it keeps the start image until the end: it leaves, or layers that leave
        /// come down onto it.
        var keepsStartImage: Bool
        /// Whether it is not drawn at the end.
        var leaves: Bool
    }

    /// Where the transition ends.
    public let end: SceneLayout
    private let startStage: Stage
    private let endStage: Stage
    /// In the order of the wire.
    private var moves: [Move]
    /// From a layer's index in the layout to its move.
    private let moveByIndex: [Int: Int]

    /// Nil unless the two differ in nothing but which nodes are expanded: then there is
    /// nothing to move, or the layers are others.
    public init?(from start: ScenePresentation, to end: SceneLayout) {
        guard start.layout.expanded != end.expanded, start.layout.showsSameLayers(as: end),
              let startStage = start.stage, let endStage = end.stage
        else { return nil }
        self.end = end
        self.startStage = startStage
        self.endStage = endStage

        let startByID = Dictionary(
            start.placements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var moves: [Move] = []
        var moveByIndex: [Int: Int] = [:]
        for index in end.drawOrder {
            let placement = end.placement(of: index)
            var move = Move(
                placement: placement, from: placement.level, to: placement.level,
                endTexture: placement.texture, endKind: placement.kind, keepsStartImage: false,
                leaves: false)
            if let before = startByID[placement.id] {
                move.from = before.level
                move.placement.kind = before.kind
                move.placement.texture = end.currentTexture(before.kind, of: index)
            } else {
                move.placement.drawnAt = .end
                // Rising out of the nearest ancestor drawn at the start.
                var ancestor = end.parentIndex(of: index)
                while let current = ancestor {
                    if let before = startByID[end.entries[current].layer.id] {
                        move.from = before.level
                        break
                    }
                    ancestor = end.parentIndex(of: current)
                }
                move.placement.texture = placement.texture
            }
            moveByIndex[index] = moves.count
            moves.append(move)
        }
        // The moves so far are the layers drawn at the end; only they can be come down onto.
        let drawnAtTheEnd = moves.count
        for before in start.placements where moveByIndex[before.index] == nil {
            var move = Move(
                placement: before, from: before.level, to: before.level, endTexture: nil,
                endKind: before.kind, keepsStartImage: true, leaves: true)
            move.placement.drawnAt = .start
            move.placement.texture = end.currentTexture(before.kind, of: before.index)
            // Coming down onto the nearest ancestor drawn at the end.
            var ancestor = end.parentIndex(of: before.index)
            while let current = ancestor {
                if let target = moveByIndex[current], target < drawnAtTheEnd {
                    move.to = moves[target].placement.level
                    if startByID[moves[target].placement.id] != nil {
                        moves[target].keepsStartImage = true
                    }
                    break
                }
                ancestor = end.parentIndex(of: current)
            }
            moveByIndex[before.index] = moves.count
            moves.append(move)
        }
        // Nothing moves: the change is out of sight (inside a collapsed node, or of a layer
        // without sublayers drawn), and there is nothing to show on the way.
        guard moves.contains(where: { $0.from != $0.to }) else { return nil }
        // The level in `placement` is set per frame.
        let order = moves.indices.sorted { moves[$0].placement.index < moves[$1].placement.index }
        self.moves = order.map { moves[$0] }
        var byIndex: [Int: Int] = [:]
        for (position, move) in self.moves.enumerated() { byIndex[move.placement.index] = position }
        self.moveByIndex = byIndex
    }

    /// The same transition ending on `layout`, the end with other images
    /// (`SceneLayout.replacingTextures`): the images that arrive on the way are used without
    /// starting again. Nil for any other layout, even one laid out again the same way.
    public func retargeted(to layout: SceneLayout) -> Self? {
        guard layout.isSameBuild(as: end) else { return nil }
        var copy = self
        copy.moves = moves.map { move in
            var move = move
            let index = move.placement.index
            move.placement.texture = layout.currentTexture(move.placement.kind, of: index)
            if !move.leaves { move.endTexture = layout.texture(at: index) }
            return move
        }
        return Self(copy, end: layout)
    }

    private init(_ other: Self, end: SceneLayout) {
        self.end = end
        startStage = other.startStage
        endStage = other.endStage
        moves = other.moves
        moveByIndex = other.moveByIndex
    }

    /// The textures any frame of the transition is drawn with, the end's still picture
    /// included: a layer that keeps its start image until the end takes its end image only
    /// then (C-SCALE-02).
    public var drawnTextures: Set<TextureKey> {
        var textures = end.drawnTextures
        for move in moves {
            if let texture = move.keepsStartImage ? move.placement.texture : move.endTexture {
                textures.insert(texture)
            }
        }
        return textures
    }

    /// The layers as drawn at `progress`, in the order of the wire.
    private func placements(at t: Double) -> [Placement] {
        moves.map { move in
            var placement = move.placement
            placement.level = lerp(move.from, move.to, t)
            if !move.keepsStartImage {
                placement.texture = move.endTexture
                placement.kind = move.endKind
            }
            return placement
        }
    }

    /// The frame at `progress`; from 1 on, the end's projection. Marks and the measurement
    /// as in `SceneLayout.project`, with each mark on the level its layer is on in this frame.
    /// On the way the levels are fractions: the measurement is given only facing the layers
    /// square on, where the levels do not show (C-SCENE-12).
    public func project(
        progress: Double, lens: Lens, viewport: Viewport, selected: UInt64?, hovered: UInt64?,
        marks: [SceneMark] = [], measuring: UInt64? = nil
    ) -> DrawList {
        if progress >= 1 {
            return end.project(
                lens: lens, viewport: viewport, selected: selected, hovered: hovered,
                marks: marks, measuring: measuring)
        }
        guard viewport.width > 0, viewport.height > 0 else { return .empty }
        let projector = Projector(
            lens: lens, stage: startStage.interpolated(to: endStage, progress: progress))
        let placements = placements(at: progress)
        let remoteness = placements.map { projector.remoteness(ofLevel: $0.level) }
        let backToFront = placements.indices.sorted { a, b in
            let la = placements[a].level, lb = placements[b].level
            if la != lb {
                return remoteness[a] != remoteness[b] ? remoteness[a] > remoteness[b] : la < lb
            }
            return placements[a].index < placements[b].index
        }
        let content = FrameContent(
            placements: placements, backToFront: backToFront, selected: selected,
            hovered: hovered, marks: end.placedMarks(marks) { level(of: $0, at: progress) },
            measurement: lens.facesSquareOn
                ? end.placedMeasurement(selected: selected, measuring: measuring) : nil)
        return SceneLayout.frame(
            content, projector: projector, lens: lens, viewport: viewport, progress: progress)
    }

    /// What is on screen at `progress`, for a transition that starts there.
    public func presentation(at progress: Double) -> ScenePresentation {
        if progress >= 1 { return end.presentation }
        return ScenePresentation(
            layout: end, placements: placements(at: progress),
            stage: startStage.interpolated(to: endStage, progress: progress))
    }

    /// The level a layer is on at `progress`: its own when it is drawn, otherwise that of its
    /// nearest drawn ancestor. A layer displayed at the end without an area, which is never
    /// drawn, stays on its level there, as in the still picture. Nil for a layer that is not
    /// in the picture at the end (unknown, hidden while hidden layers are not shown, outside
    /// the focus).
    public func level(of id: UInt64, at progress: Double) -> Double? {
        guard let index = end.indexByID[id], let fallback = end.level(of: id) else { return nil }
        if moveByIndex[index] == nil, end.entries[index].standIn == index {
            return Double(fallback)
        }
        var current: Int? = index
        while let layer = current {
            if let position = moveByIndex[layer] {
                return lerp(moves[position].from, moves[position].to, progress)
            }
            current = end.parentIndex(of: layer)
        }
        return Double(fallback)
    }
}
