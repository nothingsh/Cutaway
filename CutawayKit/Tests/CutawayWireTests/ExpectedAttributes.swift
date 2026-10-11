import CutawayWire

/// Attributes of the fixtures, written out by hand from Protocol/fixtures/src and
/// Protocol/fixtures/README.md.
enum ExpectedAttributes {
    static let alignmentCases = ["left", "center", "right", "justified", "natural"]

    /// Layer 3 of `layer-details`, with the flags of protocol 0.3. The `set-attribute`
    /// scenario answers with the same groups, the text and the alignment changed.
    static func layer3(
        text: String = "Hello", alignment: Int64 = 1, alignmentName: String = "center"
    ) -> [AttributeGroup] {
        [
            AttributeGroup(id: "layer", title: "Layer", attributes: [
                Attribute(
                    id: "layer.frame", title: "Frame",
                    value: .rect(Rect(
                        origin: Point(x: 96.5, y: 108), size: Size(width: 200, height: 24))),
                    editable: false, valueKind: .rect),
                Attribute(
                    id: "layer.position", title: "Position", value: .point(Point(x: 196.5, y: 120)),
                    editable: true, valueKind: .point),
                Attribute(
                    id: "layer.shadowOffset", title: "Shadow Offset",
                    value: .size(Size(width: 0, height: -3)), editable: true, valueKind: .size),
                Attribute(
                    id: "layer.opacity", title: "Opacity", value: .double(1), editable: true,
                    valueKind: .double),
                Attribute(
                    id: "layer.hidden", title: "Hidden", value: .bool(false), editable: true,
                    valueKind: .bool),
                Attribute(
                    id: "layer.backgroundColor", title: "Background Color", value: nil,
                    editable: true, acceptsNil: true, valueKind: .color),
                Attribute(
                    id: "layer.borderColor", title: "Border Color",
                    value: .color(Color(red: 0, green: 0, blue: 0, alpha: 1)), editable: true,
                    acceptsNil: true, valueKind: .color),
                Attribute(
                    id: "layer.transform", title: "Transform", value: .transform(.identity),
                    editable: true, valueKind: .transform),
            ]),
            AttributeGroup(id: "label", title: "Label", attributes: [
                Attribute(
                    id: "label.text", title: "Text", value: .string(text), editable: true,
                    acceptsNil: true, valueKind: .string),
                Attribute(
                    id: "label.numberOfLines", title: "Number Of Lines", value: .integer(1),
                    editable: true, valueKind: .integer),
                Attribute(
                    id: "label.textAlignment", title: "Text Alignment",
                    value: .enumeration(EnumValue(
                        value: alignment, cases: alignmentCases, caseName: alignmentName,
                        caseValues: [0, 1, 2, 3, 4])),
                    editable: true, valueKind: .enumeration),
            ]),
            AttributeGroup(id: "view", title: "View", attributes: [
                Attribute(
                    id: "view.layoutMargins", title: "Layout Margins",
                    value: .insets(Insets(top: 8, left: 8, bottom: 8, right: 8)), editable: true,
                    valueKind: .insets),
            ]),
        ]
    }

    /// Layer 4 of `set-attribute`, which appears only there.
    static func layer4(opacity: Double, background: Color?) -> [AttributeGroup] {
        [
            AttributeGroup(id: "layer", title: "Layer", attributes: [
                Attribute(
                    id: "layer.opacity", title: "Opacity", value: .double(opacity),
                    editable: true, valueKind: .double),
                Attribute(
                    id: "layer.cornerRadius", title: "Corner Radius", value: .double(12),
                    editable: true, valueKind: .double),
                Attribute(
                    id: "layer.backgroundColor", title: "Background Color",
                    value: background.map { .color($0) }, editable: true, acceptsNil: true,
                    valueKind: .color),
            ]),
            AttributeGroup(id: "view", title: "View", attributes: [
                Attribute(
                    id: "view.alpha", title: "Alpha", value: .double(opacity), editable: true,
                    valueKind: .double),
                Attribute(
                    id: "view.tintColor", title: "Tint Color", value: nil, editable: true,
                    acceptsNil: true, valueKind: .color),
            ]),
        ]
    }
}
