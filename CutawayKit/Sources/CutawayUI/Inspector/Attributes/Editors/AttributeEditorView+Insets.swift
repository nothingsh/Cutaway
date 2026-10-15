import AppKit
import CutawayModel
import CutawayWire
import DeclarativeAppKit

/// The insets box of an attribute editor (C-ATTR-22).
extension AttributeEditorView {
    /// A box with a number on each side (C-ATTR-22): top and bottom in the middle, left and
    /// right at the sides, and the layer's size in a dashed frame in between. Each number is
    /// typed as any other (C-ATTR-05, C-ATTR-13); a read-only box is faint.
    func insetsContent() -> NSView {
        let names = (0..<4).map { LimitText.componentName(.insets, $0) ?? "" }
        let numbers = names.map {
            NumberFieldView(
                letter: nil, isInteger: false, name: localized("attributes.editor.component", title, $0),
                unit: unit, showsUnit: false)
        }
        tallness = { true }
        // The numbers have no boxes of their own: the box is theirs (as in the design).
        for number in numbers { number.makeBare() }
        bindComponents(numbers, zeros: 4) { AttributeValueEditing.value(.insets, $0) }
        let size = NSTextField(labelWithString: "")
            .font(.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular))
            .textColor(.tertiaryLabelColor)
            .alignment(.center)
            .accessibilityIdentifier(Self.insetsSizeIdentifier)
        showLayerSize = { size.stringValue = $0 ?? "" }
        let dash = DashedFrame()
        let box = Self.fieldBox()
        let content = NSView()
        box.contentView?.addContent(content)
        let (top, left, bottom, right) = (numbers[0], numbers[1], numbers[2], numbers[3])
        for view in [top, left, bottom, right, dash, size] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        // As in the design: a band of a field's height above and below, a column 44 points
        // wide at each side, and the dashed frame in between.
        let column: CGFloat = 44
        let band = Self.fieldHeight
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor),
            top.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            top.widthAnchor.constraint(equalToConstant: column + 8),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bottom.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            bottom.widthAnchor.constraint(equalToConstant: column + 8),
            left.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            left.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            left.widthAnchor.constraint(equalToConstant: column),
            right.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            right.widthAnchor.constraint(equalToConstant: column),
            dash.topAnchor.constraint(equalTo: content.topAnchor, constant: band),
            dash.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -band),
            dash.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: column),
            dash.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -column),
            size.centerXAnchor.constraint(equalTo: dash.centerXAnchor),
            size.centerYAnchor.constraint(equalTo: dash.centerYAnchor),
            size.widthAnchor.constraint(lessThanOrEqualTo: dash.widthAnchor),
        ])
        if isReadOnly { box.alphaValue = 0.6 }
        return box
            .frame(height: 74)
            .accessibilityIdentifier(Self.insetsIdentifier)
    }
}

/// The dashed frame in the middle of an insets box, where the layer is.
private final class DashedFrame: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        path.lineWidth = 1
        path.setLineDash([3, 2], count: 2, phase: 0)
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }
}
