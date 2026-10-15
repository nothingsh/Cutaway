import AppKit
import CutawayModel
import DeclarativeAppKit

/// How many of a layer's ancestors the header's line shows (C-ATTR-16): the nearest ones, at
/// most `maximum`, as many as fit; the rest fold into "⋯n" before them. The nearest one shows
/// however narrow the line.
enum AncestorFolding {
    static let maximum = 3

    /// How many of the nearest ancestors show. `widths` are the ancestors', farthest first; a
    /// separator goes between two of them and after "⋯n", which is `overflow` wide.
    static func shownCount(
        widths: [CGFloat], available: CGFloat, separator: CGFloat, overflow: CGFloat
    ) -> Int {
        guard !widths.isEmpty else { return 0 }
        var count = min(maximum, widths.count)
        while count > 1 {
            let folded = widths.count - count
            let separators = CGFloat(count - 1 + (folded > 0 ? 1 : 0))
            let needed = widths.suffix(count).reduce(0, +) + separators * separator
                + (folded > 0 ? overflow : 0)
            if needed <= available { break }
            count -= 1
        }
        return count
    }
}

/// The selected layer's ancestors under the attribute panel's header (C-ATTR-16): each its
/// icon and short name, farthest first, separated by "›"; those that do not show are in the
/// menu of "⋯n" before them. Pointing at one hovers it, as a row of the list does (C-HIER-15);
/// clicking one, or its item in the menu, selects it.
final class AncestorsBar: NSView {
    static let identifier = "attributes.ancestors"
    static let overflowIdentifier = "attributes.ancestors.more"
    static let iconSide: CGFloat = 13
    static let font = NSFont.systemFont(ofSize: 11)

    var onHover: (UInt64?) -> Void = { _ in }
    var onSelect: (UInt64) -> Void = { _ in }

    private(set) var ancestors: [LayerSummary.Ancestor] = []
    /// One to an ancestor, farthest first, each with the separator before it.
    private(set) var buttons: [AncestorButton] = []
    private var separators: [NSTextField] = []
    private(set) lazy var overflowButton: NSButton = .init().configure {
        $0.isBordered = false
        $0.font = Self.font
        $0.contentTintColor = .tertiaryLabelColor
        $0.setAccessibilityIdentifier(Self.overflowIdentifier)
        $0.target = self
        $0.action = #selector(showOverflow(_:))
    }

    private let stack = NSStackView().configure {
        $0.orientation = .horizontal
        $0.alignment = .centerY
        $0.spacing = 1
        $0.setHuggingPriority(.defaultLow, for: .horizontal)
    }

    /// How many of the nearest ancestors show, as last laid out.
    private(set) var shownCount = 0
    private var laidOutWidth: CGFloat = -1

