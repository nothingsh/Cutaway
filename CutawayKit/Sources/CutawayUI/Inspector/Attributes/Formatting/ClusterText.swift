import CutawayWire
import Foundation

/// How the compound rows of protocol 1.2's clusters read (C-ATTR-27): a text style by UIKit's
/// name for it, the lines drawn, an image's size, scale and rendering mode, an index path and a
/// list's counts. Values only: which attribute is which comes from the cluster's slots.
enum ClusterText {
    /// Whether a list counts rows or items: a table's item is its row (P-ATTR-12), and the
    /// panel knows a table by the view's base class (P-HIER-17).
    struct Words: Equatable {
        var rows: Bool

        init(viewBaseClassName: String?) {
            rows = viewBaseClassName == "UITableViewCell" || viewBaseClassName == "UITableView"
        }
    }

    /// UIKit's text styles by the names in both of their spellings, the case's
    /// ("largeTitle") and the raw value's ("UICTFontTextStyleTitle1"), and as Xcode shows them.
    private static let textStyles: [String: String] = [
        "extraLargeTitle": "Extra Large Title", "extraLargeTitle2": "Extra Large Title 2",
        "largeTitle": "Large Title", "title1": "Title 1", "title2": "Title 2", "title3": "Title 3",
        "headline": "Headline", "subheadline": "Subheadline", "body": "Body", "callout": "Callout",
        "footnote": "Footnote", "caption1": "Caption 1", "caption2": "Caption 2",
    ]

    /// "Body" for "body" or "UICTFontTextStyleBody"; a name UIKit does not have, as it came.
    static func textStyle(_ name: String) -> String {
        var key = name
        let prefix = "UICTFontTextStyle"
        if key.hasPrefix(prefix) {
            key = String(key.dropFirst(prefix.count))
            // "Title1" → "title1", "ExtraLargeTitle2" → "extraLargeTitle2".
            key = key.prefix(1).lowercased() + key.dropFirst()
        }
        // The raw value of `largeTitle` is "UICTFontTextStyleTitle0".
        if key == "title0" { key = "largeTitle" }
        if key == "emphasizedTitle0" { key = "extraLargeTitle" }
        return textStyles[key] ?? name
    }

    /// "Drawn 2 of 3", or "Drawn 2" without a limit (0) or without the number of lines.
    static func drawn(_ drawn: Int64, of count: Int64?) -> String {
        guard let count, count > 0 else { return localized("attributes.cluster.drawn", String(drawn)) }
        return localized("attributes.cluster.drawnOf", String(drawn), String(count))
    }

    /// "28 × 27 pt · @3x · alwaysTemplate", leaving out what is missing; nil for nothing.
    static func image(size: AttributeValue?, unit: AttributeUnit, scale: AttributeValue?,
                      mode: AttributeValue?) -> String?
    {
        var parts: [String] = []
        if case .size(let size) = size {
            let text = "\(AttributeText.number(size.width)) × \(AttributeText.number(size.height))"
            parts.append(unit == .points ? text + " pt" : text)
        }
        if let scale = number(scale) { parts.append("@" + AttributeText.number(scale) + "x") }
        if let mode { parts.append(AttributeText.text(of: mode)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Section 0 · Item 3", "Section 0 · Row 3"; one of them when the other is missing.
    static func indexPath(section: Int64?, item: Int64?, words: Words) -> String? {
        let parts = [
            section.map { localized("attributes.cluster.section", String($0)) },
            item.map {
                words
                    .rows ? localized("attributes.cluster.row", String($0)) :
                    localized("attributes.cluster.item", String($0))
            },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "3 sections · 16 items", "1 section · 1 row".
    static func counts(sections: Int64?, items: Int64?, words: Words) -> String? {
        let parts = [
            sections.map { localized("attributes.cluster.sections", Int($0)) },
            items
                .map {
                    words
                        .rows ? localized("attributes.cluster.rows", Int($0)) :
                        localized("attributes.cluster.items", Int($0))
                },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func integer(_ value: AttributeValue?) -> Int64? {
        if case .integer(let integer) = value { return integer }
        return nil
    }

    static func number(_ value: AttributeValue?) -> Double? {
        switch value {
        case .integer(let integer): Double(integer)
        case .double(let double): double
        default: nil
        }
    }
}
