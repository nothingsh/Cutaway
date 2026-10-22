import CutawayModel
import CutawayWire

/// The compound rows the panel knows (C-ATTR-19, P-ATTR-12): which clusters, which parts each
/// has, and the kind of value each part takes. Only the cluster and slot names decide, never
/// the attributes' IDs (C-ATTR-03).
enum AttributeClusters {
    /// A cluster the panel draws as one row.
    enum Kind: String, CaseIterable {
        case visibility, corners, border, shadow, geometry, sizing, autoLayout, font, lines, state,
             scrolling
        // Protocol 1.2.
        case image, indexPath, listCounts
    }

    /// The names of the slots (P-ATTR-12), as the server gives them: what the rows know their
    /// parts by.
    enum Slot {
        // visibility
        static let hidden = "hidden"
        static let opacity = "opacity"
        // corners, shadow
        static let radius = "radius"
        static let clip = "clip"
        // border, shadow
        static let width = "width"
        static let color = "color"
        static let offset = "offset"
        // geometry
        static let frame = "frame"
        static let position = "position"
        static let anchor = "anchor"
        static let bounds = "bounds"
        static let zPosition = "zPosition"
        static let transform = "transform"
        // sizing
        static let huggingHorizontal = "hugging.horizontal"
        static let huggingVertical = "hugging.vertical"
        static let compressionHorizontal = "compression.horizontal"
        static let compressionVertical = "compression.vertical"
        static let intrinsicWidth = "intrinsic.width"
        static let intrinsicHeight = "intrinsic.height"
        // autoLayout
        static let autoresizing = "autoresizing"
        static let ambiguous = "ambiguous"
        // font, image
        static let name = "name"
        static let size = "size"
        static let textStyle = "textStyle"
        static let scalable = "scalable"
        // lines
        static let count = "count"
        static let lineBreak = "lineBreak"
        static let drawn = "drawn"
        static let truncated = "truncated"
        // state, scrolling
        static let enabled = "enabled"
        static let selected = "selected"
        static let highlighted = "highlighted"
        static let paging = "paging"
        // image
        static let scale = "scale"
        static let renderingMode = "renderingMode"
        static let symbolConfiguration = "symbolConfiguration"
        // indexPath, listCounts
        static let section = "section"
        static let item = "item"
        static let sections = "sections"
        static let items = "items"
    }

    /// What a part takes.
    private enum Takes {
        case bool, number, color, rect, point, size, transform, string, integer, enumeration

        func accepts(_ kind: AttributeValueKind) -> Bool {
            switch self {
            case .bool: kind == .bool
            case .number: kind == .integer || kind == .double
            case .integer: kind == .integer
            case .color: kind == .color
            case .rect: kind == .rect
            case .point: kind == .point
            case .size: kind == .size
            case .transform: kind == .transform
            case .string: kind == .string
            case .enumeration: kind == .enumeration
            }
        }
    }

    /// The slots of each cluster, in the order the row shows them. `font`'s `textStyle` and
    /// `scalable` and `lines`' `drawn` and `truncated` are 1.2's (C-ATTR-27).
    private static let slots: [Kind: [(String, Takes)]] = [
        .visibility: [(Slot.hidden, .bool), (Slot.opacity, .number)],
        .corners: [(Slot.radius, .number), (Slot.clip, .bool)],
        .border: [(Slot.width, .number), (Slot.color, .color)],
        .shadow: [(Slot.color, .color), (Slot.opacity, .number), (Slot.radius, .number), (Slot.offset, .size)],
        .geometry: [
            (Slot.frame, .rect), (Slot.position, .point), (Slot.anchor, .point), (Slot.bounds, .rect),
            (Slot.zPosition, .number), (Slot.transform, .transform),
        ],
        .sizing: [
            (Slot.huggingHorizontal, .number), (Slot.huggingVertical, .number),
            (Slot.compressionHorizontal, .number), (Slot.compressionVertical, .number),
            (Slot.intrinsicWidth, .number), (Slot.intrinsicHeight, .number),
        ],
        .autoLayout: [(Slot.autoresizing, .bool), (Slot.ambiguous, .bool)],
        .font: [(Slot.name, .string), (Slot.size, .number), (Slot.textStyle, .string), (Slot.scalable, .bool)],
        .lines: [
            (Slot.count, .integer), (Slot.lineBreak, .enumeration), (Slot.drawn, .integer), (Slot.truncated, .bool),
        ],
        .state: [(Slot.enabled, .bool), (Slot.selected, .bool), (Slot.highlighted, .bool)],
        .scrolling: [(Slot.enabled, .bool), (Slot.paging, .bool)],
        .image: [
            (Slot.name, .string), (Slot.size, .size), (Slot.scale, .number), (Slot.renderingMode, .enumeration),
            (Slot.symbolConfiguration, .string),
        ],
        .indexPath: [(Slot.section, .integer), (Slot.item, .integer)],
        .listCounts: [(Slot.sections, .integer), (Slot.items, .integer)],
    ]