    var isEnabled = true {
        didSet {
            for button in buttons { button.isEnabled = isEnabled }
            overflowButton.isEnabled = isEnabled
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityIdentifier(Self.identifier)
        setAccessibilityRole(.group)
        setAccessibilityLabel(localized("attributes.ancestors"))
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        // The line never asks for more width than it is given: what does not fit folds.
        setContentCompressionResistancePriority(.init(1), for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 20)
    }

    /// Shows another layer's ancestors.
    func show(_ ancestors: [LayerSummary.Ancestor]) {
        guard ancestors != self.ancestors else { return }
        self.ancestors = ancestors
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        separators = ancestors.map { _ in
            NSTextField(labelWithString: "›").configure {
                $0.font = Self.font
                $0.textColor = .tertiaryLabelColor
                $0.setAccessibilityElement(false)
            }
        }
        buttons = ancestors.map { ancestor in
            AncestorButton(ancestor).configure {
                $0.isEnabled = isEnabled
                $0.target = self
                $0.action = #selector(select(_:))
                $0.onHover = { [weak self] id in self?.onHover(id) }
            }
        }
        stack.addArrangedSubview(overflowButton)
        for (separator, button) in zip(separators, buttons) {
            stack.addArrangedSubview(separator)
            stack.addArrangedSubview(button)
        }
        laidOutWidth = -1
        fold(toFit: bounds.width)
        needsLayout = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        // Another width may fit more or fewer ancestors.
        if widthChanged { needsLayout = true }
    }

    override func layout() {
        if abs(bounds.width - laidOutWidth) > 0.5 { fold(toFit: bounds.width) }
        super.layout()
    }

    /// Shows the nearest ancestors that fit and folds the rest into "⋯n".
    private func fold(toFit width: CGFloat) {
        laidOutWidth = width
        // Their own widths: inside the stack their fitting sizes are what the stack gives them.
        let separatorWidth = (separators.first?.intrinsicContentSize.width ?? 0) + 2 * stack.spacing
        let overflowWidth = overflowWidth(folding: ancestors.count) + stack.spacing
        shownCount = AncestorFolding.shownCount(
            widths: buttons.map { $0.intrinsicContentSize.width + stack.spacing }, available: width,
            separator: separatorWidth, overflow: overflowWidth)
        let folded = ancestors.count - shownCount
        overflowButton.title = "⋯\(folded)"
        overflowButton.setAccessibilityLabel(localized("attributes.ancestors.more", folded))
        overflowButton.isHidden = folded == 0
        for (index, button) in buttons.enumerated() {
            button.isHidden = index < folded
            // No separator before the first shown, unless "⋯n" comes before it.
            separators[index].isHidden = index < folded || (index == folded && folded == 0)
        }
    }

    /// How wide "⋯n" is for `count` folded ancestors, the widest it gets.
    private func overflowWidth(folding count: Int) -> CGFloat {
        let title = "⋯\(count)" as NSString
        return ceil(title.size(withAttributes: [.font: Self.font]).width) + 8
    }

    @objc private func select(_ sender: AncestorButton) {
        onSelect(sender.ancestor.id)
    }

    /// The folded ancestors, farthest first, each with its icon. For tests too.
    func overflowMenu() -> NSMenu {
        let menu = NSMenu()
        for ancestor in ancestors.prefix(ancestors.count - shownCount) {
            let item = NSMenuItem(
                title: ancestor.title, action: #selector(selectFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ancestor.id
            item.image = LayerIconImage.image(ancestor.icon, side: Self.iconSide)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func showOverflow(_ sender: NSButton) {
        overflowMenu().popUp(
            positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc func selectFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UInt64 else { return }
        onSelect(id)
    }
}

/// One ancestor in the header's line: its icon and short name, plain until the pointer is on
/// it, then on a light fill; the pointer on it hovers its layer. Drawn by itself, as tight as
/// the design has it: a button's own insets left room for one ancestor fewer.
final class AncestorButton: NSButton {
    /// Before the icon, between it and the name, and after the name.
    static let insets = (leading: CGFloat(3), gap: CGFloat(4), trailing: CGFloat(6))

    let ancestor: LayerSummary.Ancestor
    var onHover: (UInt64?) -> Void = { _ in }

    private(set) var isHovered = false {
        didSet { needsDisplay = true }
    }

    private var trackingArea: NSTrackingArea?
    private let icon: NSImage

    init(_ ancestor: LayerSummary.Ancestor) {
        self.ancestor = ancestor
        icon = LayerIconImage.image(ancestor.icon, side: AncestorsBar.iconSide)
        super.init(frame: .zero)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        setAccessibilityLabel(ancestor.title)
        toolTip = ancestor.title
        setContentHuggingPriority(.required, for: .horizontal)
        // The nearest ancestor is cut short rather than overflow the line.
        setContentCompressionResistancePriority(.init(2), for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var text: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(
            string: ancestor.title,
            attributes: [
                .font: AncestorsBar.font,
                .foregroundColor: isEnabled ? NSColor.labelColor : .secondaryLabelColor,
                .paragraphStyle: paragraph,
            ])
    }

    override var intrinsicContentSize: NSSize {
        let insets = Self.insets
        return NSSize(
            width: insets.leading + AncestorsBar.iconSide + insets.gap + ceil(text.size().width)
                + insets.trailing,
            height: 20)
    }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointerEntered()
    }

    override func mouseExited(with event: NSEvent) {
        pointerExited()
    }

    /// The pointer came onto it: it hovers its layer. For tests too.
    func pointerEntered() {
        guard isEnabled else { return }
        isHovered = true
        onHover(ancestor.id)
    }

    /// The pointer left it. For tests too.
    func pointerExited() {
        guard isHovered else { return }
        isHovered = false
        onHover(nil)
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled { pointerExited() }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.quaternarySystemFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
            NSColor.separatorColor.setStroke()
            let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
            edge.lineWidth = 1
            edge.stroke()
        }
        let insets = Self.insets
        let side = AncestorsBar.iconSide
        icon.draw(in: NSRect(
            x: insets.leading, y: ((bounds.height - side) / 2).rounded(), width: side, height: side))
        let text = text
        let height = ceil(text.size().height)
        let x = insets.leading + side + insets.gap
        text.draw(with: NSRect(
            x: x, y: ((bounds.height - height) / 2).rounded(),
            width: max(bounds.width - x - insets.trailing, 0), height: height),
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
