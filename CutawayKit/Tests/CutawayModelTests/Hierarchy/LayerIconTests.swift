import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-HIER-11: what a layer's icon says — its kind, the glyph of its class, and whether the class
/// is the app's own.
final class LayerIconTests: XCTestCase {
    private func node(
        parent: UInt64 = 1, view: String? = nil, viewDisplay: String? = nil,
        layer: String = "CALayer", controller: String? = nil
    ) -> LayerNode {
        LayerNode(
            id: 2, parentID: parent, className: layer, displayClassName: layer,
            viewClassName: view, viewDisplayClassName: viewDisplay ?? view, bounds: nil,
            position: nil, anchorPoint: nil, transform: nil, zPosition: 0, isHidden: false,
            opacity: 1, masksToBounds: false, viewControllerClassName: controller,
            viewControllerDisplayClassName: controller)
    }

    private func icon(_ view: String) -> LayerIcon {
        LayerIcon(node(view: view))
    }

    func test_C_HIER_11_systemClassesAreKnownByTheirPrefix() {
        for name in [
            "UIView", "_UIBarBackground", "CALayer", "_CASomething", "NSObjectView", "WKWebView",
            "MKMapView", "AVPlayerView", "PKCanvasView", "SKView", "SCNView", "MTKView",
            "PHPickerView", "SwiftUI._UIHostingView<Foo>", "UIKit.UIView",
            "_TtC7SwiftUI17HostingScrollView", "_TtGC7SwiftUI14_UIHostingViewVS_7AnyView_",
            "_TtC5UIKit17UICoreHostingView",
        ] {
            XCTAssertFalse(LayerIcon.isAppClass(name), name)
        }
        for name in [
            "CardView", "MyApp.FeedCell", "_TtC5MyApp8FeedCell", "_TtGC5MyApp4ListSS_",
            "Avatar", "UiKitLikeView", "CartView", "SkeletonView", "UI",
        ] {
            XCTAssertTrue(LayerIcon.isAppClass(name), name)
        }
    }

    // MARK: - What the server says (P-HIER-16, P-HIER-17)

    private func node(
        parent: UInt64 = 1, view: String? = nil, layer: String = "CALayer",
        controller: String? = nil, change: (inout LayerNode) -> Void
    ) -> LayerNode {
        var node = node(parent: parent, view: view, layer: layer, controller: controller)
        change(&node)
        return node
    }

    func test_C_HIER_11_theOriginWinsOverThePrefix() {
        // A system class without a known prefix, and an app class with one.
        let privateSystem = node(view: "_SomePrivateView") { $0.viewClassOrigin = .system }
        XCTAssertFalse(LayerIcon(privateSystem).isAppClass)
        let prefixed = node(view: "UIKitLookalikeView") { $0.viewClassOrigin = .app }
        XCTAssertTrue(LayerIcon(prefixed).isAppClass)
        // A window by its view, a plain layer by its own, a root view by its controller.
        let window = node(parent: 0, view: "UIWindow") { $0.viewClassOrigin = .app }
        XCTAssertTrue(LayerIcon(window).isAppClass)
        let windowLayer = node(parent: 0) { $0.layerClassOrigin = .app }
        XCTAssertTrue(LayerIcon(windowLayer).isAppClass)
        let layer = node(layer: "RingLayer") { $0.layerClassOrigin = .system }
        XCTAssertFalse(LayerIcon(layer).isAppClass)
        let root = node(view: "UIView", controller: "UINavigationController") {
            $0.viewClassOrigin = .system
            $0.viewControllerClassOrigin = .app
        }
        XCTAssertEqual(LayerIcon(root), LayerIcon(.controller, .view, isAppClass: true))
    }

    func test_C_HIER_11_withoutTheServersWordTheNamesStand() throws {
        // The fixture's nodes with and without the optional fields give the same icons.
        let hierarchy = try Fixtures.hierarchy()
        let old = Fixtures.withoutTheOptionalFields(hierarchy)
        XCTAssertEqual(hierarchy.nodes.map(LayerIcon.init), old.nodes.map(LayerIcon.init))
        XCTAssertNotEqual(hierarchy.nodes, old.nodes)
    }
}
