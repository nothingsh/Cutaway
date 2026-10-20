import AppKit
import Combine
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-ATTR-24: a colour is called by the name the app registered (P-ATTR-20) before a matching
/// asset (C-SRC-04) and UIKit's name (C-ATTR-22); the tooltip gives the others and the code.
@MainActor
final class ColorNameTests: XCTestCase {
    private static let brandBlue = Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)

    /// A project with a colour set of the same value.
    private static let index = ProjectIndex(
        root: URL(fileURLWithPath: "/tmp/Shop"),
        colorSets: [ColorSet(
            name: "BrandBlue", file: "BrandBlue.colorset/Contents.json",
            entries: [ColorSet.Entry(
                idiom: "universal", appearances: [], colorSpace: "srgb",
                components: ["red": "51", "green": "102", "blue": "204", "alpha": "1.000"],
                systemReference: nil)])],
        strings: [])

    private static func attribute(registered: String?, system: String? = nil) -> Attribute {
        var attribute = Attribute(
            id: "app.row.color", title: "Color", value: .color(brandBlue), editable: true,
            valueKind: .color, systemColorName: system)
        attribute.registeredColorName = registered
        return attribute
    }

    private static func hexField(in view: NSView) throws -> AttributeEditField {
        try XCTUnwrap(
            AppListViewTests.descendants(of: view)
                .first { $0.accessibilityIdentifier() == AttributeEditorView.hexIdentifier } as? AttributeEditField)
    }

    func test_C_ATTR_24_aRegisteredNameIsWrittenAsIs() throws {
        let attribute = Self.attribute(registered: "brandBlue")
        let names = ValueNames(attribute, index: nil)
        XCTAssertEqual(names.colorName, "brandBlue", "not split at capitals")
        XCTAssertEqual(names.colorNotes, [])

        let editor = AttributeEditorView(attribute: attribute, onSet: { _, _ in })
        editor.show(attribute.value, names: names)
        let hex = try Self.hexField(in: editor)
        XCTAssertEqual(hex.shownText, "brandBlue")
        XCTAssertEqual(hex.toolTip, "#3366CC")
    }

    func test_C_ATTR_24_theRegisteredNameComesBeforeAssetAndSystemNames() throws {
        let attribute = Self.attribute(registered: "brandBlue", system: "systemBlue")
        let names = ValueNames(attribute, index: Self.index)
        XCTAssertEqual(names.colorName, "brandBlue")
        XCTAssertEqual(names.colorNotes, ["Asset: BrandBlue", "System Blue"])

        let editor = AttributeEditorView(attribute: attribute, onSet: { _, _ in })
        editor.show(attribute.value, names: names)
        let hex = try Self.hexField(in: editor)
        XCTAssertEqual(hex.shownText, "brandBlue")
        XCTAssertEqual(hex.toolTip, "Asset: BrandBlue · System Blue · #3366CC")
    }

    func test_C_ATTR_24_withoutTheRegisteredNameAsBefore() {
        let attribute = Self.attribute(registered: nil, system: "systemBlue")
        XCTAssertEqual(ValueNames(attribute, index: Self.index).colorName, "BrandBlue", "the asset (C-SRC-04)")
        XCTAssertEqual(ValueNames(attribute, index: nil).colorName, "System Blue", "UIKit's (C-ATTR-22)")
        XCTAssertNil(ValueNames(Self.attribute(registered: nil), index: nil).colorName, "the code")
    }

    func test_C_ATTR_24_theFixturesRowColorIsBrandBlue() throws {
        let color = try XCTUnwrap(
            Fixtures.attributes(of: 10, scenario: "layer-details").flatMap(\.attributes)
                .first { $0.id == "app.row.color" })
        XCTAssertEqual(ValueNames(color, index: nil).colorName, "brandBlue")
    }

    func test_C_ATTR_24_aCompoundColourTakesTheRegisteredName() async throws {
        var responder = try MockResponder.demo()
        let groups = responder.details[3]?.attributeGroups ?? []
        responder.details[3]?.attributeGroups = groups.map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                if attribute.id == "layer.borderColor" { attribute.registeredColorName = "ink" }
                return attribute
            }
            return group
        }
        let server = try await MockServer.start(script: MockScript(
            steps: try MockScript.fixtures("handshake").steps + [.respond(responder)]))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 14 }
        XCTAssertTrue(tree)
        let summary = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: summary, loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 700), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.layoutIfNeeded()
        model.select(3)
        let loaded = await Wait.until {
            await MainActor.run { !controller.compoundRows.isEmpty }
        }
        XCTAssertTrue(loaded)
        let border = try XCTUnwrap(
            controller.compoundRows.first { $0.view(forAttribute: "layer.borderColor") != nil })
        let part = try XCTUnwrap(border.view(forAttribute: "layer.borderColor"))
        XCTAssertEqual(try Self.hexField(in: part).shownText, "ink")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }
}
