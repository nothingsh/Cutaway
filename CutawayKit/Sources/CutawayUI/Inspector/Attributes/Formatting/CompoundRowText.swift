import CutawayWire
import Foundation

/// What a compound row says in its own words (C-ATTR-19, C-ATTR-27): its title, the labels of
/// its lines and chips, and the texts it writes for what the app works out rather than sets.
/// Values only: the row draws them.
enum CompoundRowText {
    private typealias Slot = AttributeClusters.Slot

    /// What a text of a row says.
    enum Role {
        case textStyle, drawn, truncated, imageName, imageDetails, symbolConfiguration, indexPath, counts

        /// Whether it is the row's value rather than a note on it.
        var isPrimary: Bool { self == .imageName || self == .indexPath || self == .counts }
    }

    /// The title of a row: the cluster's, or "Visible" for a `visibility` of Hidden alone.
    static func title(of row: AttributeClusters.Row) -> String {
        switch row.kind {
        case .visibility:
            if row[Slot.opacity] == nil {
                localized("attributes.cluster.visible")
            } else {
                localized("attributes.cluster.opacity")
            }
        case .corners: localized("attributes.cluster.corners")
        case .border: localized("attributes.cluster.border")
        case .shadow: localized("attributes.cluster.shadow")
        case .geometry:
            geometryLabel(AttributeClusters.slotNames(of: .geometry).first { row[$0] != nil } ?? Slot.frame)
        case .sizing: ""
        case .autoLayout: localized("attributes.cluster.autoLayout")
        case .font: localized("attributes.cluster.font")
        case .lines: localized("attributes.cluster.lines")
        case .state: localized("attributes.cluster.state")
        case .scrolling: localized("attributes.cluster.scrolling")
        case .image: localized("attributes.cluster.image")
        case .indexPath: localized("attributes.cluster.indexPath")
        case .listCounts: localized("attributes.cluster.counts")
        }
    }

    /// The geometry's labels, by slot.
    static func geometryLabel(_ slot: String) -> String {
        switch slot {
        case Slot.frame: localized("attributes.cluster.frame")
        case Slot.position: localized("attributes.cluster.position")
        case Slot.anchor: localized("attributes.cluster.anchor")
        case Slot.bounds: localized("attributes.cluster.bounds")
        case Slot.zPosition: localized("attributes.cluster.z")
        default: localized("attributes.cluster.transform")
        }
    }

    /// What a chip of the `state` and `scrolling` clusters says.
    static func chipTitle(_ slot: String) -> String {
        switch slot {
        case Slot.enabled: localized("attributes.cluster.enabled")
        case Slot.selected: localized("attributes.cluster.selected")
        case Slot.highlighted: localized("attributes.cluster.highlighted")
        case Slot.paging: localized("attributes.cluster.paging")
        default: slot
        }
    }

    /// What a text of `row` says, or nil for nothing: `value` gives the value shown for a slot,
    /// and `written` the slots the row writes as text.
    static func text(
        _ role: Role, of row: AttributeClusters.Row, written: Set<String>, words: ClusterText.Words,
        value: (String) -> AttributeValue?
    ) -> String? {
        func string(_ slot: String) -> String? {
            if case .string(let text) = value(slot) { return text }
            return nil
        }
        switch role {
        case .textStyle:
            return string(Slot.textStyle).map(ClusterText.textStyle)
        case .drawn:
            return ClusterText.integer(value(Slot.drawn)).map {
                ClusterText.drawn($0, of: ClusterText.integer(value(Slot.count)))
            }
        case .truncated:
            guard case .bool(true) = value(Slot.truncated) else { return nil }
            return localized("attributes.cluster.truncated")
        case .imageName:
            return AttributeText.text(of: value(Slot.name))
        case .imageDetails:
            return ClusterText.image(
                size: written.contains(Slot.size) ? value(Slot.size) : nil,
                unit: row[Slot.size]?.unit ?? .unspecified,
                scale: written.contains(Slot.scale) ? value(Slot.scale) : nil,
                mode: written.contains(Slot.renderingMode) ? value(Slot.renderingMode) : nil)
        case .symbolConfiguration:
            return string(Slot.symbolConfiguration)
        // The row's only line: with no values it reads as a nil value does (P-ATTR-03).
        case .indexPath:
            return ClusterText.indexPath(
                section: ClusterText.integer(value(Slot.section)), item: ClusterText.integer(value(Slot.item)),
                words: words) ?? localized("attributes.value.none")
        case .counts:
            return ClusterText.counts(
                sections: ClusterText.integer(value(Slot.sections)), items: ClusterText.integer(value(Slot.items)),
                words: words) ?? localized("attributes.value.none")
        }
    }
}
