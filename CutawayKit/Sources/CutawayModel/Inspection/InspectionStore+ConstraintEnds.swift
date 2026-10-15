import CutawayScene

/// Which other ends of the selected layer's constraints the preview marks (C-LAYOUT-04,
/// C-LAYOUT-06, C-LAYOUT-07, C-PREV-18).
extension InspectionStore {
    /// The pointer is on the chip of a constraint's other end in the attribute panel, or on
    /// none (C-LAYOUT-06): the end's layer is the hovered one, as a row's is (C-HIER-15), and
    /// its mark is shown and stressed. A mark that is not one of the ends is not; a guide of
    /// the selected view hovers no layer.
    public func hoverConstraintEnd(_ mark: SceneMark?, layerID: UInt64?) {
        if mark != heldConstraints.chip {
            heldConstraints.chip = mark
            showConstraintEnds()
        }
        hover(layerID)
    }

    /// The pointer is on constraints of the selected layer in the attribute panel, by their
    /// places in the server's order (C-LAYOUT-07): a row's, whose ends are stressed, or the
    /// folded UIKit ones, whose ends are not.
    public func pointConstraints(_ indices: [Int], stresses: Bool) {
        let pointing = ConstraintPointing(indices, stresses: stresses)
        guard pointing != heldConstraints.pointing else { return }
        heldConstraints.pointing = pointing
        showConstraintEnds()
    }

    /// The pointer left the constraints at `indices`. Nothing changes when it is on others
    /// already: leaving one row may be told after entering the next.
    public func leaveConstraints(_ indices: [Int]) {
        guard heldConstraints.pointing?.indices == indices else { return }
        heldConstraints.pointing = nil
        showConstraintEnds()
    }

    /// Marks every end of the selected layer's constraints, or only those pointed at
    /// (C-PREV-18). Only the marks change.
    public func setShowsAllConstraintEnds(_ shows: Bool) {
        guard shows != showsAllConstraintEnds else { return }
        showsAllConstraintEnds = shows
        showConstraintEnds()
    }

    /// Turns the switch over (⇧⌘K, C-PREV-18).
    public func toggleConstraintEnds() {
        setShowsAllConstraintEnds(!showsAllConstraintEnds)
    }

    /// Publishes what the preview marks now, each only when it changed.
    func showConstraintEnds() {
        let shown = heldConstraints.shown(showsAll: showsAllConstraintEnds)
        if shown.ends != constraintEnds { constraintEnds = shown.ends }
        if shown.stressed != emphasizedConstraintEnds { emphasizedConstraintEnds = shown.stressed }
    }
}
