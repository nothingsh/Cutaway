import CutawayWire

/// What a layer's icon says (C-HIER-11): the kind of thing it is, the glyph of its class, and
/// whether the class is the app's own or the system's. Taken from what the server says of the
/// classes (P-HIER-16, P-HIER-17), and worked out from class names when an older server says
/// nothing, so it can be wrong; it only picks an icon, and nothing shown as data depends on it.
public struct LayerIcon: Equatable, Hashable, Sendable {
    /// The kind, which the icon's colour shows.
    public enum Category: String, CaseIterable, Sendable {
        case window, controller, text, control, image, scroll, bar, content, container, layer
    }

    /// The class, which the icon's glyph shows. The raw value names its image.
    public enum Glyph: String, CaseIterable, Sendable {
        case window, view, label, textField, textView, button, toggle, slider, segmented
        case stepper, pageControl, picker, image, collection, table, scroll, cell
        case navigationBar, tabBar, searchBar, web, map, swiftUI, activity, progress, stack
        case effect, layer, shapeLayer, gradientLayer, textLayer
    }

    public var category: Category
    public var glyph: Glyph
    /// Whether the class is the app's own (filled) rather than the system's (outlined). For a
    /// controller's root view, the controller's class.
    public var isAppClass: Bool

    public init(_ category: Category, _ glyph: Glyph, isAppClass: Bool) {
        self.category = category
        self.glyph = glyph
        self.isAppClass = isAppClass
    }

    /// Ends of readable view class names, first match wins. A subclass usually keeps its
    /// superclass's ending (`CheckoutButton`), so it matches too. Cells come before the lists
    /// they are in: `UICollectionViewCell` is a cell.
    static let suffixes: [(suffix: String, category: Category, glyph: Glyph)] = [
        ("Window", .window, .window),
        ("Label", .text, .label),
        ("TextField", .text, .textField),
        ("TextView", .text, .textView),
        ("SegmentedControl", .control, .segmented),
        ("PageControl", .control, .pageControl),
        ("Stepper", .control, .stepper),
        ("DatePicker", .control, .picker),
        ("PickerView", .control, .picker),
        ("Button", .control, .button),
        ("Switch", .control, .toggle),
        ("Slider", .control, .slider),
        ("Control", .control, .button),
        ("ImageView", .image, .image),
        ("Cell", .scroll, .cell),
        ("ReusableView", .scroll, .cell),
        ("HeaderFooterView", .scroll, .cell),
        ("CollectionView", .scroll, .collection),
        ("TableView", .scroll, .table),
        ("ScrollView", .scroll, .scroll),
        ("NavigationBar", .bar, .navigationBar),
        ("TabBar", .bar, .tabBar),
        ("Toolbar", .bar, .tabBar),
        ("SearchBar", .bar, .searchBar),
        ("WebView", .content, .web),
        ("MapView", .content, .map),
        ("HostingView", .content, .swiftUI),
        ("ActivityIndicatorView", .content, .activity),
        ("ProgressView", .content, .progress),
        ("StackView", .container, .stack),
        ("EffectView", .container, .effect),
    ]

    /// Ends of layer class names, for a layer that backs no view.
    static let layerSuffixes: [(suffix: String, glyph: Glyph)] = [
        ("ShapeLayer", .shapeLayer), ("GradientLayer", .gradientLayer), ("TextLayer", .textLayer),
    ]

    /// The protocol's table of view classes (P-HIER-17). A name outside it is read as absent.
    /// Each has the category and glyph of its ending; `UIHostingView` is the name the protocol
    /// gives SwiftUI's hosting views.
    static let knownViewClasses: Set<String> = [
        "UIWindow", "UILabel", "UITextField", "UITextView", "UISegmentedControl", "UIPageControl",
        "UIStepper", "UIDatePicker", "UIPickerView", "UIButton", "UISwitch", "UISlider",
        "UIControl", "UIImageView", "UITableViewCell", "UICollectionViewCell",
        "UICollectionReusableView", "UITableViewHeaderFooterView", "UICollectionView",
        "UITableView", "UIScrollView", "UINavigationBar", "UITabBar", "UIToolbar", "UISearchBar",
        "WKWebView", "MKMapView", "UIActivityIndicatorView", "UIProgressView", "UIStackView",
        "UIVisualEffectView", "UIHostingView",
    ]

    /// The protocol's table of layer classes (P-HIER-17).
    static let knownLayerClasses: Set<String> = ["CAShapeLayer", "CAGradientLayer", "CATextLayer"]

    /// Prefixes of the system's class names. A two- or three-letter prefix counts only when a
    /// capital follows, so that `Avatar` or `CartView` are not taken for the system's.
    static let systemPrefixes = ["UI", "NS", "CA", "WK", "MK", "AV", "PK", "SK", "SCN", "MTK", "PH"]
    /// Modules of the system's Swift classes.
    static let systemModules: Set<Substring> = ["SwiftUI", "UIKit"]

