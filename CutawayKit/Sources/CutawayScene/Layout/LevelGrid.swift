/// Cells over the content box that the layers already given a level are filed in by their
/// boxes (C-SCENE-02). Square cells, about two layers' worth across the content box
/// for each one, at most 128 a side.
struct LevelGrid {
    /// The cells a box lies on: columns and rows, inclusive, clamped to the grid.
    struct Cells {
        var columns: ClosedRange<Int>
        var rows: ClosedRange<Int>

        var count: Int { columns.count * rows.count }
    }

    /// A box on more cells than this goes in the list of large layers.
    static let largestFiled = 16

    let origin: ScenePoint
    let side: Double
    let columns: Int
    let rows: Int

    init(contentBox: SceneRect, count: Int) {
        let across = min(max(Int(Double(count).squareRoot() / 2), 1), 128)
        let longest = max(contentBox.size.width, contentBox.size.height)
        origin = contentBox.origin
        side = longest > 0 ? longest / Double(across) : 1
        columns = max(Int((contentBox.size.width / side).rounded(.up)), 1)
        rows = max(Int((contentBox.size.height / side).rounded(.up)), 1)
    }

    func cells(under box: SceneRect) -> Cells {
        Cells(
            columns: index(box.minX - origin.x, below: columns)...index(box.maxX - origin.x, below: columns),
            rows: index(box.minY - origin.y, below: rows)...index(box.maxY - origin.y, below: rows))
    }

    /// The cell an offset falls in, clamped to the grid: a box on its edge, or a little
    /// beyond it through rounding, lies on the edge's cells.
    private func index(_ offset: Double, below limit: Int) -> Int {
        let cell = (offset / side).rounded(.down)
        guard cell.isFinite, cell > 0 else { return 0 }
        return cell >= Double(limit - 1) ? limit - 1 : Int(cell)
    }
}
