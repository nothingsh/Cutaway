import AppKit
import CutawayModel
import CutawayWire

/// The SF Symbol that stands for a layer in the list, the attribute panel's header and the
/// preview's readout. It only picks an icon: nothing shown as data depends on it.
enum LayerSymbol {
    static let window = "macwindow"
    static let view = "square"
    static let layer = "square.dashed"

    /// Ends of readable view class names and their symbols, first match wins. A custom
    /// subclass usually keeps its superclass's ending (`CheckoutButton`), so it matches too.
    static let suffixes: [(suffix: String, symbol: String)] = [
        ("Window", "macwindow"),
        ("Label", "textformat"),
        ("Button", "button.horizontal"),
        ("ImageView", "photo"),
        ("TextField", "character.cursor.ibeam"),
        ("TextView", "text.alignleft"),
        ("Cell", "rectangle.split.1x2"),
        ("TableView", "list.bullet.rectangle"),
        ("CollectionView", "square.grid.3x2"),
        ("ScrollView", "scroll"),
        ("StackView", "square.stack"),
        ("NavigationBar", "menubar.rectangle"),
        ("TabBar", "dock.rectangle"),
        ("Switch", "switch.2"),
        ("Slider", "slider.horizontal.3"),
        ("WebView", "globe"),
        ("MapView", "map"),
        ("EffectView", "drop.halffull"),
        ("HostingView", "swift"),
    ]

    /// Every symbol this type can return. A misspelt name makes no image, so a test loads each.
    static var all: [String] { [window, view, layer] + suffixes.map(\.symbol) }

    /// The symbol of a layer: a window's root layer, a layer that backs no view, or a view by
    /// the end of its readable class name.
    static func name(for node: LayerNode?) -> String {
        guard let node else { return layer }
        if node.parentID == 0 { return window }
        let viewName = [node.viewDisplayClassName, node.viewClassName]
            .compactMap { $0 }.first { !$0.isEmpty }
        guard let viewName else { return layer }
        return name(forViewClass: viewName)
    }

    /// The symbol of a view by its class name; `square` when no ending matches.
    static func name(forViewClass className: String) -> String {
        // "_UIHostingView<ContentView>" ends with its generic arguments; they say nothing
        // about what the view is.
        let base = className.split(separator: "<", maxSplits: 1).first.map(String.init)
            ?? className
        return suffixes.first { base.hasSuffix($0.suffix) }?.symbol ?? view
    }

    @MainActor
    static func image(for node: LayerNode?, size: CGFloat = 13) -> NSImage? {
        Theme.symbol(name(for: node), size: size)
    }
}
