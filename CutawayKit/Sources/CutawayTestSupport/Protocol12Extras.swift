import CutawayWire

/// Attributes of protocol 1.2 that no fixture has: the `lines` cluster's `drawn` and
/// `truncated`, the `image`, `indexPath` and `listCounts` clusters, and references to several
/// layers, as a stack view's arranged subviews. Made after the fixtures' layer 3: the same
/// shape of attribute, a section, read-only where the value is computed. The IDs are only an
/// example, as the fixtures' are.
public enum Protocol12Extras {
    private static func attribute(
        _ id: String, _ title: String, _ value: AttributeValue?, _ kind: AttributeValueKind,
        cluster: String? = nil, slot: String? = nil, editable: Bool = false,
        section: AttributeSection = .content, unit: AttributeUnit = .unspecified
    ) -> Attribute {
        Attribute(
            id: id, title: title, value: value, editable: editable, valueKind: kind, section: section,
            cluster: cluster.map { AttributeCluster(name: $0, slot: slot ?? "") }, unit: unit)
    }

    /// The label's lines: 3 at most, 2 drawn, cut short.
    public static func lines(count: Int64? = 3, drawn: Int64? = 2, truncated: Bool? = true) -> [Attribute] {
        var attributes: [Attribute] = []
        if let count {
            attributes.append(attribute(
                "label.numberOfLines", "Lines", .integer(count), .integer, cluster: "lines", slot: "count",
                editable: true))
        }
        if let drawn {
            attributes.append(attribute(
                "label.drawnLineCount", "Lines Drawn", .integer(drawn), .integer, cluster: "lines", slot: "drawn"))
        }
        if let truncated {
            attributes.append(attribute(
                "label.isTruncated", "Truncated", .bool(truncated), .bool, cluster: "lines", slot: "truncated"))
        }
        return attributes
    }

    /// An image view's image: a symbol 28 by 27 points at 3x, drawn as a template.
    public static func image(configuration: Bool = true) -> [Attribute] {
        var attributes = [
            attribute(
                "imageView.imageName", "Image", .string("person.crop.circle.fill"), .string,
                cluster: "image", slot: "name"),
            attribute(
                "imageView.imageSize", "Image Size", .size(Size(width: 28, height: 27)), .size,
                cluster: "image", slot: "size", unit: .points),
            attribute("imageView.imageScale", "Image Scale", .double(3), .double, cluster: "image", slot: "scale"),
            attribute(
                "imageView.imageRenderingMode", "Rendering Mode",
                .enumeration(EnumValue(
                    value: 2, cases: ["automatic", "alwaysOriginal", "alwaysTemplate"],
                    caseName: "alwaysTemplate", caseValues: [0, 1, 2])),
                .enumeration, cluster: "image", slot: "renderingMode"),
        ]
        if configuration {
            attributes.append(attribute(
                "imageView.symbolConfiguration", "Symbol Configuration", .string("Body, Medium"), .string,
                cluster: "image", slot: "symbolConfiguration"))
        }
        return attributes
    }

    /// A cell's index path.
    public static func indexPath(section: Int64? = 0, item: Int64? = 3) -> [Attribute] {
        [
            section.map {
                attribute("cell.indexPath.section", "Section", .integer($0), .integer, cluster: "indexPath",
                          slot: "section")
            },
            item.map {
                attribute("cell.indexPath.item", "Item", .integer($0), .integer, cluster: "indexPath", slot: "item")
            },
        ].compactMap { $0 }
    }

    /// A list's numbers of sections and items.
    public static func listCounts(sections: Int64 = 3, items: Int64 = 16) -> [Attribute] {
        [
            attribute(
                "list.numberOfSections", "Sections", .integer(sections), .integer, cluster: "listCounts",
                slot: "sections"),
            attribute(
                "list.numberOfItems", "Items", .integer(items), .integer, cluster: "listCounts", slot: "items"),
        ]
    }

    /// A stack view's arranged subviews, by the layers that back them (P-ATTR-18), read-only.
    public static func arrangedSubviews(_ references: [ObjectReference]) -> Attribute {
        attribute(
            "stackView.arrangedSubviews", "Arranged Subviews", .references(references), .references)
    }

    /// The fixtures' layer 3 groups with `extra` at the end of its first group, the label's.
    public static func layerThree(adding extra: [Attribute]) throws -> [AttributeGroup] {
        var groups = try Fixtures.attributes(of: 3, scenario: "layer-details")
        guard let label = groups.firstIndex(where: { $0.className == "UILabel" }) else { return groups }
        groups[label].attributes += extra
        return groups
    }
}
