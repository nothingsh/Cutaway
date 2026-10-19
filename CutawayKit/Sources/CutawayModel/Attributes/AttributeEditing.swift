import CutawayWire

/// An attribute of a layer, as a change names it (C-ATTR-06).
public struct AttributeKey: Hashable, Sendable {
    public var layerID: UInt64
    public var attributeID: String

    public init(layerID: UInt64, attributeID: String) {
        self.layerID = layerID
        self.attributeID = attributeID
    }
}

/// What a row of the attribute panel shows besides its value (C-ATTR-06, C-ATTR-07).
public enum EditStatus: Equatable, Sendable {
    /// A change is on its way, or a drag goes on: the row shows this value.
    case sending(AttributeValue?)
    /// The last change failed: the row shows the value from before it, and why.
    case failed(EditFailure)
}

/// Why a change failed, as the row says it. A layer that is gone and a lost connection are
/// not among them: the panel and the window say those.
public enum EditFailure: Equatable, Sendable {
    /// The app did not take the value (`InvalidAttributeValue`, P-SET-03).
    case rejected
    /// The attribute cannot be changed (`AttributeNotEditable`, P-SET-03).
    case notEditable
    /// The app is not active (P-APP-01).
    case appNotActive
    /// No answer in time, or another failure.
    case noAnswer
    /// The value has a number that is not finite; it was not sent (C-ATTR-09).
    case notFinite
    /// A component is outside the attribute's limits; it was not sent (C-ATTR-13, P-SET-07).
    case outOfRange(LimitViolation)
}

extension AttributeValue {
    /// Whether every number in the value is finite. Only such a value is sent (C-ATTR-09).
    var isFinite: Bool {
        switch self {
        case .bool, .integer, .string, .enumeration, .references: true
        case .double(let value): value.isFinite
        case .color(let c): [c.red, c.green, c.blue, c.alpha].allSatisfy(\.isFinite)
        case .point(let p): p.x.isFinite && p.y.isFinite
        case .size(let s): s.width.isFinite && s.height.isFinite
        case .rect(let r):
            [r.origin.x, r.origin.y, r.size.width, r.size.height].allSatisfy(\.isFinite)
        case .insets(let i): [i.top, i.left, i.bottom, i.right].allSatisfy(\.isFinite)
        case .transform(let t):
            [
                t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24,
                t.m31, t.m32, t.m33, t.m34, t.m41, t.m42, t.m43, t.m44,
            ].allSatisfy(\.isFinite)
        }
    }
}

extension Attribute {
    /// Whether the panel offers an editor for it (C-ATTR-05): the server says it can be
    /// changed, its kind is one this client knows, a value that is there is of that kind
    /// (P-ATTR-06), and an enum has a raw value for every case (P-ATTR-07); an enum without a
    /// value has no cases to offer. Anything else is shown read-only rather than guessed at.
    /// Nothing here depends on the attribute's ID (C-ATTR-03). References are read-only
    /// whatever the server says (P-ATTR-18, C-WIRE-12).
    public var isEditable: Bool {
        guard editable, valueKind != .none, valueKind != .references else { return false }
        if let value, value.kind != valueKind { return false }
        guard valueKind == .enumeration else { return true }
        guard case .enumeration(let enumeration) = value else { return false }
        return !enumeration.cases.isEmpty && enumeration.caseValues.count == enumeration.cases.count
    }
}
