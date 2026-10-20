import AppKit
import DeclarativeAppKit

/// The constraints of the attribute panel (C-LAYOUT-02), at the end of the Layout section and
/// folded with it: a heading that says how many there are, then one row to a constraint, in
/// the server's order. The constraints UIKit made are folded into one last row that opens to list them.
/// The other ends are chips that hover and select their layers (C-LAYOUT-03, C-LAYOUT-06).
/// Pointing at a row, or at the folded UIKit ones, marks their other ends (C-LAYOUT-07).
final class ConstraintsSectionView: NSView {
    static let headerIdentifier = "constraints.header"
    static let emptyIdentifier = "constraints.empty"
    static let generatedIdentifier = "constraints.generated"

    let list: ConstraintList
    /// The rows of the app's constraints, then those of UIKit's.
    let rows: [ConstraintRowView]
    var onToggleGenerated: (Bool) -> Void = { _ in }
    private(set) var showsGenerated: Bool {
        didSet { apply() }
    }

    /// The heading: the constraints' icon, "Constraints" and how many.
    private(set) lazy var header = NSTextField(labelWithString: "")

    private(set) lazy var generatedButton: NSButton = .init().configure {
        $0.isBordered = false
        $0.imageHugsTitle = true
        // The class names after the count are cut short rather than widen the inspector.
        ($0.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        $0.target = self
        $0.action = #selector(toggleGenerated(_:))
    }

    /// The row that folds UIKit's constraints away; pointing at it points at all of them.
    private(set) var generatedBox: PointingBox?

    private let body: VStack
    private let generatedRows: VStack

    init(
        rows: [ConstraintRow], showsGenerated: Bool,
        onShowLayer: @escaping (UInt64) -> Void,
        onHoverEnd: @escaping (ConstraintRow.End?) -> Void = { _ in },
        onPoint: @escaping (ConstraintPointer) -> Void = { _ in }
    ) {
        let list = ConstraintList(rows)
        self.list = list
        self.showsGenerated = showsGenerated
        let generated = list.generated
        let ownRows = list.own.map {
            ConstraintRowView($0, showsClass: false, onShowLayer: onShowLayer, onHoverEnd: onHoverEnd)
        }
        let generatedRowViews = generated.map {
            ConstraintRowView($0, showsClass: true, onShowLayer: onShowLayer, onHoverEnd: onHoverEnd)
        }
        self.rows = ownRows + generatedRowViews
        for row in self.rows {
            row.onPoint = onPoint
        }
        let generatedIndices = generated.map(\.index)
        generatedRows = VStack(alignment: .fill, spacing: 0) { generatedRowViews }
            .padding(top: 0, leading: Theme.Spacing.medium, bottom: 0, trailing: 0)
        body = VStack(alignment: .fill, spacing: 0) {}
        super.init(frame: .zero)

        body.addContent(VStack(alignment: .fill, spacing: 0) {
            ownRows
            if !generated.isEmpty {
                VStack(alignment: .fill) {
                    PointingBox().configure {
                        $0.boxType = .custom
                        $0.borderWidth = 0
                        $0.cornerRadius = Theme.Radius.control
                        $0.fillColor = .quaternarySystemFill
                        $0.titlePosition = .noTitle
                        $0.contentViewMargins = NSSize(width: 6, height: 3)
                        generatedBox = $0
                        $0.onHover = { inside in
                            onPoint(inside
                                ? .entered(generatedIndices, stresses: false)
                                : .left(generatedIndices))
                        }
                        $0.contentView?.addContent(HStack(alignment: .center) {
                            generatedButton
                                .buttonType(.momentaryChange)
                                .imagePosition(.imageLeading)
                                .alignment(.left)
                                .contentTintColor(.secondaryLabelColor)
                                .compressionResistancePriority(
                                    Theme.textGivesWay, for: .horizontal)
                                .accessibilityIdentifier(Self.generatedIdentifier)
                            Spacer()
                        })
                    }
                }
                .padding(top: 4, leading: Theme.Spacing.large - 6, bottom: 2,
                         trailing: Theme.Spacing.large - 6)
                generatedRows
            }
            if rows.isEmpty {
                VStack(alignment: .leading) {
                    NSTextField(labelWithString: localized("constraints.empty"))
                        .font(Theme.Font.caption)
                        .textColor(.tertiaryLabelColor)
                        .accessibilityIdentifier(Self.emptyIdentifier)
                }
                .padding(horizontal: Theme.Spacing.large + 4, vertical: 2)
            }
        })
        addVStack(alignment: .fill, spacing: 2) {
            VStack(alignment: .fill) {
                header
                    .lineBreakMode(.byTruncatingTail)
                    .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                    .accessibilityIdentifier(Self.headerIdentifier)
            }
            .padding(top: 8, leading: Theme.Spacing.large, bottom: 2, trailing: Theme.Spacing.large)
            body
        }
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The heading's title, which a filter matches (C-ATTR-14).
    var title: String { localized("constraints.header") }

    /// The heading as shown, without the icon.
    var headerText: String {
        header.attributedStringValue.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    // MARK: - The pointer

    /// One tracking area for the whole section, which works out the row under the pointer
    /// from where the pointer is. Each row tracking its own missed the pointer leaving when
    /// the list scrolled under it: rows stayed filled and their ends marked (reported by the
    /// user, 2026-10-20).
    private var trackingArea: NSTrackingArea?
    /// While the list scrolls, nothing is pointed at (`pauseForScrolling()`).
    private var isScrolling = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        pointerMoved(to: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        pointerMoved(to: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        point(at: nil)
    }

    /// The pointer is at a point in the window: the row under it is pointed at, and only it.
    func pointerMoved(to point: NSPoint) {
        guard !isScrolling else { return }
        let local = convert(point, from: nil)
        var target: NSView?
        if visibleRect.contains(local) {
            target = rows.first { row in
                !row.isHiddenOrHasHiddenAncestor && row.convert(row.bounds, to: self).contains(local)
            }
            if target == nil, let box = generatedBox, box.convert(box.bounds, to: self).contains(local) {
                target = box
            }
        }
        self.point(at: target)
    }

    /// Points at a row or the folded UIKit box, or at nothing; whatever was pointed at is
    /// left first, so that the marks of one row go before the next row's come.
    private func point(at target: NSView?) {
        for row in rows where row !== target && row.isHovered { row.point(false) }
        if let box = generatedBox, box !== target, box.isHovered { box.point(false) }
        (target as? ConstraintRowView)?.point(true)
        (target as? PointingBox)?.point(true)
    }

    /// The list began to scroll: nothing is pointed at, neither a row nor a chip, until it
    /// stops (`pointerMayHaveMoved()`). Rows passing under the pointer mark nothing.
    func pauseForScrolling() {
        isScrolling = true
        point(at: nil)
        for row in rows { row.equationView.point(at: nil) }
    }

    /// The list stopped scrolling, or its rows moved: the row under the pointer, if any, is
    /// pointed at.
    func pointerMayHaveMoved() {
        isScrolling = false
        guard let window else { return }
        pointerMoved(to: window.mouseLocationOutsideOfEventStream)
    }

    @objc func toggleGenerated(_ sender: Any?) {
        showsGenerated.toggle()
        onToggleGenerated(showsGenerated)
    }

    private func apply() {
        // The icon in the colour of the marks on the preview (C-ATTR-17), like a section's.
        let heading = NSMutableAttributedString()
        let icon = NSTextAttachment()
        let side: CGFloat = 12
        icon.image = ConstraintIconImage.section(side: side)
        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        icon.bounds = NSRect(x: 0, y: ((font.capHeight - side) / 2).rounded(), width: side, height: side)
        heading.append(NSAttributedString(attachment: icon))
        heading.append(NSAttributedString(
            string: " " + title, attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
        if !list.rows.isEmpty {
            heading.append(NSAttributedString(
                string: "  \(list.count)",
                attributes: [.font: Theme.Font.captionDigits, .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        header.attributedStringValue = heading
        header.setAccessibilityLabel(title)

        generatedRows.isHidden = !showsGenerated
        generatedButton.image = Theme.symbol(
            showsGenerated ? "chevron.down" : "chevron.right", size: 9, weight: .bold)
        let label = localized("constraints.generated", list.generatedCount)
        let generatedTitle = NSMutableAttributedString(
            string: " " + label,
            attributes: [.font: Theme.Font.caption, .foregroundColor: NSColor.labelColor])
        if let generatedSummary = list.generatedSummary, !showsGenerated {
            generatedTitle.append(NSAttributedString(
                string: "  " + generatedSummary,
                attributes: [
                    .font: Theme.Font.caption, .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
        }
        generatedButton.attributedTitle = generatedTitle
        generatedButton.setAccessibilityLabel(label)
        generatedButton.setAccessibilityValue(
            showsGenerated ? localized("disclosure.expanded") : localized("disclosure.collapsed"))
    }
}

/// A box that says when the pointer comes onto it and leaves it; the section says where the
/// pointer is.
final class PointingBox: NSBox {
    var onHover: (Bool) -> Void = { _ in }
    private(set) var isHovered = false {
        didSet {
            if isHovered != oldValue { onHover(isHovered) }
        }
    }

    /// Puts the pointer on the box, or off it.
    func point(_ inside: Bool) {
        isHovered = inside
    }
}
