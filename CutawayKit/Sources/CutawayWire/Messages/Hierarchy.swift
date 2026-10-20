// MARK: - Hierarchy

/// An instance variable that holds a layer, or the view the layer backs (P-HIER-08,
/// P-HIER-09). Protocol 0.2.
public struct MemberReference: Equatable, Sendable {
    /// The runtime name of the class that declares the variable.
    public var ownerClassName: String?
    public var ownerDisplayClassName: String?
    /// The variable's name as declared.
    public var name: String?

    public init(ownerClassName: String?, ownerDisplayClassName: String?, name: String?) {
        self.ownerClassName = ownerClassName
        self.ownerDisplayClassName = ownerDisplayClassName
        self.name = name
    }
}

/// Where a class, or a constraint, comes from (P-HIER-16, P-LAYOUT-09). Protocol 1.1.
/// `unknown` means absent, as from an older server, and stands for values this client does
/// not know.
public enum ClassOrigin: Equatable, Sendable {
    case unknown, system, app
}

/// Whether a view controller is on show (P-HIER-18). Protocol 1.1. `unknown` means absent.
public enum ViewControllerVisibility: Equatable, Sendable {
    case unknown, shown, notShown
}

/// What a hierarchy node stands for (P-HIER-19). Protocol 1.2. `layer` when absent, as from an
/// older server, and for values this client does not know.
public enum NodeKind: Equatable, Sendable {
    /// A layer of the app.
    case layer
    /// A part of the interface the host app draws inside a layer and describes (P-HIER-20).
    case virtual
}

public struct LayerNode: Equatable, Sendable {
    public var id: UInt64
    /// 0 for a window's root layer.
    public var parentID: UInt64
    public var className: String?
    public var displayClassName: String?
    /// Set when the layer backs a view.
    public var viewClassName: String?
    public var viewDisplayClassName: String?
    public var bounds: Rect?
    public var position: Point?
    public var anchorPoint: Point?
    public var transform: Transform3D?
    public var zPosition: Double
    public var isHidden: Bool
    public var opacity: Float
    public var masksToBounds: Bool
    /// Set when the layer backs a view controller's root view (P-HIER-07). Protocol 0.2.
    public var viewControllerClassName: String?
    public var viewControllerDisplayClassName: String?
    /// Nearest holder first; empty when there are none or the server sends none (P-HIER-08).
    /// Protocol 0.2.
    public var memberReferences: [MemberReference]
    /// The addresses of the layer, of the view it backs and of the view controller, in the
    /// app's process when the hierarchy was captured (P-HIER-14); nil when absent, as from a
    /// 1.0 server. For display only: an address is not an identity (P-HIER-15). Protocol 1.1.
    public var layerAddress: UInt64?
    public var viewAddress: UInt64?
    public var viewControllerAddress: UInt64?
    /// Where the classes of `className`, `viewClassName` and `viewControllerClassName` come
    /// from (P-HIER-16). Protocol 1.1.
    public var layerClassOrigin: ClassOrigin
    public var viewClassOrigin: ClassOrigin
    public var viewControllerClassOrigin: ClassOrigin
    /// The nearest class of the layer, and of its view, in the protocol's tables (P-HIER-17);
    /// nil when absent. Not checked against the tables here: a name this client does not know
    /// is for the reader to ignore. Protocol 1.1.
    public var layerBaseClassName: String?
    public var viewBaseClassName: String?
    /// Whether the view controller is on show (P-HIER-18). Protocol 1.1.
    public var viewControllerVisibility: ViewControllerVisibility
    /// Protocol 1.2 (P-HIER-19).
    public var kind: NodeKind
    /// The short label the host app gives a virtual node (P-HIER-20); nil otherwise. Protocol 1.2.
    public var name: String?
    /// The host app asks that the node start collapsed (P-HIER-23). Protocol 1.2.
    public var isCollapsedByDefault: Bool
    /// The host app excludes the node, with its subtree, from images (P-DET-10). Protocol 1.2.
    public var isCaptureExcluded: Bool

    public init(
        id: UInt64, parentID: UInt64, className: String?, displayClassName: String?,
        viewClassName: String?, viewDisplayClassName: String?, bounds: Rect?, position: Point?,
        anchorPoint: Point?, transform: Transform3D?, zPosition: Double, isHidden: Bool,
        opacity: Float, masksToBounds: Bool, viewControllerClassName: String? = nil,
        viewControllerDisplayClassName: String? = nil, memberReferences: [MemberReference] = [],
        layerAddress: UInt64? = nil, viewAddress: UInt64? = nil,
        viewControllerAddress: UInt64? = nil, layerClassOrigin: ClassOrigin = .unknown,
        viewClassOrigin: ClassOrigin = .unknown, viewControllerClassOrigin: ClassOrigin = .unknown,
        layerBaseClassName: String? = nil, viewBaseClassName: String? = nil,
        viewControllerVisibility: ViewControllerVisibility = .unknown, kind: NodeKind = .layer,
        name: String? = nil, isCollapsedByDefault: Bool = false, isCaptureExcluded: Bool = false
    ) {
        self.id = id
        self.parentID = parentID
        self.className = className
        self.displayClassName = displayClassName
        self.viewClassName = viewClassName
        self.viewDisplayClassName = viewDisplayClassName
        self.bounds = bounds
        self.position = position
        self.anchorPoint = anchorPoint
        self.transform = transform
        self.zPosition = zPosition
        self.isHidden = isHidden
        self.opacity = opacity
        self.masksToBounds = masksToBounds
        self.viewControllerClassName = viewControllerClassName
        self.viewControllerDisplayClassName = viewControllerDisplayClassName
        self.memberReferences = memberReferences
        self.layerAddress = layerAddress
        self.viewAddress = viewAddress
        self.viewControllerAddress = viewControllerAddress
        self.layerClassOrigin = layerClassOrigin
        self.viewClassOrigin = viewClassOrigin
        self.viewControllerClassOrigin = viewControllerClassOrigin
        self.layerBaseClassName = layerBaseClassName
        self.viewBaseClassName = viewBaseClassName
        self.viewControllerVisibility = viewControllerVisibility
        self.kind = kind
        self.name = name
        self.isCollapsedByDefault = isCollapsedByDefault
        self.isCaptureExcluded = isCaptureExcluded
    }
}

public struct Hierarchy: Equatable, Sendable {
    /// Pre-order: a node's parent always comes before it. Siblings are ordered back to front.
    public var nodes: [LayerNode]
    /// 0 when there is no key window.
    public var keyWindowID: UInt64

    public init(nodes: [LayerNode], keyWindowID: UInt64) {
        self.nodes = nodes
        self.keyWindowID = keyWindowID
    }
}