    /// The slots a row writes as text, not in an editor (C-ATTR-27): what the app works out
    /// rather than what is set. One that can be changed has its own row and its editor, so
    /// that putting it in the row takes nothing away.
    private static let textSlots: [Kind: Set<String>] = [
        .font: [Slot.textStyle],
        .lines: [Slot.drawn, Slot.truncated],
        .image: [Slot.name, Slot.size, Slot.scale, Slot.symbolConfiguration],
        .indexPath: [Slot.section, Slot.item],
        .listCounts: [Slot.sections, Slot.items],
    ]

    /// Whether a row writes the slot as text.
    static func isText(_ slot: String, in kind: Kind) -> Bool {
        textSlots[kind]?.contains(slot) ?? false
    }

    /// The slots of a cluster, in order.
    static func slotNames(of kind: Kind) -> [String] {
        (slots[kind] ?? []).map(\.0)
    }

    /// Whether an attribute can be the given slot of a cluster: the slot is the cluster's,
    /// its value is of the kind the part takes, and it is not one written as text that can be
    /// changed.
    static func fits(_ attribute: Attribute, slot: String, in kind: Kind) -> Bool {
        guard let takes = slots[kind]?.first(where: { $0.0 == slot })?.1 else { return false }
        if isText(slot, in: kind), attribute.isEditable { return false }
        let valueKind = attribute.valueKind == .none ? attribute.value?.kind : attribute.valueKind
        return valueKind.map(takes.accepts) ?? false
    }

    /// One cluster as listed: its members by slot.
    struct Row: Equatable {
        var kind: Kind
        var members: [String: Attribute]
        /// The slots in the order their attributes came.
        var order: [String] = []

        /// The members in the order they came, which is the order of the list's attributes.
        var attributes: [Attribute] { order.compactMap { members[$0] } }

        subscript(slot: String) -> Attribute? { members[slot] }

        mutating func add(_ attribute: Attribute, as slot: String) {
            members[slot] = attribute
            order.append(slot)
        }
    }

    /// An item of a section: an attribute on its own row, or a compound row.
    enum Item: Equatable {
        case single(Attribute)
        case cluster(Row)

        var attributes: [Attribute] {
            switch self {
            case .single(let attribute): [attribute]
            case .cluster(let row): row.attributes
            }
        }
    }

    /// The items of a section's attributes, given as parts (one to a group): a cluster the
    /// panel knows is one item in the place of its first member, and gathers its members from
    /// every part of the section. A member that does not fit its cluster, or a second
    /// member for a slot already taken, is listed on its own just after the cluster's row.
    /// Every attribute is listed exactly once (P-ATTR-03).
    static func items(of parts: [[Attribute]]) -> [[Item]] {
        let all = parts.flatMap { $0 }
        var rows: [String: Row] = [:]
        var leftOver: [String: [Attribute]] = [:]
        for attribute in all {
            guard let cluster = attribute.cluster, let kind = Kind(rawValue: cluster.name) else { continue }
            var row = rows[cluster.name] ?? Row(kind: kind, members: [:])
            if row.members[cluster.slot] == nil, fits(attribute, slot: cluster.slot, in: kind) {
                row.add(attribute, as: cluster.slot)
            } else {
                leftOver[cluster.name, default: []].append(attribute)
            }
            rows[cluster.name] = row
        }
        var listed = Set<String>()
        return parts.map { part in
            var items: [Item] = []
            for attribute in part {
                guard let name = attribute.cluster?.name, let row = rows[name] else {
                    items.append(.single(attribute))
                    continue
                }
                guard listed.insert(name).inserted else { continue }
                // A cluster none of whose members fits is no row: its attributes go one by one.
                if !row.members.isEmpty { items.append(.cluster(row)) }
                items += (leftOver[name] ?? []).map(Item.single)
            }
            return items
        }
    }
}
