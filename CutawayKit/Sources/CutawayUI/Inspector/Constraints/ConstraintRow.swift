import CutawayModel
import CutawayScene
import CutawayWire
import Foundation

/// How the attribute panel writes one constraint of the selected view (C-LAYOUT-02):
/// "first.attribute relation second.attribute × multiplier + constant", and the lines below
/// it. An end that is another view or a layout guide is a chip (C-LAYOUT-06) that says which
/// layer it is, so that the panel can go there (C-LAYOUT-03), and which mark on the preview.
struct ConstraintRow: Equatable {
    enum Piece: Equatable {
        case text(String)
        /// The selected view.
        case selfItem
        /// Another view, or a layout guide.
        case end(End)
    }

    /// The other end of a constraint as a chip (C-LAYOUT-06).
    struct End: Equatable {
        enum Kind: Equatable {
            /// A view, with its icon (C-HIER-11).
            case view(LayerIcon)
            case guide
        }

        /// A view's short name (`LayerTree.shortTitle(of:)`), "ID n" for one not in the tree;
        /// a guide's name (C-LAYOUT-02).
        var name: String
        var kind: Kind
        /// The layer a click selects: the view, or the guide's owner. Nil when there is none to
        /// go to: a layer not in the tree, or a guide of the selected view (C-LAYOUT-03).
        var layerID: UInt64?
        /// The end's mark on the preview (`ConstraintEnd.mark(of:selected:)`), or nil when it
        /// has none.
        var mark: SceneMark?

        /// Whether a click goes to it.
        var canSelect: Bool { layerID != nil }
        /// Whether pointing at it does anything: hover its layer, or stress its mark.
        var canHover: Bool { layerID != nil || mark != nil }
    }

    var id: UInt64
    /// Its place among the selected view's constraints, in the server's order: what pointing
    /// at it tells the store (C-LAYOUT-07).
    var index: Int
    var equation: [Piece]
    /// "Priority 250 · titleLabel.preferredWidth", or nil for a required constraint without an
    /// identifier.
    var details: String?
    /// "Safe Area of UIView", one for each end that is a layout guide.
    var guideOwners: [String]
    var status: ConstraintStatus
    /// The class of a constraint UIKit made (P-LAYOUT-02), or nil for one the app made.
    var generatedClassName: String?

    init(_ constraint: LayoutConstraint, selected: UInt64, tree: LayerTree, index: Int = 0) {
        id = constraint.id
        self.index = index
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

    /// The equation as plain text, "self" included, a chip by its name.
    var plainEquation: String { Self.plain(equation) }

    /// Whether UIKit made the constraint: as the server says (P-LAYOUT-09), or from an older
    /// server, when its class is neither `NSLayoutConstraint` nor the class layout anchors
    /// make. One without a class name, against P-LAYOUT-02, counts as the app's.
    private static func isGenerated(_ constraint: LayoutConstraint) -> Bool {
        switch constraint.origin {
        case .system: return true
        case .app: return false
        case .unknown:
            guard let className = constraint.className else { return false }
            return !Self.appConstraintClasses.contains(className)
        }
    }

    /// The classes of the constraints an app makes itself, for a server that gives no origin.
    private static let appConstraintClasses: Set<String> = [
        "NSLayoutConstraint", "NSLayoutAnchorConstraint",
    ]

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

    /// The name of a kind of guide the server named (P-LAYOUT-04); nil for any other.
    private static func guideName(_ kind: LayoutGuideKind) -> String? {
        switch kind {
        case .safeArea: localized("constraints.guide.safeArea")
        case .layoutMargins: localized("constraints.guide.layoutMargins")
        case .readableContent: localized("constraints.guide.readableContent")
        case .keyboard: localized("constraints.guide.keyboard")
        case .unknown, .other: nil
        }
    }

    /// The names of the layout guides UIKit makes, by `identifier`, for a server that gives
    /// no kind. Only the safe area's has a source (the protocol's fixture); the others are to
    /// be checked against a real app, and a wrong one only falls back to the identifier. Any
    /// other guide shows its identifier.
    private static func guideName(_ identifier: String) -> String? {
        switch identifier {
        case "UIViewSafeAreaLayoutGuide": localized("constraints.guide.safeArea")
        case "UIViewLayoutMarginsGuide": localized("constraints.guide.layoutMargins")
        case "UIViewReadableContentGuide": localized("constraints.guide.readableContent")
        case "UIKeyboardLayoutGuide": localized("constraints.guide.keyboard")
        default: nil
        }
    }

    /// The name of a layout guide: a known one's, its identifier, or its class. Only without
    /// a kind is the identifier looked up: `other` says it is none of the known ones.
    static func name(of guide: LayoutGuide) -> String {
        if let name = guideName(guide.kind) { return name }
        if let identifier = guide.identifier, !identifier.isEmpty {
            return guide.kind == .unknown ? guideName(identifier) ?? identifier : identifier
        }
        return [guide.displayClassName, guide.className].compactMap { $0 }
            .first { !$0.isEmpty } ?? localized("constraints.guide.generic")
    }

    /// One end: what it is written as, and for a layout guide the line naming its owner.
    private static func end(
        _ item: LayoutItem?, selected: UInt64, tree: LayerTree
    ) -> (piece: Piece, owner: String?) {
        let mark = ConstraintEnd.mark(of: item, selected: selected)
        switch item {
        case .view(let id) where id == selected:
            return (.selfItem, nil)
        case .view(let id):
            guard tree.contains(id) else {
                let icon = LayerIcon(.container, .view, isAppClass: false)
                return (.end(End(name: "ID \(id)", kind: .view(icon), layerID: nil, mark: nil)), nil)
            }
            let end = End(
                name: tree.shortTitle(of: id), kind: .view(LayerIcon(tree.node(id))), layerID: id,
                mark: mark)
            return (.end(end), nil)
        case .layoutGuide(let guide):
            let name = Self.name(of: guide)
            let owner = guide.ownerLayerID
            let known = tree.contains(owner)
            let ownerName = owner == selected
                ? "self" : known ? tree.displayTitle(of: owner) : "ID \(owner)"
            let end = End(
                name: name, kind: .guide, layerID: owner != selected && known ? owner : nil,
                mark: owner == selected || known ? mark : nil)
            return (.end(end), localized("constraints.guideOf", name, ownerName))
        case .other(let className, let displayClassName):
            let name = [displayClassName, className].compactMap { $0 }.first { !$0.isEmpty }
            return (.text(name ?? "?"), nil)
        case nil:
            return (.text("?"), nil)
        }
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
