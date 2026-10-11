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
    /// The raw value of each case, parallel to `cases` (P-ATTR-07). Empty from a 0.2 server,
    /// and in a `SetAttribute`, which only needs `value` (P-SET-02). Protocol 0.3.
    public var caseValues: [Int64]

    public init(value: Int64, cases: [String], caseName: String?, caseValues: [Int64] = []) {
        self.value = value
        self.cases = cases
        self.caseName = caseName
        self.caseValues = caseValues
    }
}

public struct Attribute: Equatable, Sendable {
    /// Stable, for example "layer.cornerRadius".
    public var id: String?
    public var title: String?
    /// Nil means the attribute's value is nil (P-ATTR-02).
    public var value: AttributeValue?
    /// `SetAttribute` may change it (P-ATTR-06). False from a 0.2 server. Protocol 0.3.
    public var editable: Bool
    /// `SetAttribute` may set it to nil. Meaningful only when `editable`. Protocol 0.3.
    public var acceptsNil: Bool
    /// The member `value` uses, given also when `value` is nil. `.none` from a 0.2 server.
    /// Protocol 0.3.
    public var valueKind: AttributeValueKind

    public init(
        id: String?, title: String?, value: AttributeValue?, editable: Bool = false,
        acceptsNil: Bool = false, valueKind: AttributeValueKind = .none
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.editable = editable
        self.acceptsNil = acceptsNil
        self.valueKind = valueKind
    }
}

public struct AttributeGroup: Equatable, Sendable {
    /// Stable, for example "layer".
    public var id: String?
    public var title: String?
    public var attributes: [Attribute]

    public init(id: String?, title: String?, attributes: [Attribute]) {
        self.id = id
        self.title = title
        self.attributes = attributes
    }
}
