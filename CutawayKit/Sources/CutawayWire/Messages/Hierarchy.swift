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

    public init(
        id: UInt64, parentID: UInt64, className: String?, displayClassName: String?,
        viewClassName: String?, viewDisplayClassName: String?, bounds: Rect?, position: Point?,
        anchorPoint: Point?, transform: Transform3D?, zPosition: Double, isHidden: Bool,
        opacity: Float, masksToBounds: Bool, viewControllerClassName: String? = nil,
        viewControllerDisplayClassName: String? = nil, memberReferences: [MemberReference] = []
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
