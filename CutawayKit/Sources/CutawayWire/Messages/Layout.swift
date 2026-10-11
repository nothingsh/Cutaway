// MARK: - Layout (protocol 0.4)

/// The attribute of an item a constraint relates. Same raw values as
/// NSLayoutConstraint.Attribute; `minX` to `maxY` (protocol 0.5) are the ones UIKit uses in the
/// constraints it makes from an autoresizing mask, outside the public enumeration (P-LAYOUT-07).
public enum LayoutAttribute: UInt8, Sendable {
    case notAnAttribute = 0
    case left, right, top, bottom, leading, trailing, width, height, centerX, centerY
    case lastBaseline, firstBaseline
    case leftMargin, rightMargin, topMargin, bottomMargin, leadingMargin, trailingMargin
    case centerXWithinMargins, centerYWithinMargins
    case minX = 32, minY = 33, maxX = 36, maxY = 37
}

public enum LayoutRelation: Sendable {
    case equal, lessThanOrEqual, greaterThanOrEqual
}

/// Whether a constraint's relation holds in the current layout, as the server checked it
/// (P-LAYOUT-06).
public enum ConstraintStatus: Sendable {
    case unknown, satisfied, unsatisfied
}

/// A layout guide at one end of a constraint (P-LAYOUT-04). It has no layer, so it is not a
/// node of the hierarchy.
public struct LayoutGuide: Equatable, Sendable {
    /// The layer of the view that owns the guide.
    public var ownerLayerID: UInt64
    public var guideID: UInt64
    public var className: String?
    public var displayClassName: String?
    /// UILayoutGuide.identifier, for example "UIViewSafeAreaLayoutGuide".
    public var identifier: String?
    /// The guide's layoutFrame, in the owner's bounds. Nil when the server left it out.
    public var frame: Rect?

    public init(
        ownerLayerID: UInt64, guideID: UInt64, className: String?, displayClassName: String?,
        identifier: String?, frame: Rect?
    ) {
        self.ownerLayerID = ownerLayerID
        self.guideID = guideID
        self.className = className
        self.displayClassName = displayClassName
        self.identifier = identifier
        self.frame = frame
    }
}

/// One end of a constraint (P-LAYOUT-04). Only the fields of its kind are read off the wire.
public enum LayoutItem: Equatable, Sendable {
    /// A view, by the layer that backs it.
    case view(layerID: UInt64)
    case layoutGuide(LayoutGuide)
    /// Neither a view nor a layout guide.
    case other(className: String?, displayClassName: String?)
}

/// An active Auto Layout constraint (P-LAYOUT-01 to P-LAYOUT-06), read as the server sent it.
public struct LayoutConstraint: Equatable, Sendable {
    /// The same in the details of every layer the constraint involves (P-LAYOUT-03).
    public var id: UInt64
    /// For example "NSLayoutConstraint" or "NSAutoresizingMaskLayoutConstraint".
    public var className: String?
    public var identifier: String?
    /// Nil only when the server broke P-LAYOUT-04.
    public var firstItem: LayoutItem?
    public var firstAttribute: LayoutAttribute
    public var relation: LayoutRelation
    /// Nil when the constraint has no second item (P-LAYOUT-05).
    public var secondItem: LayoutItem?
    public var secondAttribute: LayoutAttribute
    public var multiplier: Double
    public var constant: Double
    /// 1 to 1000.
    public var priority: Float
    public var status: ConstraintStatus

    public init(
        id: UInt64, className: String?, identifier: String?, firstItem: LayoutItem?,
        firstAttribute: LayoutAttribute, relation: LayoutRelation, secondItem: LayoutItem?,
        secondAttribute: LayoutAttribute, multiplier: Double, constant: Double, priority: Float,
        status: ConstraintStatus
    ) {
        self.id = id
        self.className = className
        self.identifier = identifier
        self.firstItem = firstItem
        self.firstAttribute = firstAttribute
        self.relation = relation
        self.secondItem = secondItem
        self.secondAttribute = secondAttribute
        self.multiplier = multiplier
        self.constant = constant
        self.priority = priority
        self.status = status
    }
}
