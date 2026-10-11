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
                switch item {
                case .view(let id) where id != selected:
                    if views.insert(id).inserted { ends.append(Self(mark: .layer(id))) }
                case .layoutGuide(let guide):
                    guard let frame = guide.frame,
                          [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
                          .allSatisfy(\.isFinite),
                          guides.insert([guide.ownerLayerID, guide.guideID]).inserted
                    else { continue }
                    ends.append(
                        Self(
                            mark: .area(SceneRect(frame), in: guide.ownerLayerID), guide: guide))
                default:
                    continue
                }
            }
        }
        return ends
    }
}
