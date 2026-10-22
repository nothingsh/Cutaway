import AppKit
import DeclarativeAppKit

/// How the attribute panel looks, apart from its layout: its backdrop, the lines between its
/// sections, and each section's title and symbol.
extension AttributesViewController {
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

    /// The title of a section named by what it is for; Content has its group's.
    static func title(of kind: AttributesViewModel.Listing.Kind) -> String {
        switch kind {
        case .content: localized("attributes.section.content")
        case .app: localized("attributes.section.app")
        case .appearance: localized("attributes.section.appearance")
        case .layout: localized("attributes.section.layout")
        case .behavior: localized("attributes.section.behavior")
        case .accessibility: localized("attributes.section.accessibility")
        case .object: localized("attributes.section.object")
        }
    }

    /// The symbol before a section's title (C-ATTR-17); nil for Content, which has its class's.
    static func symbol(of kind: AttributesViewModel.Listing.Kind) -> String? {
        switch kind {
        case .content: nil
        case .app: "app.badge"
        case .appearance: "circle.lefthalf.filled"
        case .layout: "ruler"
        case .behavior: "hand.point.up.left"
        case .accessibility: "accessibility"
        case .object: "tag"
        }
    }
}