    /// The icon of a layer: a window's root layer, a layer that backs no view, a controller's
    /// root view, or a view by the end of its readable class name.
    public init(_ node: LayerNode?) {
        guard let node else {
            self.init(.layer, .layer, isAppClass: false)
            return
        }
        let layerName = Self.first(node.className, node.displayClassName)
        let viewRuntime = Self.first(node.viewClassName, node.viewDisplayClassName)
        let viewReadable = Self.first(node.viewDisplayClassName, node.viewClassName)
        if node.parentID == 0 {
            let isApp = viewRuntime != nil
                ? Self.isAppClass(node.viewClassOrigin, viewRuntime)
                : Self.isAppClass(node.layerClassOrigin, layerName)
            self.init(.window, .window, isAppClass: isApp)
            return
        }
        guard let viewRuntime, let viewReadable else {
            let isApp = Self.isAppClass(node.layerClassOrigin, layerName)
            let glyph: Glyph
            if let known = node.layerBaseClassName.flatMap(Self.knownLayerClass) {
                glyph = known
            } else if node.layerClassOrigin != .unknown {
                // A server that gives origins gives base classes too: none is in the table.
                glyph = .layer
            } else {
                let base = Self.base(Self.first(node.displayClassName, node.className) ?? "")
                glyph = Self.layerSuffixes.first { base.hasSuffix($0.suffix) }?.glyph ?? .layer
            }
            self.init(.layer, glyph, isAppClass: isApp)
            return
        }
        let match: (suffix: String, category: Category, glyph: Glyph)?
        if let known = node.viewBaseClassName.flatMap(Self.knownViewClass) {
            match = known
        } else if node.viewClassOrigin != .unknown {
            match = nil
        } else {
            let base = Self.base(viewReadable)
            match = Self.suffixes.first { base.hasSuffix($0.suffix) }
        }
        let glyph = match?.glyph ?? .view
        if let controller = Self.first(node.viewControllerClassName, node.viewControllerDisplayClassName) {
            self.init(
                .controller, glyph,
                isAppClass: Self.isAppClass(node.viewControllerClassOrigin, controller))
        } else {
            self.init(
                match?.category ?? .container, glyph,
                isAppClass: Self.isAppClass(node.viewClassOrigin, viewRuntime))
        }
    }

    /// The ending a class of the protocol's view table has, or nil for a name outside it.
    static func knownViewClass(_ name: String) -> (suffix: String, category: Category, glyph: Glyph)? {
        guard knownViewClasses.contains(name) else { return nil }
        return suffixes.first { name.hasSuffix($0.suffix) }
    }

    /// The glyph of a class of the protocol's layer table, or nil for a name outside it.
    static func knownLayerClass(_ name: String) -> Glyph? {
        guard knownLayerClasses.contains(name) else { return nil }
        return layerSuffixes.first { name.hasSuffix($0.suffix) }?.glyph
    }

    /// The server's origin of a class, or without one a guess from its runtime name.
    static func isAppClass(_ origin: ClassOrigin, _ name: String?) -> Bool {
        switch origin {
        case .app: true
        case .system: false
        case .unknown: name.map(isAppClass) ?? false
        }
    }

    /// The icon of an attribute group (C-ATTR-17): a class of the system, outlined, known by
    /// the end of its name as a view is ("Scroll View" ends like `UIScrollView`); the Layer
    /// group is a plain layer, and a name that matches nothing a container. The title is the
    /// name, or the ID without one.
    public init(group title: String?, id: String?) {
        let name = [title, id.map { $0.prefix(1).uppercased() + $0.dropFirst() }]
            .compactMap { $0 }.first { !$0.isEmpty }?
            .replacingOccurrences(of: " ", with: "") ?? ""
        if name == "Layer" {
            self.init(.layer, .layer, isAppClass: false)
            return
        }
        let match = Self.suffixes.first { name.hasSuffix($0.suffix) }
        self.init(match?.category ?? .container, match?.glyph ?? .view, isAppClass: false)
    }

    /// The icon of the class that declares an attribute group's properties (C-ATTR-17,
    /// P-ATTR-16): a class of the protocol's tables by its ending, outlined as the system's;
    /// `CALayer` a plain layer; any other class a container.
    public init(groupClass name: String) {
        if let known = Self.knownViewClass(name) {
            self.init(known.category, known.glyph, isAppClass: false)
        } else if name == "CALayer" || Self.knownLayerClasses.contains(name) {
            self.init(.layer, Self.knownLayerClass(name) ?? .layer, isAppClass: false)
        } else {
            self.init(.container, .view, isAppClass: false)
        }
    }

    /// Whether a runtime class name is the app's own rather than the system's: anything that
    /// is not the system's by its prefix or, for a Swift class, by its module.
    public static func isAppClass(_ name: String) -> Bool {
        if let module = swiftModule(name) { return !systemModules.contains(module) }
        let name = name.drop { $0 == "_" }
        return !systemPrefixes.contains { prefix in
            guard name.hasPrefix(prefix) else { return false }
            return name.dropFirst(prefix.count).first?.isUppercase == true
        }
    }

    /// The module of a Swift class name, written out (`MyApp.FeedCell`) or mangled
    /// (`_TtC5MyApp8FeedCell`, `_TtGC7SwiftUI…`); nil for any other name.
    static func swiftModule(_ name: String) -> Substring? {
        if name.hasPrefix("_Tt") {
            var rest = name.dropFirst(3)
            if rest.first == "G" { rest = rest.dropFirst() }
            guard rest.first == "C" else { return nil }
            rest = rest.dropFirst()
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard let length = Int(digits) else { return nil }
            let module = rest.dropFirst(digits.count).prefix(length)
            return module.count == length ? module : nil
        }
        let base = base(name)
        guard let dot = base.firstIndex(of: "."), dot != base.startIndex else { return nil }
        return base[..<dot]
    }

    /// A class name without its generic arguments: they say nothing about what the view is.
    private static func base(_ name: String) -> Substring {
        name.split(separator: "<", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring(name)
    }

    private static func first(_ names: String?...) -> String? {
        names.compactMap { $0 }.first { !$0.isEmpty }
    }
}
