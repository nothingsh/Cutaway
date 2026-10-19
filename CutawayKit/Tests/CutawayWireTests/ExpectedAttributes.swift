import CutawayWire

/// Attributes of the fixtures, written out by hand from Protocol/fixtures/src and
/// Protocol/fixtures/README.md.
enum ExpectedAttributes {
    static let alignmentCases = ["left", "center", "right", "justified", "natural"]

    /// No limit on one side or the other: what `limits` name with `has_minimum` alone.
    static let atLeastZero = NumberLimit(minimum: 0)
    static let zeroToOne = NumberLimit(minimum: 0, maximum: 1)

    /// Layer 3 of `layer-details`, with the flags of protocol 0.3 and the fields of 1.1 and 1.2. The
    /// `set-attribute` scenario answers with the same groups, the text and the alignment
    /// changed.
    static func layer3(
        text: String = "Hello", alignment: Int64 = 1, alignmentName: String = "center"
    ) -> [AttributeGroup] {
        [
            layer3Layer(),
            layer3Label(text: text, alignment: alignment, alignmentName: alignmentName),
            layer3View(),
        ]
    }

    private static func layer3Layer() -> AttributeGroup {
        AttributeGroup(id: "layer", title: "Layer", attributes: [
            Attribute(
                id: "layer.frame", title: "Frame",
                value: .rect(Rect(
                    origin: Point(x: 96.5, y: 108), size: Size(width: 200, height: 24))),
                editable: false, valueKind: .rect, section: .layout,
                cluster: AttributeCluster(name: "geometry", slot: "frame"), unit: .points),
            Attribute(
                id: "layer.bounds", title: "Bounds",
                value: .rect(Rect(origin: .zero, size: Size(width: 200, height: 24))),
                editable: true, valueKind: .rect, section: .layout,
                limits: [NumberLimit(), NumberLimit(), atLeastZero, atLeastZero],
                cluster: AttributeCluster(name: "geometry", slot: "bounds"), unit: .points),
            Attribute(
                id: "layer.position", title: "Position", value: .point(Point(x: 196.5, y: 120)),
                editable: true, valueKind: .point, section: .layout,
                cluster: AttributeCluster(name: "geometry", slot: "position"), unit: .points),
            Attribute(
                id: "layer.shadowOpacity", title: "Shadow Opacity", value: .double(0),
                editable: true, valueKind: .double, section: .appearance, limits: [zeroToOne],
                cluster: AttributeCluster(name: "shadow", slot: "opacity"), unit: .fraction),
            Attribute(
                id: "layer.shadowOffset", title: "Shadow Offset",
                value: .size(Size(width: 0, height: -3)), editable: true, valueKind: .size,
                section: .appearance, cluster: AttributeCluster(name: "shadow", slot: "offset"),
                inactiveCause: "layer.shadowOpacity", unit: .points),
            Attribute(
                id: "layer.borderWidth", title: "Border Width", value: .double(0),
                editable: true, valueKind: .double, section: .appearance, limits: [atLeastZero],
                cluster: AttributeCluster(name: "border", slot: "width"), unit: .points),
            Attribute(
                id: "layer.borderColor", title: "Border Color",
                value: .color(Color(red: 0, green: 0, blue: 0, alpha: 1)), editable: true,
                acceptsNil: true, valueKind: .color, section: .appearance,
                cluster: AttributeCluster(name: "border", slot: "color"),
                inactiveCause: "layer.borderWidth"),
            Attribute(
                id: "layer.transform", title: "Transform", value: .transform(.identity),
                editable: true, valueKind: .transform, section: .layout,
                cluster: AttributeCluster(name: "geometry", slot: "transform")),
        ], className: "CALayer")
    }

    private static func layer3Label(
        text: String, alignment: Int64, alignmentName: String
    ) -> AttributeGroup {
        AttributeGroup(id: "label", title: "Label", attributes: [
            Attribute(
                id: "label.text", title: "Text", value: .string(text), editable: true,
                acceptsNil: true, valueKind: .string, section: .content),
            Attribute(
                id: "label.fontSize", title: "Font Size", value: .double(17), editable: true,
                valueKind: .double, section: .content,
                limits: [NumberLimit(minimum: 0, minimumIsExclusive: true)],
                cluster: AttributeCluster(name: "font", slot: "size"), unit: .points),
            Attribute(
                id: "label.fontTextStyle", title: "Text Style", value: .string("body"),
                editable: false, valueKind: .string, section: .content,
                cluster: AttributeCluster(name: "font", slot: "textStyle")),
            Attribute(
                id: "label.adjustsFontForContentSizeCategory", title: "Adjusts to Text Size",
                value: .bool(true), editable: true, valueKind: .bool, section: .content,
                cluster: AttributeCluster(name: "font", slot: "scalable")),
            Attribute(
                id: "label.numberOfLines", title: "Lines", value: .integer(1),
                editable: true, valueKind: .integer, section: .content, limits: [atLeastZero],
                cluster: AttributeCluster(name: "lines", slot: "count")),
            Attribute(
                id: "label.textAlignment", title: "Text Alignment",
                value: .enumeration(EnumValue(
                    value: alignment, cases: alignmentCases, caseName: alignmentName,
                    caseValues: [0, 1, 2, 3, 4])),
                editable: true, valueKind: .enumeration, section: .content),
        ], className: "UILabel")
    }

