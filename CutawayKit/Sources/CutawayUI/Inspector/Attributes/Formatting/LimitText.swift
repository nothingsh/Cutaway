import CutawayModel
import CutawayWire

/// How the attribute panel words limits (C-ATTR-13): why a value outside them is not sent, and
/// why typed text is not a number it can send (C-ATTR-05).
enum LimitText {
    /// Why a value is not sent: "Must be between 0 and 1.", or for a component "Width must
    /// be 0 or more.".
    /// A proportion's numbers are in percent: "Must be between 0% and 100%." (C-ATTR-20).
    static func message(
        _ violation: LimitViolation, kind: AttributeValueKind, unit: AttributeUnit = .unspecified
    ) -> String {
        switch violation.reason {
        case .outOfRange(let limit):
            return message(
                limit, name: violation.component.flatMap { componentName(kind, $0) }, unit: unit)
        }
    }

    /// How a bound is written: in percent for a proportion, otherwise as a plain number.
    private static func writer(_ unit: AttributeUnit) -> (Double) -> String {
        unit == .fraction ? { AttributeText.percent($0) + "%" } : AttributeText.number
    }

    /// The name of a component in a message, in the order of P-ATTR-09; nil for one the kind
    /// does not have.
    static func componentName(_ kind: AttributeValueKind, _ index: Int) -> String? {
        let names: [String] = switch kind {
        case .point: [x, y]
        case .size: [width, height]
        case .rect: [x, y, width, height]
        case .insets:
            [
                localized("attributes.component.top"), localized("attributes.component.left"),
                localized("attributes.component.bottom"), localized("attributes.component.right"),
            ]
        case .transform: (1...4).flatMap { row in (1...4).map { "m\(row)\($0)" } }
        default: []
        }
        return names.indices.contains(index) ? names[index] : nil
    }

    private static var x: String { localized("attributes.component.x") }
    private static var y: String { localized("attributes.component.y") }
    private static var width: String { localized("attributes.component.width") }
    private static var height: String { localized("attributes.component.height") }

    private static func message(_ limit: NumberLimit, name: String?, unit: AttributeUnit) -> String {
        let write = writer(unit)
        let low = limit.minimum.map(write)
        let high = limit.maximum.map(write)
        switch (low, high, limit.minimumIsExclusive, limit.maximumIsExclusive, name) {
        case (let low?, let high?, false, false, nil): return localized("attributes.limit.between", low, high)
        case (let low?, let high?, false, false, let name?):
            return localized("attributes.limit.named.between", name, low, high)
        case (let low?, let high?, true, false, nil): return localized("attributes.limit.moreThanAtMost", low, high)
        case (let low?, let high?, true, false, let name?):
            return localized("attributes.limit.named.moreThanAtMost", name, low, high)
        case (let low?, let high?, false, true, nil): return localized("attributes.limit.atLeastLessThan", low, high)
        case (let low?, let high?, false, true, let name?):
            return localized("attributes.limit.named.atLeastLessThan", name, low, high)
        case (let low?, let high?, true, true, nil): return localized("attributes.limit.moreThanLessThan", low, high)
        case (let low?, let high?, true, true, let name?):
            return localized("attributes.limit.named.moreThanLessThan", name, low, high)
        case (let low?, nil, false, _, nil): return localized("attributes.limit.atLeast", low)
        case (let low?, nil, false, _, let name?): return localized("attributes.limit.named.atLeast", name, low)
        case (let low?, nil, true, _, nil): return localized("attributes.limit.moreThan", low)
        case (let low?, nil, true, _, let name?): return localized("attributes.limit.named.moreThan", name, low)
        case (nil, let high?, _, false, nil): return localized("attributes.limit.atMost", high)
        case (nil, let high?, _, false, let name?): return localized("attributes.limit.named.atMost", name, high)
        case (nil, let high?, _, true, nil): return localized("attributes.limit.lessThan", high)
        case (nil, let high?, _, true, let name?): return localized("attributes.limit.named.lessThan", name, high)
        case (nil, nil, _, _, _): return ""
        }
    }

    // MARK: - Typed text

    /// Why typed text is not a number the field can send (C-ATTR-05).
    enum InputProblem: Error, Equatable {
        /// It does not read as a finite number.
        case notANumber
        /// A decimal in an integer's field.
        case notWhole
        /// An integer a Double does not hold exactly: it cannot travel as one.
        case tooLarge
    }

    static func message(_ problem: InputProblem) -> String {
        switch problem {
        case .notANumber: localized("attributes.input.number")
        case .notWhole: localized("attributes.input.whole")
        case .tooLarge: localized("attributes.input.tooLarge")
        }
    }
}
