import AppKit
import DeclarativeAppKit

/// What the attribute panel names and draws, and what it does with the pasteboard, apart from
/// the panel itself.
extension AttributesViewController {
    /// Puts text on the general pasteboard: what the address buttons do outside tests.
    static func copyToPasteboard(_ text: String) {
        copy(text, to: .general)
    }

    static func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// A line between two sections.
    static func separator() -> NSView {
        VStack(alignment: .fill) {
            NSBox().configure { $0.boxType = .separator }
        }
    }

    /// The panel's backdrop, and the header's that stays at the top over the list: the
    /// window's own material, so that the panel looks as the window does, and the same view
    /// for both, so that they look alike over any desktop and in any state of the window.
    static func backdrop() -> NSVisualEffectView {
        NSVisualEffectView().configure {
            $0.material = .windowBackground
            $0.blendingMode = .behindWindow
            $0.state = .followsWindowActiveState
        }
    }

    /// The filter as the design draws it: a field 24 points tall with the fields' fill and
    /// hairline and corners of 6 points, the system's search field without its own bezel
    /// inside, so that typing, Esc and the clear button work as before (C-ATTR-14).
    static func filterBox(around field: NSSearchField) -> NSView {
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.controlSize = .small
        field.font = .systemFont(ofSize: 12)
        // The design's magnifier is 11 points, in the secondary colour.
        if let search = (field.cell as? NSSearchFieldCell)?.searchButtonCell {
            search.image = Theme.symbol("magnifyingglass", size: 11, weight: .medium)
            search.image?.isTemplate = true
        }
        let box = AttributeEditorView.fieldBox()
        box.cornerRadius = 6
        box.contentView?.addVStack(alignment: .fill) {
            Spacer()
            field
            Spacer()
        }
        .padding(horizontal: 2, vertical: 0)
        return box.frame(height: 24)
    }

    /// Every symbol the panel's messages use. A misspelt name makes no image.
    static var symbols: [String] {
        ["cursorarrow.click.2", "questionmark.square.dashed", "moon.zzz",
         "exclamationmark.triangle", "checkmark.circle.fill", "circle", "chevron.right",
         "chevron.down", "chevron.up.chevron.down", "magnifyingglass", "eye", "eye.slash", IdentityLinesView.copySymbol]
            + AttributesViewModel.Listing.Kind.allCases.compactMap(symbol(of:))
            + ConstraintRowView.symbols
    }

    /// The title of a section named by what it is for; Content has its group's.
    static func title(of kind: AttributesViewModel.Listing.Kind) -> String {
        switch kind {
        case .content: localized("attributes.section.content")
        case .appearance: localized("attributes.section.appearance")
        case .layout: localized("attributes.section.layout")
        case .behavior: localized("attributes.section.behavior")
        case .object: localized("attributes.section.object")
        }
    }

    /// The symbol before a section's title (C-ATTR-17); nil for Content, which has its class's.
    static func symbol(of kind: AttributesViewModel.Listing.Kind) -> String? {
        switch kind {
        case .content: nil
        case .appearance: "circle.lefthalf.filled"
        case .layout: "ruler"
        case .behavior: "hand.point.up.left"
        case .object: "tag"
        }
    }
}
