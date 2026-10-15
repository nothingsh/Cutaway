import CutawayScene
import CutawayWire

/// One end of the selected layer's constraints to point out on the preview (C-LAYOUT-04).
public struct ConstraintEnd: Equatable, Sendable {
    public var mark: SceneMark
    /// The guide, for an end that is one.
    public var guide: LayoutGuide?

    public init(mark: SceneMark, guide: LayoutGuide? = nil) {
        self.mark = mark
        self.guide = guide
    }

    /// The ends of `constraints` other than the selected view itself, in the constraints'
    /// order, first item before second, each once: views by their layers, layout guides by
    /// their frames in their owners (P-LAYOUT-04). A guide of the selected view is an end. A
    /// guide without a frame or with one that is not finite (a server that breaks P-LAYOUT-04),
    /// an end that is neither a view nor a guide, and a missing end are not marked.
    public static func ends(of constraints: [LayoutConstraint], selected: UInt64) -> [Self] {
        var ends: [Self] = []
        var views = Set<UInt64>()
        var guides = Set<[UInt64]>()
        for constraint in constraints {
            for item in [constraint.firstItem, constraint.secondItem] {
                guard let mark = mark(of: item, selected: selected) else { continue }
                switch item {
                case .view(let id):
                    if views.insert(id).inserted { ends.append(Self(mark: mark)) }
                case .layoutGuide(let guide):
                    if guides.insert([guide.ownerLayerID, guide.guideID]).inserted {
                        ends.append(Self(mark: mark, guide: guide))
                    }
                default:
                    continue
                }
            }
        }
        return ends
    }

    /// What the preview marks for one end of a constraint of the selected view: a view by its
    /// layer, a layout guide by its frame in its owner (P-LAYOUT-04). Nil for the selected view
    /// itself, a guide without a finite frame, an end that is neither, and a missing end. The
    /// attribute panel's chip for the end points at the same mark (C-LAYOUT-06).
    public static func mark(of item: LayoutItem?, selected: UInt64) -> SceneMark? {
        switch item {
        case .view(let id) where id != selected:
            return .layer(id)
        case .layoutGuide(let guide):
            guard let frame = guide.frame,
                  [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
                  .allSatisfy(\.isFinite)
            else { return nil }
            return .area(SceneRect(frame), in: guide.ownerLayerID)
        default:
            return nil
        }
    }
}

/// The constraints of the selected view the pointer is on in the attribute panel, by their
/// places in the server's order (C-LAYOUT-07): one row's, whose ends are stressed, or those
/// folded into "N from UIKit", whose ends are marked plainly.
public struct ConstraintPointing: Equatable, Sendable {
    public var indices: [Int]
    public var stresses: Bool

    public init(_ indices: [Int], stresses: Bool = true) {
        self.indices = indices
        self.stresses = stresses
    }
}

/// The selected layer's constraints while they are held, and what the pointer is on among
/// them in the attribute panel: what the marks of their ends are made from (C-LAYOUT-04,
/// C-LAYOUT-06, C-LAYOUT-07).
struct HeldConstraints: Equatable, Sendable {
    var constraints: [LayoutConstraint] = []
    /// The layer the constraints are of; nil while none are held.
    var owner: UInt64?
    /// The constraints the pointer is on (C-LAYOUT-07).
    var pointing: ConstraintPointing?
    /// The chip of an end the pointer is on (C-LAYOUT-06).
    var chip: SceneMark?

    /// Holds these constraints of this layer. The rows are built again when they differ
    /// from those held: what the pointer was on is gone with them. False when nothing
    /// changed.
    mutating func hold(_ constraints: [LayoutConstraint], of owner: UInt64?) -> Bool {
        guard constraints != self.constraints || owner != self.owner else { return false }
        self.constraints = constraints
        self.owner = owner
        pointing = nil
        chip = nil
        return true
    }

    /// What the preview marks (`ConstraintEnd.shown`); nothing while none are held.
    func shown(showsAll: Bool) -> ConstraintEnd.Shown {
        guard let owner else { return ConstraintEnd.Shown() }
        return ConstraintEnd.shown(
            of: constraints, selected: owner, showsAll: showsAll, pointing: pointing, chip: chip)
    }
}

extension ConstraintEnd {
    /// The ends the preview marks, and those of them it stresses.
    public struct Shown: Equatable, Sendable {
        public var ends: [ConstraintEnd] = []
        public var stressed: [SceneMark] = []

        public init(ends: [ConstraintEnd] = [], stressed: [SceneMark] = []) {
            self.ends = ends
            self.stressed = stressed
        }
    }

    /// What the preview marks of the selected view's constraints. With `showsAll` (C-PREV-18),
    /// every end (C-LAYOUT-04); otherwise only the ends of the constraints pointed at
    /// (C-LAYOUT-07), and of the chip pointed at (C-LAYOUT-06). The chip's end is stressed;
    /// failing that, a pointed row's ends. A chip that is not an end counts for nothing, nor
    /// do places the constraints do not have.
    public static func shown(
        of constraints: [LayoutConstraint], selected: UInt64, showsAll: Bool,
        pointing: ConstraintPointing?, chip: SceneMark?
    ) -> Shown {
        let all = ends(of: constraints, selected: selected)
        let chipEnd = chip.flatMap { chip in all.first { $0.mark == chip } }
        let pointed = pointing.map { pointing in
            ends(
                of: pointing.indices.filter(constraints.indices.contains).map { constraints[$0] },
                selected: selected)
        } ?? []
        let stressed: [SceneMark] = if let chipEnd {
            [chipEnd.mark]
        } else if pointing?.stresses == true {
            pointed.map(\.mark)
        } else {
            []
        }
        if showsAll { return Shown(ends: all, stressed: stressed) }
        // In the order of all the ends, each once.
        let shown = all.filter { end in pointed.contains(end) || end == chipEnd }
        return Shown(ends: shown, stressed: stressed)
    }
}
