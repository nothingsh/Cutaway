import CutawayWire

/// A component of a value that is outside the limits its attribute states (C-ATTR-13,
/// P-SET-07): such a value is not sent.
public struct LimitViolation: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The component is outside this limit.
        case outOfRange(NumberLimit)
    }

    /// Nil for an attribute of one number; otherwise the component's index, in the order of
    /// P-ATTR-09.
    public var component: Int?
    public var reason: Reason

    public init(component: Int?, reason: Reason) {
        self.component = component
        self.reason = reason
    }
}

extension NumberLimit {
    /// Whether a number is within the limit (P-ATTR-10). A number that is not one is not.
    public func contains(_ x: Double) -> Bool {
        guard !x.isNaN else { return false }
        if let minimum, minimumIsExclusive ? x <= minimum : x < minimum { return false }
        if let maximum, maximumIsExclusive ? x >= maximum : x > maximum { return false }
        return true
    }
}

extension [NumberLimit] {
    /// The limit of one component: a single entry is every component's (P-ATTR-09).
    public func limit(forComponent index: Int) -> NumberLimit {
        count == 1 ? self[0] : (indices.contains(index) ? self[index] : NumberLimit())
    }
}

extension AttributeValue {
    /// The numbers of the value in the order of P-ATTR-09: one for an integer or a double,
    /// and the components of a point, size, rect, insets or transform; nil for any other.
    public var numericComponents: [Double]? {
        switch self {
        case .integer(let integer): [Double(integer)]
        case .double(let double): [double]
        case .point(let p): [p.x, p.y]
        case .size(let s): [s.width, s.height]
        case .rect(let r): [r.origin.x, r.origin.y, r.size.width, r.size.height]
        case .insets(let i): [i.top, i.left, i.bottom, i.right]
        case .transform(let t):
            [
                t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24,
                t.m31, t.m32, t.m33, t.m34, t.m41, t.m42, t.m43, t.m44,
            ]
        case .bool, .string, .color, .enumeration, .references: nil
        }
    }
}

extension Attribute {
    /// The first component of `value` outside the attribute's limits, or nil when it may be
    /// sent: there are no limits, the value has no numbers, or all are within them. An
    /// integer is compared as a double (P-ATTR-10). Only the limits given count, never the
    /// attribute's ID (C-ATTR-03).
    public func limitViolation(of value: AttributeValue?) -> LimitViolation? {
        guard let limits, let numbers = value?.numericComponents,
              let index = numbers.indices.first(where: { !limits.limit(forComponent: $0).contains(numbers[$0]) })
        else { return nil }
        return LimitViolation(
            component: numbers.count == 1 ? nil : index,
            reason: .outOfRange(limits.limit(forComponent: index)))
    }

    /// The indices of the components of `value` outside the limits, for marking them.
    public func componentsOutsideLimits(of value: AttributeValue?) -> [Int] {
        guard let limits, let numbers = value?.numericComponents else { return [] }
        return numbers.indices.filter { !limits.limit(forComponent: $0).contains(numbers[$0]) }
    }
}
