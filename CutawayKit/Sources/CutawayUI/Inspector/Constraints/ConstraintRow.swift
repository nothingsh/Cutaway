import CutawayModel
import CutawayWire
import Foundation

/// How the attribute panel writes one constraint of the selected view (C-LAYOUT-02):
/// "first.attribute relation second.attribute × multiplier + constant", the ends named as the
/// list names them, and the lines below it. Pieces that name another layer say which, so that
/// the panel can go there (C-LAYOUT-03).
struct ConstraintRow: Equatable {
    enum Piece: Equatable {
        case text(String)
        /// The selected view.
        case selfItem
        /// Another layer, named as the list names it; for a layout guide, the guide's name and
        /// its owner's layer.
        case link(String, layerID: UInt64)
    }

    var id: UInt64
    var equation: [Piece]
    /// "Priority 250 · titleLabel.preferredWidth", or nil for a required constraint without an
    /// identifier.
    var details: String?
    /// "Safe Area of UIView", one for each end that is a layout guide.
    var guideOwners: [String]
    var status: ConstraintStatus
    /// The class of a constraint UIKit made (P-LAYOUT-02), or nil for one the app made.
    var generatedClassName: String?

    init(_ constraint: LayoutConstraint, selected: UInt64, tree: LayerTree) {
        id = constraint.id
        status = constraint.status
        generatedClassName = Self.isGenerated(constraint) ? constraint.className : nil
        var pieces: [Piece] = []
        var owners: [String] = []
        func append(_ item: LayoutItem?, _ attribute: LayoutAttribute) {
            let end = Self.end(item, selected: selected, tree: tree)
            pieces.append(end.piece)
            if let owner = end.owner { owners.append(owner) }
            pieces.append(.text("." + Self.name(of: attribute)))
        }
        append(constraint.firstItem, constraint.firstAttribute)
        pieces.append(.text(" \(Self.symbol(of: constraint.relation)) "))
        if constraint.secondItem != nil {
            append(constraint.secondItem, constraint.secondAttribute)
            if constraint.multiplier != 1 {
                pieces.append(.text(" × " + AttributeText.number(constraint.multiplier)))
            }
            if constraint.constant != 0 {
                let sign = constraint.constant < 0 ? "−" : "+"
                pieces.append(.text(" \(sign) " + AttributeText.number(abs(constraint.constant))))
            }
        } else {
            // Nothing but the constant, even when it is 0 (P-LAYOUT-05).
            let constant = constraint.constant
            pieces.append(.text(
                (constant < 0 ? "−" : "") + AttributeText.number(abs(constant))))
        }
        equation = Self.merged(pieces)
        guideOwners = owners
        var lines: [String] = []
        if constraint.priority < 1000 {
            lines.append(
                localized("constraints.priority", AttributeText.number(Double(constraint.priority))))
        }
        if let identifier = constraint.identifier, !identifier.isEmpty { lines.append(identifier) }
        details = lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// The equation as plain text, "self" included.
    var plainEquation: String {
        equation.map { piece in
            switch piece {
            case .text(let text): text
            case .selfItem: "self"
            case .link(let name, _): name
            }
        }.joined()
    }

    /// Whether UIKit made the constraint: its class is not `NSLayoutConstraint` (P-LAYOUT-02).
    /// One without a class name, against that clause, counts as the app's.
    private static func isGenerated(_ constraint: LayoutConstraint) -> Bool {
        guard let className = constraint.className else { return false }
        return className != "NSLayoutConstraint"
    }

    /// A constraint class as words: "NSAutoresizingMaskLayoutConstraint" is "Autoresizing Mask".
    /// Nil when nothing is left of it.
    static func readableClassName(_ className: String) -> String? {
        var name = Substring(className)
        while name.hasPrefix("_") { name = name.dropFirst() }
        for prefix in ["NS", "UI"] where name.hasPrefix(prefix) {
            name = name.dropFirst(prefix.count)
            break
        }
        for suffix in ["LayoutConstraint", "Constraint"] where name.hasSuffix(suffix) {
            name = name.dropLast(suffix.count)
            break
        }
        var words = ""
        var previous: Character?
        for character in name {
            if character.isUppercase, let previous, previous.isLowercase { words.append(" ") }
            words.append(character)
            previous = character
        }
        return words.isEmpty ? nil : words
    }

    /// The names of the layout guides UIKit makes, by `identifier`. Only the safe area's has a
    /// source (the protocol's fixture); the others are to be checked against a real app, and a
    /// wrong one only falls back to the identifier. Any other guide shows its identifier.
    private static func guideName(_ identifier: String) -> String? {
        switch identifier {
        case "UIViewSafeAreaLayoutGuide": localized("constraints.guide.safeArea")
        case "UIViewLayoutMarginsGuide": localized("constraints.guide.layoutMargins")
        case "UIViewReadableContentGuide": localized("constraints.guide.readableContent")
        case "UIKeyboardLayoutGuide": localized("constraints.guide.keyboard")
        default: nil
        }
    }

    /// The name of a layout guide: a known one's, its identifier, or its class.
    static func name(of guide: LayoutGuide) -> String {
        if let identifier = guide.identifier, !identifier.isEmpty {
            return guideName(identifier) ?? identifier
        }
        return [guide.displayClassName, guide.className].compactMap { $0 }
            .first { !$0.isEmpty } ?? localized("constraints.guide.generic")
    }

    /// One end: what it is written as, and for a layout guide the line naming its owner.
    private static func end(
        _ item: LayoutItem?, selected: UInt64, tree: LayerTree
    ) -> (piece: Piece, owner: String?) {
        switch item {
        case .view(let id):
            return (layer(id, named: nil, selected: selected, tree: tree), nil)
        case .layoutGuide(let guide):
            let name = Self.name(of: guide)
            let owner = guide.ownerLayerID
            let ownerName = owner == selected
                ? "self" : tree.contains(owner) ? tree.displayTitle(of: owner) : "ID \(owner)"
            return (
                layer(owner, named: name, selected: selected, tree: tree),
                localized("constraints.guideOf", name, ownerName))
        case .other(let className, let displayClassName):
            let name = [displayClassName, className].compactMap { $0 }.first { !$0.isEmpty }
            return (.text(name ?? "?"), nil)
        case nil:
            return (.text("?"), nil)
        }
    }

    /// A layer's piece: "self", a link to it, or its ID when it is not in the tree. `name`
    /// stands for a layout guide of the layer.
    private static func layer(
        _ id: UInt64, named name: String?, selected: UInt64, tree: LayerTree
    ) -> Piece {
        if id == selected { return name.map { .text($0) } ?? .selfItem }
        guard tree.contains(id) else { return .text(name ?? "ID \(id)") }
        return .link(name ?? tree.displayTitle(of: id), layerID: id)
    }

    /// The attribute as UIKit names it. `notAnAttribute` at an end that is there is one the
    /// server could not name (P-LAYOUT-08).
    static func name(of attribute: LayoutAttribute) -> String {
        switch attribute {
        case .notAnAttribute: "unknown"
        case .left: "left"
        case .right: "right"
        case .top: "top"
        case .bottom: "bottom"
        case .leading: "leading"
        case .trailing: "trailing"
        case .width: "width"
        case .height: "height"
        case .centerX: "centerX"
        case .centerY: "centerY"
        case .lastBaseline: "lastBaseline"
        case .firstBaseline: "firstBaseline"
        case .leftMargin: "leftMargin"
        case .rightMargin: "rightMargin"
        case .topMargin: "topMargin"
        case .bottomMargin: "bottomMargin"
        case .leadingMargin: "leadingMargin"
        case .trailingMargin: "trailingMargin"
        case .centerXWithinMargins: "centerXWithinMargins"
        case .centerYWithinMargins: "centerYWithinMargins"
        case .minX: "minX"
        case .minY: "minY"
        case .maxX: "maxX"
        case .maxY: "maxY"
        }
    }

    private static func symbol(of relation: LayoutRelation) -> String {
        switch relation {
        case .equal: "="
        case .lessThanOrEqual: "≤"
        case .greaterThanOrEqual: "≥"
        }
    }

    /// Neighbouring texts joined into one.
    private static func merged(_ pieces: [Piece]) -> [Piece] {
        var result: [Piece] = []
        for piece in pieces {
            if case .text(let next) = piece, case .text(let last)? = result.last {
                result[result.count - 1] = .text(last + next)
            } else {
                result.append(piece)
            }
        }
        return result
    }
}

/// The constraints of the Constraints section (C-LAYOUT-02), as it lists them: the app's own,
/// then those UIKit made (P-LAYOUT-02), each in the server's order, with what the row that
/// folds UIKit's away says about them.
struct ConstraintList: Equatable {
    let rows: [ConstraintRow]
    /// The constraints the app made.
    let own: [ConstraintRow]
    /// The constraints UIKit made.
    let generated: [ConstraintRow]
    /// The class of UIKit's constraints as words, when they are all of one class.
    let generatedSummary: String?

    init(_ rows: [ConstraintRow]) {
        self.rows = rows
        own = rows.filter { $0.generatedClassName == nil }
        generated = rows.filter { $0.generatedClassName != nil }
        let classes = Set(generated.compactMap(\.generatedClassName))
        generatedSummary = classes.count == 1
            ? classes.first.flatMap(ConstraintRow.readableClassName) : nil
    }

    /// How many constraints there are, after the section's title.
    var count: Int { rows.count }
    /// How many UIKit made, on the row that folds them away.
    var generatedCount: Int { generated.count }
}
