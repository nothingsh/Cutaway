import AppKit
import CutawayModel
import CutawayWire

// View › Environment (C-MENU-05): the items' actions and their checks. The toolbar's button is
// `EnvironmentToolbarController`'s.
extension InspectorWindowController {
    /// The tag of the menu item that chooses `value` for `kind`.
    static func environmentTag(_ kind: TraitKind, _ value: Traits.Value) -> Int {
        let kindIndex = TraitKind.allCases.firstIndex(of: kind) ?? 0
        let valueIndex = EnvironmentNames.choices(of: kind).firstIndex(of: value) ?? 0
        return kindIndex * 100 + valueIndex
    }

    /// The kind and value a menu item's tag stands for.
    static func environmentChoice(of tag: Int) -> (TraitKind, Traits.Value)? {
        let kinds = TraitKind.allCases
        guard tag >= 0, kinds.indices.contains(tag / 100) else { return nil }
        let kind = kinds[tag / 100]
        let choices = EnvironmentNames.choices(of: kind)
        guard choices.indices.contains(tag % 100) else { return nil }
        return (kind, choices[tag % 100])
    }

    @objc func chooseEnvironmentValue(_ sender: NSMenuItem) {
        guard let (kind, value) = Self.environmentChoice(of: sender.tag) else { return }
        store.setEnvironment(kind, to: value)
    }

    @objc func resetEnvironment(_ sender: Any?) {
        store.resetEnvironment()
    }

    @objc func toggleAppearance(_ sender: Any?) {
        store.toggleAppearance()
    }

    /// Whether an item of View › Environment can be used; a value's item is ticked when it is
    /// the one shown.
    func validateEnvironmentItem(_ item: NSMenuItem) -> Bool {
        guard store.canChangeEnvironment, let controls = store.environment.controls
        else {
            item.state = .off
            return false
        }
        switch item.action {
        case #selector(chooseEnvironmentValue(_:)):
            guard let (kind, value) = Self.environmentChoice(of: item.tag) else { return false }
            item.state = controls.shown[kind] == value ? .on : .off
            return controls.overridable.contains(kind)
        case #selector(toggleAppearance(_:)):
            return controls.overridable.contains(.userInterfaceStyle)
        case #selector(resetEnvironment(_:)):
            return controls.isOverriding
        default:
            return false
        }
    }
}
