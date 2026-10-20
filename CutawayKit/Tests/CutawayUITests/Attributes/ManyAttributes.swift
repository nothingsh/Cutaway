import AppKit
import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// An attribute panel over a layer with very many attributes (C-SCALE-03): layer 3 of the
/// fixtures' app with `groups` groups of `perGroup` numbers, in a window 300 by 600.
@MainActor
final class ManyAttributes {
    let session: Session
    let model: InspectionStore
    let controller: AttributesViewController
    let window: NSWindow

    var list: NSScrollView { controller.list }
    var document: NSView { controller.list.documentView ?? NSView() }
    var visible: NSRect { controller.list.contentView.bounds }

    static func groups(_ groups: Int, of perGroup: Int) -> [AttributeGroup] {
        (0..<groups).map { group in
            AttributeGroup(
                id: "group\(group)", title: "Group \(group)",
                attributes: (0..<perGroup).map { index in
                    Attribute(
                        id: "a\(group).\(index)", title: "Attribute \(group).\(index)",
                        value: .double(Double(index)), editable: true, valueKind: .double)
                })
        }
    }

    init(groups: [AttributeGroup], editing: MockResponder.Editing = .refuse) async throws {
        var responder = try MockResponder.demo()
        responder.editing = editing
        var detail = try XCTUnwrap(responder.details[3])
        detail.attributeGroups = groups
        responder.details[3] = detail
        let server = try await MockServer.start(
            script: MockScript(steps: try MockScript.fixtures("handshake").steps + [.respond(responder)]))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        self.model = model
        model.enter()
        let listed = await Wait.until { await model.tree.count == 14 }
        XCTAssertTrue(listed)
        let layer = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: layer,
            connection: model.$connection.eraseToAnyPublisher(), loadingDelay: 0)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        // Kept by this object: closing must not release it as well.
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.layoutIfNeeded()
    }

    /// Whether the store has the layer's attributes.
    var isLoaded: Bool {
        if case .loaded = model.attributes.state { return true }
        return false
    }

    /// How many pages in view are not built.
    var unbuiltInView: Int {
        controller.lazyParts.reduce(0) { $0 + $1.pagesNotBuilt(in: visible, of: document) }
    }

    /// Selects layer 3 and waits until what is in view is built.
    @discardableResult
    func select() async -> Bool {
        model.select(3)
        return await Wait.untilOnMain(within: .seconds(20)) {
            window.layoutIfNeeded()
            return isLoaded && !controller.attributeRows.isEmpty && unbuiltInView == 0
        }
    }

    /// Scrolls the list so that the top of what it shows is `y` from the document's top.
    func scroll(to y: CGFloat) {
        let height = document.frame.height
        let origin = document.isFlipped ? y : height - y - visible.height
        list.contentView.scroll(to: list.contentView.constrainBoundsRect(
            NSRect(origin: NSPoint(x: 0, y: origin), size: visible.size)).origin)
        list.reflectScrolledClipView(list.contentView)
        // What the next turn of the run loop does after a scroll.
        controller.arrangePages()
        window.layoutIfNeeded()
    }

    /// The titles of the rows built in view, top to bottom.
    var titlesInView: [String] {
        controller.attributeRows.map(\.row)
            .filter { !$0.isHiddenOrHasHiddenAncestor && $0.convert($0.bounds, to: document).intersects(visible) }
            .sorted { $0.convert($0.bounds, to: document).minY < $1.convert($1.bounds, to: document).minY }
            .map(\.title)
    }

    func close() async {
        model.leave()
        window.close()
        await session.close()
    }
}
