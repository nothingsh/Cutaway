import AppKit
import CutawayModel

/// The preview's control for its borders (C-PREV-17): a pull-down whose face is four small
/// squares in kind colours, grey while the borders are off, with Off, Plain and By Kind, Only
/// the App's Own Classes, and Constraint Ends (C-PREV-18). Each item holds what it sets.
@MainActor
enum BordersButton {
    /// What an item of the menu sets.
    enum Choice: Equatable {
        case style(BorderStyle)
        case onlyAppClasses
        case constraintEnds
    }

    /// The kinds whose colours the face shows, left to right and top to bottom.
    static let faceKinds: [LayerIcon.Category] = [.text, .control, .scroll, .controller]

    /// A pull-down button with the items, laid out by the caller.
    static func make() -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        button.addItem(withTitle: "")
        guard let menu = button.menu else { return button }
        for style in BorderStyle.allCases {
            let item = NSMenuItem(title: title(of: style), action: nil, keyEquivalent: "")
            item.representedObject = Box(Choice.style(style))
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let only = NSMenuItem(
            title: localized("preview.borders.onlyAppClasses"), action: nil, keyEquivalent: "")
        only.representedObject = Box(Choice.onlyAppClasses)
        menu.addItem(only)
        menu.addItem(.separator())
        let ends = NSMenuItem(
            title: localized("preview.borders.constraintEnds"), action: nil, keyEquivalent: "")
        ends.representedObject = Box(Choice.constraintEnds)
        menu.addItem(ends)
        return button
    }

    /// A style's name, as the menus and the settings say it.
    static func title(of style: BorderStyle) -> String {
        switch style {
        case .off: localized("preview.borders.off")
        case .plain: localized("preview.borders.plain")
        case .byKind: localized("preview.borders.byKind")
        }
    }

    /// What the item at `index` sets; nil for the face and the separator.
    static func choice(of button: NSPopUpButton, at index: Int) -> Choice? {
        (button.item(at: index)?.representedObject as? Box)?.choice
    }

    /// Checks the style shown, Only the App's Own Classes and Constraint Ends, and draws the
    /// face for the borders.
    static func show(
        _ options: BorderOptions, showsConstraintEnds: Bool, on button: NSPopUpButton
    ) {
        for item in button.itemArray {
            guard let choice = (item.representedObject as? Box)?.choice else { continue }
            let on = switch choice {
            case .style(let style): style == options.style
            case .onlyAppClasses: options.onlyAppClasses
            case .constraintEnds: showsConstraintEnds
            }
            item.state = on ? .on : .off
        }
        button.item(at: 0)?.image = face(on: options.showsBorders)
        button.toolTip = localized("preview.borders.tooltip")
    }

    /// Sets what the item at `index` says on the store.
    static func choose(_ index: Int, of button: NSPopUpButton, in store: InspectionStore) {
        switch choice(of: button, at: index) {
        case .style(let style): store.setBorderStyle(style)
        case .onlyAppClasses: store.setOnlyAppClasses(!store.borders.onlyAppClasses)
        case .constraintEnds: store.toggleConstraintEnds()
        case nil: break
        }
    }

    /// Four 5-point squares, 2 points apart, in the kinds' colours, or grey when `on` is false.
    static func face(on: Bool) -> NSImage {
        let side: CGFloat = 5, gap: CGFloat = 2
        let image = NSImage(size: NSSize(width: 2 * side + gap, height: 2 * side + gap), flipped: true) { _ in
            for (index, kind) in faceKinds.enumerated() {
                let rect = NSRect(
                    x: CGFloat(index % 2) * (side + gap), y: CGFloat(index / 2) * (side + gap),
                    width: side, height: side)
                (on ? LayerIconImage.color(kind) : NSColor.tertiaryLabelColor).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.accessibilityDescription = localized("preview.borders.tooltip")
        return image
    }

    /// A choice as a menu item's represented object.
    private final class Box: NSObject {
        let choice: Choice

        init(_ choice: Choice) {
            self.choice = choice
        }
    }
}