    private static func layer3View() -> AttributeGroup {
        AttributeGroup(id: "view", title: "View", attributes: [
            Attribute(
                id: "view.tag", title: "Tag", value: .integer(0), editable: true,
                valueKind: .integer, section: .identity),
            Attribute(
                id: "view.isHidden", title: "Hidden", value: .bool(false), editable: true,
                valueKind: .bool, section: .appearance,
                cluster: AttributeCluster(name: "visibility", slot: "hidden")),
            Attribute(
                id: "view.alpha", title: "Opacity", value: .double(1), editable: true,
                valueKind: .double, section: .appearance, limits: [zeroToOne],
                cluster: AttributeCluster(name: "visibility", slot: "opacity"), unit: .fraction),
            Attribute(
                id: "view.backgroundColor", title: "Background", value: nil,
                editable: true, acceptsNil: true, valueKind: .color, section: .appearance),
            Attribute(
                id: "view.tintColor", title: "Tint",
                value: .color(Color(red: 0, green: 0.47843137, blue: 1, alpha: 1)),
                editable: true, acceptsNil: true, valueKind: .color, section: .appearance,
                systemColorName: "systemBlue",
                appearanceColors: AppearanceColors(
                    light: Color(red: 0, green: 0.47843137, blue: 1, alpha: 1),
                    dark: Color(red: 0.039215688, green: 0.5176471, blue: 1, alpha: 1))),
            Attribute(
                id: "view.isUserInteractionEnabled", title: "User Interaction",
                value: .bool(false), editable: true, valueKind: .bool, section: .behavior),
            Attribute(
                id: "view.layoutMargins", title: "Layout Margins",
                value: .insets(Insets(top: 8, left: 8, bottom: 8, right: 8)), editable: true,
                valueKind: .insets, section: .layout, unit: .points),
            Attribute(
                id: "view.accessibilityLabel", title: "Label", value: .string("Welcome"),
                editable: true, acceptsNil: true, valueKind: .string, section: .accessibility),
        ], className: "UIView")
    }

    /// Layer 6 of `layer-details`, asked for attributes only: two references (protocol 1.2,
    /// P-ATTR-18).
    static func layer6() -> [AttributeGroup] {
        let recognizers = ["UIScrollViewDelayedTouchesBeganGestureRecognizer", "UIScrollViewPanGestureRecognizer"]
        return [
            AttributeGroup(id: "scrollView", title: "Scroll View", attributes: [
                Attribute(
                    id: "scrollView.delegate", title: "Delegate",
                    value: .references([ObjectReference(
                        layerID: 2, className: "Demo.HomeViewController",
                        displayClassName: "HomeViewController")]),
                    valueKind: .references, section: .content),
            ], className: "UIScrollView"),
            AttributeGroup(id: "view", title: "View", attributes: [
                Attribute(
                    id: "view.gestureRecognizers", title: "Gesture Recognizers",
                    value: .references(recognizers.map {
                        ObjectReference(layerID: nil, className: $0, displayClassName: $0)
                    }),
                    valueKind: .references, section: .behavior),
            ], className: "UIView"),
        ]
    }

    /// Layer 4 of `set-attribute`, which appears only there. It backs a view, so it has
    /// `view.alpha` and `view.backgroundColor`, and no `layer.opacity` or
    /// `layer.backgroundColor` (P-ATTR-11).
    static func layer4(opacity: Double, background: Color?) -> [AttributeGroup] {
        [
            AttributeGroup(id: "layer", title: "Layer", attributes: [
                Attribute(
                    id: "layer.cornerRadius", title: "Corner Radius", value: .double(12),
                    editable: true, valueKind: .double, section: .appearance, limits: [atLeastZero],
                    cluster: AttributeCluster(name: "corners", slot: "radius"), unit: .points),
            ], className: "CALayer"),
            AttributeGroup(id: "view", title: "View", attributes: [
                Attribute(
                    id: "view.alpha", title: "Opacity", value: .double(opacity), editable: true,
                    valueKind: .double, section: .appearance, limits: [zeroToOne],
                    cluster: AttributeCluster(name: "visibility", slot: "opacity"), unit: .fraction),
                Attribute(
                    id: "view.clipsToBounds", title: "Clips to Bounds", value: .bool(true),
                    editable: true, valueKind: .bool, section: .appearance,
                    cluster: AttributeCluster(name: "corners", slot: "clip")),
                Attribute(
                    id: "view.backgroundColor", title: "Background",
                    value: background.map { .color($0) }, editable: true, acceptsNil: true,
                    valueKind: .color, section: .appearance),
                Attribute(
                    id: "view.tintColor", title: "Tint", value: nil, editable: true,
                    acceptsNil: true, valueKind: .color, section: .appearance),
            ], className: "UIView"),
        ]
    }
}
