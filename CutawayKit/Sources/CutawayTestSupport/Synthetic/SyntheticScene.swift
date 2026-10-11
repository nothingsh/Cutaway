import CutawayWire
import Foundation

/// How the screens of an app-shaped scene are made (C-MOCK-03): a window holding one screen
/// after another, all in the same place, each with full-screen containers, a navigation bar
/// and a list of cells. Every cell has a content view with an icon, a title, a subtitle and an
/// accessory, a text layer in each label, and a separator: nine layers.
public struct AppShape: Equatable, Sendable {
    /// Full-screen views each screen nests before its content.
    public var containersPerScreen: Int
    /// Buttons in each screen's navigation bar.
    public var barItems: Int
    /// Cells in each screen's list, one below the other; those beyond the screen are there
    /// too, as a list keeps a few it prepared.
    public var cellsPerScreen: Int

    public init(containersPerScreen: Int = 4, barItems: Int = 6, cellsPerScreen: Int = 50) {
        self.containersPerScreen = containersPerScreen
        self.barItems = barItems
        self.cellsPerScreen = cellsPerScreen
    }
}

/// A made-up app of any size, the same for the same parameters (C-MOCK-03). Nothing is
/// random: positions, class names and colours follow from each layer's place, so the frames
/// it gives encode to the same bytes every time.
public struct SyntheticScene: Sendable {
    public enum Shape: Equatable, Sendable {
        /// One chain: each layer inside the one before, all full-screen.
        case deep
        /// A window holding small leaves that do not overlap.
        case wide
        case app(AppShape)
    }

    /// What screenshots the layers have.
    public enum ImagePixels: Equatable, Sendable {
        case none
        /// Every image of this many pixels.
        case fixed(width: Int, height: Int)
        /// The layer's size in points times `scale`, at least one pixel each way.
        case layerSize(scale: Double)
    }

    public var layerCount: Int
    public var shape: Shape
    public var imagePixels: ImagePixels
    public var attributes: Bool
    public var constraints: Bool

    public init(
        layerCount: Int, shape: Shape, imagePixels: ImagePixels = .none, attributes: Bool = false,
        constraints: Bool = false
    ) {
        self.layerCount = layerCount
        self.shape = shape
        self.imagePixels = imagePixels
        self.attributes = attributes
        self.constraints = constraints
    }

    /// The app's icon: one colour.
    public static let icon = AppIcon(
        image: .solid(pixelWidth: 60, pixelHeight: 60, bgra: 0xFF30_80F0))

    /// The screen the window covers, in points.
    public static let screen = Size(width: 393, height: 852)

    public func hierarchy() -> Hierarchy {
        let layers = build()
        return Hierarchy(nodes: layers.map(\.node), keyWindowID: layers.first?.node.id ?? 0)
    }

    /// Every layer's screenshots, attributes and constraints, as the parameters say.
    public func details() -> [UInt64: LayerDetail] {
        let layers = build()
        var images = ImageMaker(pixels: imagePixels)
        var constraintsOf: [UInt64: [LayoutConstraint]] = [:]
        if constraints {
            for layer in layers {
                guard let pinned = layer.pinnedTo else { continue }
                for made in Self.pins(layer, to: pinned) {
                    constraintsOf[layer.node.id, default: []].append(made)
                    constraintsOf[pinned, default: []].append(made)
                }
            }
        }
        var details: [UInt64: LayerDetail] = [:]
        details.reserveCapacity(layers.count)
        for (index, layer) in layers.enumerated() {
            let image = images.image(for: layer, colour: index)
            details[layer.node.id] = LayerDetail(
                layerID: layer.node.id, status: .ok, solo: image, group: image,
                attributeGroups: attributes ? Self.attributeGroups(of: layer) : [],
                constraints: constraintsOf[layer.node.id] ?? [])
        }
        return details
    }

    /// Answers requests for this scene; edits are applied (`MockResponder.Editing.apply`).
    public func responder() -> MockResponder {
        var responder = MockResponder(icon: Self.icon, hierarchy: hierarchy(), details: details())
        responder.editing = .apply
        return responder
    }

    // MARK: - Building

    struct Layer {
        var node: LayerNode
        /// Where it is in its parent, in points.
        var frame: Rect
        /// The content view a cell's subview is pinned to by its leading and top edges.
        var pinnedTo: UInt64?
    }

