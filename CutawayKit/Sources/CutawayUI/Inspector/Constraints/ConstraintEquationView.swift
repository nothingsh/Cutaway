import AppKit
import CutawayModel

/// A constraint's equation: text that wraps and can be selected, in which the other ends are
/// chips (C-LAYOUT-06). Pointing at a chip hovers its layer and stresses its mark on the
/// preview; clicking one selects its layer (C-LAYOUT-03).
final class ConstraintEquationView: ChipTextView, NSTextViewDelegate {
    static let identifier = "constraints.equation"

    private let onShowLayer: (UInt64) -> Void
    /// The chip under the pointer, or nil when it leaves the chips (C-LAYOUT-06).
    var onHoverEnd: (ConstraintRow.End?) -> Void = { _ in }
    /// The equation as words, a chip by its name: what it says, for tests and accessibility.
    let plainText: String

    init(
        _ pieces: [ConstraintRow.Piece], dimmed: Bool, onShowLayer: @escaping (UInt64) -> Void
    ) {
        self.onShowLayer = onShowLayer
        plainText = ConstraintRow.plain(pieces)
        super.init()
        delegate = self
        setAccessibilityIdentifier(Self.identifier)
        setAccessibilityValue(plainText)
        textStorage?.setAttributedString(Self.attributed(pieces, dimmed: dimmed))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Every chip, with its character, in order.
    var chips: [(index: Int, cell: ConstraintChipCell)] {
        chipCells.compactMap { index, cell in (cell as? ConstraintChipCell).map { (index, $0) } }
    }

    /// The layers the chips that can be clicked go to, in order. For tests.
    var linkedLayerIDs: [UInt64] {
        chips.compactMap(\.cell.end.layerID)
    }

    /// Clicks the chip of a layer, as the mouse does. For tests.
    func clickLink(to id: UInt64) {
        if let cell = chips.first(where: { $0.cell.end.layerID == id })?.cell { chose(cell) }
    }

    /// Puts the pointer on the chip of an end, or on none, as the mouse does. For tests.
    func hoverEnd(at index: Int?) {
        point(at: index)
    }

    override func pointed(at cell: LayerChipCell?) {
        onHoverEnd((cell as? ConstraintChipCell)?.end)
    }

    override func chose(_ cell: LayerChipCell) {
        guard let id = cell.chip.layerID else { return }
        onShowLayer(id)
    }

    private static func attributed(
        _ pieces: [ConstraintRow.Piece], dimmed: Bool
    ) -> NSAttributedString {
        let font = Theme.Font.constraint
        let color: NSColor = dimmed ? .secondaryLabelColor : .labelColor
        let result = NSMutableAttributedString()
        for piece in pieces {
            switch piece {
            case .text(let text):
                result.append(NSAttributedString(
                    string: text, attributes: [.font: font, .foregroundColor: color]))
            case .selfItem:
                result.append(NSAttributedString(
                    string: "self",
                    attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            case .end(let end):
                result.append(attachment(ConstraintChipCell(end, dimmed: dimmed), font: font))
            }
        }
        return result
    }
}

extension ConstraintRow {
    /// Pieces as words, a chip by its name.
    static func plain(_ pieces: [Piece]) -> String {
        pieces.map { piece in
            switch piece {
            case .text(let text): text
            case .selfItem: "self"
            case .end(let end): end.name
            }
        }.joined()
    }
}

/// The chip of a constraint's other end (C-LAYOUT-06): the end's layer, or its layout guide.
final class ConstraintChipCell: LayerChipCell {
    let end: ConstraintRow.End

    init(_ end: ConstraintRow.End, dimmed: Bool) {
        self.end = end
        let icon: LayerChip.Icon = switch end.kind {
        case .view(let icon): .layer(icon)
        case .guide: .guide
        }
        super.init(
            LayerChip(name: end.name, icon: icon, layerID: end.layerID, canHover: end.canHover),
            dimmed: dimmed, textFont: Theme.Font.constraint)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
