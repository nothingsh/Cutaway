import AppKit
import CutawayModel
import CutawayProjects
import CutawayWire

/// Where the classes of a layer are declared in the app's project folder (C-SRC-03): its
/// view's, its view controller's and its own. A class of the system is not looked for.
struct OpenableClasses: Equatable {
    var view: [SourceLocation] = []
    var controller: [SourceLocation] = []
    var layer: [SourceLocation] = []

    static let none = Self()

    init() {}

    init(_ node: LayerNode?, in index: ProjectIndex?) {
        guard let node, let index else { return }
        func locations(_ names: [String?], _ origin: ClassOrigin) -> [SourceLocation] {
            guard origin != .system, let name = names.compactMap({ $0 }).first(where: { !$0.isEmpty })
            else { return [] }
            return index.locations(ofClass: name)
        }
        view = locations([node.viewDisplayClassName, node.viewClassName], node.viewClassOrigin)
        controller = locations(
            [node.viewControllerDisplayClassName, node.viewControllerClassName], node.viewControllerClassOrigin)
        layer = locations([node.displayClassName, node.className], node.layerClassOrigin)
    }

    /// What the menus and ⌥⌘O open: the first class found of the view, the view controller
    /// and the layer.
    var first: [SourceLocation] {
        [view, controller, layer].first { !$0.isEmpty } ?? []
    }

    var isEmpty: Bool { first.isEmpty }
}

/// The choice of a declaration among several (C-SRC-03): one menu item for each, the file and
/// line with its folder under it.
@MainActor
enum DeclarationChoices {
    static let itemIdentifier = NSUserInterfaceItemIdentifier("openInXcode.place")

    /// The title of a place: "HomeHeaderView.swift:14".
    static func title(of location: SourceLocation) -> String {
        "\(location.file.lastPathComponent):\(location.line)"
    }

    /// The tooltip of an Open in Xcode button.
    static func toolTip(for locations: [SourceLocation]) -> String {
        locations.count == 1
            ? localized("source.openInXcode.place", title(of: locations[0]))
            : localized("source.openInXcode.places", locations.count)
    }

    /// The items choosing among `locations`, each sending `action` to `target` with its
    /// location as the represented object.
    static func items(for locations: [SourceLocation], target: AnyObject, action: Selector) -> [NSMenuItem] {
        locations.map { location in
            let item = NSMenuItem(title: title(of: location), action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = location
            item.identifier = itemIdentifier
            item.toolTip = location.file.path
            if #available(macOS 14.4, *), !location.folder.isEmpty {
                item.subtitle = location.folder
            }
            return item
        }
    }
}