    private func build() -> [Layer] {
        var builder = Builder(limit: max(layerCount, 0))
        switch shape {
        case .deep:
            var parent: UInt64 = 0
            while !builder.isFull {
                parent = builder.add(
                    parent, "UIView", x: 0, y: 0, width: Self.screen.width,
                    height: Self.screen.height) ?? parent
            }
        case .wide:
            let columns = max(Int(Double(layerCount).squareRoot().rounded(.up)), 1)
            let side = Double(columns) * 10
            guard let window = builder.add(0, "UIWindow", x: 0, y: 0, width: side, height: side)
            else { break }
            var index = 0
            while !builder.isFull {
                builder.add(
                    window, "UIView", x: Double(index % columns) * 10,
                    y: Double(index / columns) * 10, width: 8, height: 8)
                index += 1
            }
        case .app(let shape):
            Self.buildApp(shape, into: &builder)
        }
        return builder.layers
    }

    private static func buildApp(_ shape: AppShape, into builder: inout Builder) {
        let width = screen.width, height = screen.height
        guard let window = builder.add(0, "UIWindow", x: 0, y: 0, width: width, height: height)
        else { return }
        while !builder.isFull {
            guard var parent = builder.add(
                window, "UITransitionView", x: 0, y: 0, width: width, height: height)
            else { return }
            for _ in 0..<shape.containersPerScreen {
                parent = builder.add(parent, "UIView", x: 0, y: 0, width: width, height: height)
                    ?? parent
            }
            if let bar = builder.add(parent, "UINavigationBar", x: 0, y: 0, width: width, height: 96) {
                for item in 0..<shape.barItems {
                    builder.add(bar, "UIButton", x: 8 + Double(item) * 62, y: 50, width: 54, height: 40)
                }
            }
            guard let list = builder.add(
                parent, "UITableView", x: 0, y: 0, width: width, height: height)
            else { return }
            for row in 0..<shape.cellsPerScreen {
                guard let cell = builder.add(
                    list, "UITableViewCell", x: 0, y: 96 + Double(row) * 60, width: width,
                    height: 60)
                else { return }
                guard let content = builder.add(
                    cell, "UITableViewCellContentView", x: 0, y: 0, width: width, height: 60)
                else { return }
                builder.add(content, "UIImageView", x: 16, y: 10, width: 40, height: 40, pinnedTo: content)
                for (y, h) in [(8.0, 20.0), (32.0, 16.0)] {
                    if let label = builder.add(
                        content, "UILabel", x: 64, y: y, width: 260, height: h, pinnedTo: content)
                    {
                        builder.addLayer(label, "_UILabelLayer", x: 0, y: 0, width: 260, height: h)
                    }
                }
                builder.add(content, "UIImageView", x: 361, y: 22, width: 12, height: 16, pinnedTo: content)
                builder.add(cell, "_UITableViewCellSeparatorView", x: 16, y: 59.5, width: 377, height: 0.5)
            }
        }
    }

    /// Adds layers in pre-order until the count is reached; each add after that is nil.
    struct Builder {
        let limit: Int
        var layers: [Layer] = []

        init(limit: Int) {
            self.limit = limit
            layers.reserveCapacity(limit)
        }

        var isFull: Bool { layers.count >= limit }

