/// Attributes describe themselves: the server decides which groups and attributes exist, and
/// the client shows whatever arrives (P-ATTR-03).

public enum AttributeValue: Equatable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case color(Color)
    case point(Point)
    case size(Size)
    case rect(Rect)
    case insets(Insets)
    case transform(Transform3D)
    case enumeration(EnumValue)
}

/// The member of `AttributeValue` an attribute's value uses (P-ATTR-06). Protocol 0.3.
/// `none` also stands for a kind this client does not know: the runtime reads an unknown
/// enum value as the first member.
public enum AttributeValueKind: Equatable, Sendable {
    case none, bool, integer, double, string, color, point, size, rect, insets, transform,
         enumeration
}

extension AttributeValue {
    /// The member this value uses.
    public var kind: AttributeValueKind {
        switch self {
        case .bool: .bool
        case .integer: .integer
        case .double: .double
        case .string: .string
        case .color: .color
        case .point: .point
        case .size: .size
        case .rect: .rect
        case .insets: .insets
        case .transform: .transform
        case .enumeration: .enumeration
        }
    }
}

public struct EnumValue: Equatable, Sendable {
    public var value: Int64
    /// The names of all cases, in declaration order.
    public var cases: [String]
    /// The name of the current case.
    public var caseName: String?
    /// The raw value of each case, parallel to `cases` (P-ATTR-07). Empty in a
    /// `SetAttribute`, which only needs `value` (P-SET-02). Protocol 0.3.
    public var caseValues: [Int64]

    public init(value: Int64, cases: [String], caseName: String?, caseValues: [Int64] = []) {
        self.value = value
        self.cases = cases
        self.caseName = caseName
        self.caseValues = caseValues
    }
}

/// The part of an inspector an attribute belongs on (P-ATTR-08). Protocol 1.1. A hint: every
/// attribute is still shown, and `unspecified` and values this client does not know count as
/// `general`.
public enum AttributeSection: Equatable, Sendable {
    case unspecified, identity, general, layout, content, appearance, behavior
}

/// How to read the numbers of an attribute's value (P-ATTR-14). Protocol 1.1. `unspecified`
/// also stands for values this client does not know.
public enum AttributeUnit: Equatable, Sendable {
    case unspecified, points, fraction
}

/// The compound row an attribute is part of, and its part in it (P-ATTR-12). Protocol 1.1.
public struct AttributeCluster: Equatable, Hashable, Sendable {
    /// For example "border".
    public var name: String
    /// For example "width".
    public var slot: String

    public init(name: String, slot: String) {
        self.name = name
        self.slot = slot
    }
}

/// The values `SetAttribute` accepts for one numeric component (P-ATTR-10). Protocol 1.1.
/// A nil bound leaves that side free.
public struct NumberLimit: Equatable, Sendable {
    public var minimum: Double?
    /// The component must be greater than `minimum`, not equal to it.
    public var minimumIsExclusive: Bool
    public var maximum: Double?
    /// The component must be less than `maximum`, not equal to it.
    public var maximumIsExclusive: Bool

    public init(
        minimum: Double? = nil, minimumIsExclusive: Bool = false, maximum: Double? = nil,
        maximumIsExclusive: Bool = false
    ) {
        self.minimum = minimum
        self.minimumIsExclusive = minimumIsExclusive
        self.maximum = maximum
        self.maximumIsExclusive = maximumIsExclusive
    }
}

extension AttributeValueKind {
    /// How many numbers a value of this kind has, in the order of P-ATTR-09; nil for a kind
    /// that has no limits.
    public var numericComponentCount: Int? {
        switch self {
        case .integer, .double: 1
        case .point, .size: 2
        case .rect, .insets: 4
        case .transform: 16
        case .none, .bool, .string, .color, .enumeration: nil
        }
    }

    /// Whether a value of this kind may have a unit other than `Unspecified` (P-ATTR-14):
    /// numbers, and the values made of lengths. Not a transform.
    public var mayHaveUnit: Bool {
        switch self {
        case .integer, .double, .point, .size, .rect, .insets: true
        case .none, .bool, .string, .color, .transform, .enumeration: false
        }
    }
}

public struct Attribute: Equatable, Sendable {
    /// Stable, for example "layer.cornerRadius".
    public var id: String?
    public var title: String?
    /// Nil means the attribute's value is nil (P-ATTR-02).
    public var value: AttributeValue?
    /// `SetAttribute` may change it (P-ATTR-06). Protocol 0.3.
    public var editable: Bool
    /// `SetAttribute` may set it to nil. Meaningful only when `editable`. Protocol 0.3.
    public var acceptsNil: Bool
    /// The member `value` uses, given also when `value` is nil. Protocol 0.3.
    public var valueKind: AttributeValueKind
    /// Which page of the panel it belongs on (P-ATTR-08). `unspecified` from a 1.0 server.
    /// Protocol 1.1.
    public var section: AttributeSection
    /// What `SetAttribute` accepts (P-ATTR-09, P-ATTR-10): nil for no limits, otherwise one
    /// entry for every component or one per component. Limits that break the protocol's rules
    /// are read as nil, so what is here can be used as it is. Protocol 1.1.
    public var limits: [NumberLimit]?
    /// Its place in a compound row (P-ATTR-12); nil when the server gave none, or only one of
    /// `cluster` and `slot`. Protocol 1.1.
    public var cluster: AttributeCluster?
    /// The ID of the attribute of the same layer that makes this one have no effect now
    /// (P-ATTR-13). Not checked against the layer's attributes here. Protocol 1.1.
    public var inactiveCause: String?
    /// Protocol 1.1 (P-ATTR-14).
    public var unit: AttributeUnit
    /// The name of the UIKit system color the value is, when the server recognised it
    /// (P-ATTR-15), for example "systemBlue". On the wire it is part of the `ColorValue`;
    /// it is kept here so that a color stays a plain value. Protocol 1.1.
    public var systemColorName: String?

    public init(
        id: String?, title: String?, value: AttributeValue?, editable: Bool = false,
        acceptsNil: Bool = false, valueKind: AttributeValueKind = .none,
        section: AttributeSection = .unspecified, limits: [NumberLimit]? = nil,
        cluster: AttributeCluster? = nil, inactiveCause: String? = nil,
        unit: AttributeUnit = .unspecified, systemColorName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.editable = editable
        self.acceptsNil = acceptsNil
        self.valueKind = valueKind
        self.section = section
        self.limits = limits
        self.cluster = cluster
        self.inactiveCause = inactiveCause
        self.unit = unit
        self.systemColorName = systemColorName
    }
}

public struct AttributeGroup: Equatable, Sendable {
    /// Stable, for example "layer".
    public var id: String?
    public var title: String?
    public var attributes: [Attribute]
    /// The runtime name of the class that declares the group's properties (P-ATTR-16), for
    /// example "UILabel". Protocol 1.1.
    public var className: String?

    public init(id: String?, title: String?, attributes: [Attribute], className: String? = nil) {
        self.id = id
        self.title = title
        self.attributes = attributes
        self.className = className
    }
}
