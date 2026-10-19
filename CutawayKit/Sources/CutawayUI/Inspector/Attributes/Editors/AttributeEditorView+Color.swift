import AppKit
import CutawayModel
import CutawayWire
import DeclarativeAppKit

/// The colour field of an attribute editor (C-ATTR-05, C-ATTR-07, C-ATTR-22).
extension AttributeEditorView {
    /// One field (C-ATTR-22): the swatch, which opens the colour panel, the hexadecimal code,
    /// which can be typed, and the opacity in percent. A colour with a name, from the app's
    /// asset catalog or UIKit (C-SRC-04), shows it instead of the code and the opacity, and the
    /// other names and the code in the tooltip; typing shows the code again.
    func colorContent() -> NSView {
        let well = NSColorWell(style: .default)
            .accessibilityIdentifier(Self.wellIdentifier)
            .accessibilityLabel(title)
            .configure {
                $0.isContinuous = true
                $0.target = self
                $0.action = #selector(colorChanged(_:))
            }
        colorWell = well
        let swatch = ColorSwatch(color: nil, well: well)
        swatch.widthAnchor.constraint(equalToConstant: ColorSwatch.side).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: ColorSwatch.side).isActive = true
        let hex = AttributeEditField()
            .accessibilityIdentifier(Self.hexIdentifier)
            .accessibilityLabel(localized("attributes.editor.hexadecimal", title))
        let alpha = NSTextField(labelWithString: "")
            .font(.monospacedDigitSystemFont(ofSize: 11, weight: .regular))
            .textColor(.tertiaryLabelColor)
            .accessibilityIdentifier(Self.alphaIdentifier)
        alpha.setContentHuggingPriority(.required, for: .horizontal)
        alpha.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        let badge = makeBadge()
        hex.onCommit = { [weak self, weak hex] text, _ in
            guard let self, let hex else { return .accepted }
            self.activeBadge = badge
            self.commitHex(text, in: hex)
            return .accepted
        }
        // The code of the colour shown, for typing over a system colour's name.
        var code = ""
        var name: String?
        // The opacity shows for a code.
        var showsAlpha = false
        let applyAlpha = { alpha.isHidden = !showsAlpha }
        // A code is in a monospaced font; a system colour's name is a name.
        let applyFont = { [weak hex] in
            hex?.font = name == nil || hex?.hasFocus == true
                ? .monospacedSystemFont(ofSize: 11.5, weight: .regular) : .systemFont(ofSize: 12)
        }

        hex.onFocus = { [weak hex] focused in
            guard let hex, name != nil else { return }
            hex.shownText = focused ? code : name ?? code
            applyFont()
        }
        showValue = { [weak self, weak hex] value in
            guard let hex else { return }
            // No colour and transparent black show alike: a transparent well, and "None".
            guard case .color(let color) = value, color != Self.transparent else {
                well.color = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
                swatch.color = nil
                name = nil
                code = ""
                showsAlpha = false
                applyAlpha()
                applyFont()
                hex.toolTip = nil
                return hex.shownText = ""
            }
            well.color = NSColor(
                colorSpace: .extendedSRGB,
                components: [color.red, color.green, color.blue, color.alpha].map { CGFloat($0) },
                count: 4)
            swatch.color = well.color
            // A colour beyond sRGB has no hex code; its components are shown instead.
            let rgb = AttributeText.hexRGB(of: color).map { String($0.dropFirst()) }
            code = rgb ?? AttributeText.text(of: value)
            let names = self?.names ?? .none
            name = names.colorName
            alpha.stringValue = AttributeText.percent(Double(color.alpha)) + "%"
            showsAlpha = rgb != nil && name == nil
            applyAlpha()
            applyFont()
            hex.toolTip = name == nil ? nil : (names.colorNotes + ["#" + code]).joined(separator: " · ")
            hex.shownText = hex.hasFocus ? code : name ?? code
        }
        editing = { [weak self] in hex.isTyping || self?.colorPause != nil }
        return Self.colorBox([swatch, hex, alpha], badge: badge)
    }

    /// The colour field's box: the swatch, the code, the opacity and "no effect" in a line,
    /// and the badge floating at its end.
    private static func colorBox(_ views: [NSView], badge: EditBadge) -> NSView {
        let box = fieldBox()
        box.contentView?.addHStack(alignment: .center, spacing: 6) {
            for view in views { view }
        }
        .padding(horizontal: 6, vertical: 0)
        return box
            .frame(height: fieldHeight)
            .overlay(alignment: .trailing, offset: CGPoint(x: -4, y: 0)) { badge }
    }

    /// Sends a typed code. An emptied field clears the colour to transparent: the panel's "no
    /// colour" swatch has no public switch. A colour that is nil stays nil (C-ATTR-05). A code
    /// that does not read goes back without a word, as before (C-ATTR-13 is about numbers).
    /// Six digits keep the opacity shown beside them.
    private func commitHex(_ text: String, in hex: AttributeEditField) {
        let cleared = text.trimmingCharacters(in: .whitespaces).isEmpty
        if cleared, value == nil {
            hex.revert()
            return
        }
        var opacity: Float?
        if case .color(let current) = value { opacity = current.alpha }
        guard let color = cleared
            ? Self.transparent : AttributeValueEditing.color(fromHex: text, keepingAlpha: opacity),
            value != .color(color)
        else {
            hex.revert()
            return
        }
        onSet(.color(color), false)
        // The code as the field writes it, not as it was typed: the value on its way was
        // shown while the field still counted as typed in.
        hex.revert()
    }

    /// The colour well or its panel moves: sent as it goes, and finished once it is still a
    /// moment (C-ATTR-07, C-ATTR-08).
    @objc func colorChanged(_ sender: NSColorWell) {
        (sender.superview as? ColorSwatch)?.color = sender.color
        guard !hasLeftWindow, let color = Self.color(of: sender.color) else { return }
        activeBadge = badges.first
        onSet(.color(color), true)
        colorPause?.cancel()
        // The change ends even when this editor is gone by then (another layer was selected):
        // a change left open would show as sending, and record no undo.
        let finish = onFinish
        let work = DispatchWorkItem { [weak self] in
            self?.colorPause = nil
            finish()
        }
        colorPause = work
        DispatchQueue.main.asyncAfter(deadline: .now() + colorPauseDelay, execute: work)
    }

    /// A colour as sent: sRGB, not premultiplied (P-ATTR-04). Components outside 0 to 1 go
    /// as they are; the app clamps them.
    static func color(of color: NSColor) -> Color? {
        guard let srgb = color.usingColorSpace(.extendedSRGB) else { return nil }
        return Color(
            red: Float(srgb.redComponent), green: Float(srgb.greenComponent),
            blue: Float(srgb.blueComponent), alpha: Float(srgb.alphaComponent))
    }
}