        /// A layer that backs a view of this class.
        @discardableResult
        mutating func add(
            _ parent: UInt64, _ viewClass: String, x: Double, y: Double, width: Double,
            height: Double, pinnedTo: UInt64? = nil
        ) -> UInt64? {
            append(
                parent, layerClass: "CALayer", viewClass: viewClass,
                frame: Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height)),
                pinnedTo: pinnedTo)
        }

        /// A layer that backs no view.
        @discardableResult
        mutating func addLayer(
            _ parent: UInt64, _ layerClass: String, x: Double, y: Double, width: Double,
            height: Double
        ) -> UInt64? {
            append(
                parent, layerClass: layerClass, viewClass: nil,
                frame: Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height)),
                pinnedTo: nil)
        }

        private mutating func append(
            _ parent: UInt64, layerClass: String, viewClass: String?, frame: Rect,
            pinnedTo: UInt64?
        ) -> UInt64? {
            guard !isFull else { return nil }
            let id = UInt64(layers.count + 1)
            let node = LayerNode(
                id: id, parentID: parent, className: layerClass, displayClassName: layerClass,
                viewClassName: viewClass, viewDisplayClassName: viewClass,
                bounds: Rect(origin: .zero, size: frame.size),
                position: Point(
                    x: frame.origin.x + frame.size.width / 2,
                    y: frame.origin.y + frame.size.height / 2),
                anchorPoint: Point(x: 0.5, y: 0.5), transform: .identity, zPosition: 0,
                isHidden: false, opacity: 1, masksToBounds: false)
            layers.append(Layer(node: node, frame: frame, pinnedTo: pinnedTo))
            return id
        }
    }

    // MARK: - Details

    /// Makes each image once for its size and colour and hands the same data out again.
    private struct ImageMaker {
        let pixels: ImagePixels
        var made: [ImageKey: EncodedImage] = [:]

        struct ImageKey: Hashable {
            var width: Int, height: Int, colour: Int
        }

        /// Opaque colours, premultiplied BGRA.
        static let palette: [UInt32] = [
            0xFFE0_6040, 0xFF40_A0E0, 0xFF60_C060, 0xFFF0_C030, 0xFFA0_60D0, 0xFF30_B0B0,
            0xFFD0_5090, 0xFF80_8080, 0xFF20_60C0, 0xFFC0_9060, 0xFF50_7030, 0xFFE0_E0E0,
        ]

        mutating func image(for layer: Layer, colour index: Int) -> EncodedImage? {
            let width: Int, height: Int, scale: Float
            switch pixels {
            case .none:
                return nil
            case .fixed(let w, let h):
                (width, height, scale) = (w, h, 1)
            case .layerSize(let s):
                width = max(Int((layer.frame.size.width * s).rounded(.up)), 1)
                height = max(Int((layer.frame.size.height * s).rounded(.up)), 1)
                scale = Float(s)
            }
            let key = ImageKey(width: width, height: height, colour: index % Self.palette.count)
            if var image = made[key] {
                image.scale = scale
                return image
            }
            var image = EncodedImage.solid(
                pixelWidth: width, pixelHeight: height, bgra: Self.palette[key.colour])
            image.scale = scale
            made[key] = image
            return image
        }
    }

    /// Leading and top, to the content view, at the subview's offset.
    private static func pins(_ layer: Layer, to content: UInt64) -> [LayoutConstraint] {
        let id = layer.node.id
        return [
            (LayoutAttribute.leading, layer.frame.origin.x),
            (LayoutAttribute.top, layer.frame.origin.y),
        ].enumerated().map { offset, pin in
            LayoutConstraint(
                id: id * 2 + UInt64(offset), className: "NSLayoutConstraint", identifier: nil,
                firstItem: .view(layerID: id), firstAttribute: pin.0, relation: .equal,
                secondItem: .view(layerID: content), secondAttribute: pin.0, multiplier: 1,
                constant: pin.1, priority: 1000, status: .satisfied)
        }
    }

    /// The groups of the `layer-details` fixture's layer 3, with this layer's own values;
    /// labels also get the label group, other views the view group.
    static func attributeGroups(of layer: Layer) -> [AttributeGroup] {
        let node = layer.node
        let colour = Double(node.id % 7) / 7
        var groups = [
            AttributeGroup(id: "layer", title: "Layer", attributes: [
                Attribute(
                    id: "layer.frame", title: "Frame", value: .rect(layer.frame), valueKind: .rect),
                Attribute(
                    id: "layer.position", title: "Position", value: node.position.map { .point($0) },
                    editable: true, valueKind: .point),
                Attribute(
                    id: "layer.opacity", title: "Opacity", value: .double(Double(node.opacity)),
                    editable: true, valueKind: .double),
                Attribute(
                    id: "layer.hidden", title: "Hidden", value: .bool(node.isHidden),
                    editable: true, valueKind: .bool),
                Attribute(
                    id: "layer.backgroundColor", title: "Background Color",
                    value: .color(Color(red: Float(colour), green: 0.5, blue: 0.5, alpha: 1)),
                    editable: true, acceptsNil: true, valueKind: .color),
                Attribute(
                    id: "layer.borderColor", title: "Border Color",
                    value: .color(Color(red: 0, green: 0, blue: 0, alpha: 1)), editable: true,
                    acceptsNil: true, valueKind: .color),
                Attribute(
                    id: "layer.transform", title: "Transform", value: .transform(.identity),
                    editable: true, valueKind: .transform),
            ]),
        ]
        if node.viewClassName == "UILabel" {
            groups.append(AttributeGroup(id: "label", title: "Label", attributes: [
                Attribute(
                    id: "label.text", title: "Text", value: .string("Label \(node.id)"),
                    editable: true, acceptsNil: true, valueKind: .string),
                Attribute(
                    id: "label.numberOfLines", title: "Number Of Lines", value: .integer(1),
                    editable: true, valueKind: .integer),
                Attribute(
                    id: "label.textAlignment", title: "Text Alignment",
                    value: .enumeration(EnumValue(
                        value: 4, cases: ["left", "center", "right", "justified", "natural"],
                        caseName: "natural", caseValues: [0, 1, 2, 3, 4])),
                    editable: true, valueKind: .enumeration),
            ]))
        } else if node.viewClassName != nil {
            groups.append(AttributeGroup(id: "view", title: "View", attributes: [
                Attribute(
                    id: "view.layoutMargins", title: "Layout Margins",
                    value: .insets(Insets(top: 8, left: 8, bottom: 8, right: 8)), editable: true,
                    valueKind: .insets),
            ]))
        }
        return groups
    }
}
