import AppKit
import CutawayWire

/// The value of an attribute that refers to objects (C-ATTR-28): a chip for each, as a
/// constraint's other end has (C-LAYOUT-06), wrapping onto more lines. Pointing at a chip whose
/// layer is in the hierarchy hovers that layer; clicking it selects it. Six chips at first, then
/// "n More", which shows the rest for as long as the row lives: another layer's row starts with
/// six again. Read-only (P-ATTR-18); no objects read as "None".
final class ReferenceChipsView: ChipTextView, NSTextViewDelegate {
    static let identifier = "attributes.references"
    /// How many chips show before "n More".
    static let limit = 6

    private let makeChips: ([ObjectReference]) -> [LayerChip]
    private let onShowLayer: (UInt64) -> Void
    private let onHoverLayer: (UInt64?) -> Void
    /// Every chip, and those shown.
    private(set) var allChips: [LayerChip] = []
    private(set) var isShowingAll = false
    /// Called when the view may have grown or shrunk by a line.
    var onHeightChange: () -> Void = {}

    init(
        chips: @escaping ([ObjectReference]) -> [LayerChip], onShowLayer: @escaping (UInt64) -> Void,
        onHoverLayer: @escaping (UInt64?) -> Void
    ) {
        makeChips = chips
        self.onShowLayer = onShowLayer
        self.onHoverLayer = onHoverLayer
        super.init()
        delegate = self
        setAccessibilityIdentifier(Self.identifier)
        linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows a value: the chips of its references, or "None".
    func show(_ value: AttributeValue?) {
        guard case .references(let references) = value else {
            showChips([])
            return
        }
        showChips(makeChips(references))
    }

    private func showChips(_ chips: [LayerChip]) {
        allChips = chips
        let font = Self.textFont
        let text = NSMutableAttributedString()
        if chips.isEmpty {
            text.append(NSAttributedString(
                string: localized("attributes.value.none"),
                attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        for (index, chip) in shownChips.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: " ", attributes: [.font: font])) }
            text.append(Self.attachment(LayerChipCell(chip, dimmed: false, textFont: font), font: font))
        }
        if let more = moreText {
            text.append(NSAttributedString(string: " ", attributes: [.font: font]))
            text.append(NSAttributedString(string: more, attributes: [.font: Self.moreFont, .link: Self.moreLink]))
        }
        setText(text)
        setAccessibilityValue(chips.map(\.name).joined(separator: ", "))
        onHeightChange()
    }

    private static let textFont = NSFont.systemFont(ofSize: 12)
    private static let moreFont = NSFont.systemFont(ofSize: 11)
    private static let moreLink = "cutaway-more"

    /// The chips shown: six until "n More" is clicked.
    var shownChips: [LayerChip] {
        isShowingAll || allChips.count <= Self.limit ? allChips : Array(allChips.prefix(Self.limit))
    }

    /// "2 More", or nil when every chip shows.
    var moreText: String? {
        let hidden = allChips.count - shownChips.count
        return hidden > 0 ? localized("attributes.reference.more", hidden) : nil
    }

    /// Shows every chip, as "n More" does.
    func showAll() {
        guard !isShowingAll else { return }
        isShowingAll = true
        showChips(allChips)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard link as? String == Self.moreLink else { return false }
        showAll()
        return true
    }

    override func pointed(at cell: LayerChipCell?) {
        onHoverLayer(cell?.chip.layerID)
    }

    override func chose(_ cell: LayerChipCell) {
        guard let id = cell.chip.layerID else { return }
        onShowLayer(id)
    }

    /// Whether it takes more than one line: its title then goes at its top (C-ATTR-12).
    var isTall: Bool { intrinsicContentSize.height > LayerChipCell.height + 4 }

    override func setFrameSize(_ newSize: NSSize) {
        let wasTall = isTall
        super.setFrameSize(newSize)
        if isTall != wasTall { onHeightChange() }
    }

    // MARK: - For tests

    /// The layers of the chips that can be clicked, in order.
    var linkedLayerIDs: [UInt64] { shownChips.compactMap(\.layerID) }

    /// Puts the pointer on the chip at a place among those shown, or on none.
    func hoverChip(at place: Int?) {
        point(at: place.flatMap { chipCells.indices.contains($0) ? chipCells[$0].index : nil })
    }

    /// Clicks the chip at a place among those shown, as the mouse does.
    func clickChip(at place: Int) {
        guard chipCells.indices.contains(place) else { return }
        let cell = chipCells[place].cell
        if cell.chip.canSelect { chose(cell) }
    }
}
