import AppKit
import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// C-SRC-04, C-SRC-05: what the attribute panel names a colour and a text by, from the app's
/// project folder: the colour set a colour is (part of C-ATTR-24), and the key a text is a
/// value of.
@MainActor
final class SourceNamesTests: XCTestCase {
    private static let tint = Color(red: 0, green: 0.47843137, blue: 1, alpha: 1)
    private static let tintDark = Color(red: 0.039215688, green: 0.5176471, blue: 1, alpha: 1)

    private static func colorSet(_ name: String, any: [String], dark: [String]? = nil) -> ColorSet {
        func entry(_ rgb: [String], _ luminosity: String?) -> ColorSet.Entry {
            ColorSet.Entry(
                idiom: "universal",
                appearances: luminosity.map { [.init(appearance: "luminosity", value: $0)] } ?? [],
                colorSpace: "srgb",
                components: ["red": rgb[0], "green": rgb[1], "blue": rgb[2], "alpha": "1.000"],
                systemReference: nil)
        }
        return ColorSet(
            name: name, file: "\(name).colorset/Contents.json",
            entries: [entry(any, nil)] + (dark.map { [entry($0, "dark")] } ?? []))
    }

    private static func string(_ key: String, _ value: String, table: String = "Localizable") -> LocalizedString {
        LocalizedString(table: table, key: key, language: "en", value: value, file: "\(table).xcstrings")
    }

    /// A project whose `Brand/Tint` is UIKit's system blue in both appearances, as layer 3's
    /// tint is, and whose table has layer 3's text.
    private static let index = ProjectIndex(
        root: URL(fileURLWithPath: "/tmp/Shop"),
        colorSets: [
            colorSet("Brand/Tint", any: ["0", "122", "255"], dark: ["10", "132", "255"]),
            colorSet("Plain", any: ["0", "0", "0"]),
        ],
        strings: [string("greeting", "Hello"), string("welcome", "Welcome"), string("hello", "Hello", table: "Main")])

    private static let tintAttribute = Attribute(
        id: "view.tintColor", title: "Tint", value: .color(tint), editable: true, valueKind: .color,
        systemColorName: "systemBlue", appearanceColors: AppearanceColors(light: tint, dark: tintDark))

    // MARK: - C-SRC-04

    func test_C_SRC_04_anAssetsNameComesBeforeUIKits() {
        let names = ValueNames(Self.tintAttribute, index: Self.index)
        XCTAssertEqual(names.colorName, "Brand/Tint", "as it is, not split at capitals")
        XCTAssertEqual(names.colorNotes, ["Asset: Brand/Tint", "System Blue"])

        XCTAssertEqual(ValueNames(Self.tintAttribute, index: nil).colorName, "System Blue", "no folder")
        var light = Self.tintAttribute
        light.appearanceColors = AppearanceColors(light: Self.tint, dark: .zero)
        XCTAssertEqual(ValueNames(light, index: Self.index).colorName, "System Blue", "only half matches")
    }

    func test_C_SRC_04_aColorThatIsNotDynamicNamesTheAppearanceItMatched() {
        let border = Attribute(
            id: "layer.borderColor", title: "Border Color",
            value: .color(Color(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)), valueKind: .color)
        let names = ValueNames(border, index: Self.index)
        XCTAssertEqual(names.colorName, "Brand/Tint")
        XCTAssertEqual(names.colorNotes, ["Asset: Brand/Tint (Dark)"])
        let black = Attribute(id: "b", title: "B", value: .color(Color(red: 0, green: 0, blue: 0, alpha: 1)),
                              valueKind: .color)
        XCTAssertEqual(ValueNames(black, index: Self.index).colorNotes, ["Asset: Plain"])
    }

    func test_C_SRC_04_theColorFieldShowsTheAssetAndItsTooltipTheRest() throws {
        let editor = AttributeEditorView(attribute: Self.tintAttribute, onSet: { _, _ in })
        editor.show(Self.tintAttribute.value, names: ValueNames(Self.tintAttribute, index: Self.index))
        let hex = try XCTUnwrap(
            AppListViewTests
                .descendants(of: editor) { $0.accessibilityIdentifier() == AttributeEditorView.hexIdentifier }
                .first as? AttributeEditField)
        XCTAssertEqual(hex.shownText, "Brand/Tint")
        // The fixture's tint is dynamic: both appearances end the tooltip (C-ATTR-25).
        XCTAssertEqual(hex.toolTip, "Asset: Brand/Tint · System Blue · #007AFF · Light 007AFF · Dark 0A84FF")
        // UIKit's name alone, as before (C-ATTR-22).
        editor.show(Self.tintAttribute.value, names: ValueNames(Self.tintAttribute, index: nil))
        XCTAssertEqual(hex.shownText, "System Blue")
        XCTAssertEqual(hex.toolTip, "#007AFF · Light 007AFF · Dark 0A84FF")
    }

    // MARK: - C-SRC-05

    func test_C_SRC_05_aTextNamesItsKeys() {
        let text = Attribute(id: "label.text", title: "Text", value: .string("Hello"), valueKind: .string)
        let names = ValueNames(text, index: Self.index)
        XCTAssertEqual(names.stringKey, "Key greeting · Localizable", "by table, then key: the first")
        XCTAssertEqual(names.stringKeys, "Key greeting · Localizable\nKey hello · Main")
        let welcome = Attribute(id: "x", title: "X", value: .string("Welcome"), valueKind: .string)
        XCTAssertEqual(ValueNames(welcome, index: Self.index).stringKey, "Key welcome · Localizable")
        XCTAssertNil(ValueNames(welcome, index: Self.index).stringKeys, "one key needs no list")
        let other = Attribute(id: "x", title: "X", value: .string("Goodbye"), valueKind: .string)
        XCTAssertEqual(ValueNames(other, index: Self.index), .none)
    }

    func test_C_SRC_05_anErrorGoesBeforeTheKeyAndTheKeyComesBack() {
        let editor = AttributeEditorView(
            attribute: Attribute(id: "label.text", title: "Text", value: .string("Hello"), editable: true,
                                 valueKind: .string),
            onSet: { _, _ in })
        let row = AttributeRowView(title: "Text", value: .string("Hello"), editor: editor)
        row.show(.string("Hello"), names: ValueNames(stringKey: "Key greeting · Localizable"))
        XCTAssertEqual(row.noteText, "Key greeting · Localizable")
        XCTAssertFalse(row.noteIsError)
        editor.onNote("Too long.")
        XCTAssertEqual(row.noteText, "Too long.")
        XCTAssertTrue(row.noteIsError)
        editor.onNote(nil)
        XCTAssertEqual(row.noteText, "Key greeting · Localizable")
        row.show(.string("Goodbye"), names: .none)
        XCTAssertNil(row.noteText)
    }

    // MARK: - In the panel

    /// Layer 3 of the fixtures in a panel whose project index comes from `index`, every
    /// attribute on a row of its own unless `clusters`; with `renamed`, under names no list
    /// could know.
    private func panel(
        _ index: some Publisher<ProjectIndex?, Never>, renamed: Bool = false, clusters: Bool = false
    ) async throws -> (AttributesViewController, NSWindow, Session, MockServer) {
        var script = try MockScript.fixtures("handshake", "hierarchy", "layer-details")
        if !clusters { script = script.withoutClusters() }
        if renamed { script = script.renamingAttributes() }
        let server = try await MockServer.start(script: script)
        let channel = try await ConnectionChannel.connect(host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let tree = await Wait.until { await model.tree.count == 9 }
        XCTAssertTrue(tree)
        let layer = Publishers.CombineLatest(model.$selectedLayerID, model.$tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo", layer: layer,
            projectIndex: index.eraseToAnyPublisher(), loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 700), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.layoutIfNeeded()
        model.select(3)
        let loaded = await Wait.until {
            await MainActor.run {
                if case .loaded = model.attributes.state { return !controller.attributeRows.isEmpty }
                return false
            }
        }
        XCTAssertTrue(loaded)
        return (controller, window, session, server)
    }

    private func row(_ title: String, in controller: AttributesViewController) throws -> AttributeRowView {
        try XCTUnwrap(controller.attributeRows.first { $0.row.title == title }?.row, title)
    }

    private func shownColor(_ row: AttributeRowView) throws -> String {
        let field = AppListViewTests.descendants(of: row) {
            $0.accessibilityIdentifier() == AttributeEditorView.hexIdentifier
        }.first as? AttributeEditField
        return try XCTUnwrap(field).shownText
    }

    func test_C_SRC_04_theRowsNameTheirValuesOnceTheIndexIsBuilt() async throws {
        let index = CurrentValueSubject<ProjectIndex?, Never>(nil)
        let (controller, window, session, server) = try await panel(index)
        XCTAssertEqual(try shownColor(try row("Tint", in: controller)), "System Blue")
        XCTAssertNil(try row("Text", in: controller).noteText)

        index.send(Self.index)
        XCTAssertEqual(try shownColor(try row("Tint", in: controller)), "Brand/Tint")
        XCTAssertEqual(try row("Text", in: controller).noteText, "Key greeting · Localizable")
        XCTAssertEqual(try row("Label", in: controller).noteText, "Key welcome · Localizable")

        index.send(nil)
        XCTAssertEqual(try shownColor(try row("Tint", in: controller)), "System Blue")
        XCTAssertNil(try row("Text", in: controller).noteText)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    func test_C_SRC_04_aCompoundRowsColorIsNamedToo() async throws {
        let (controller, window, session, server) = try await panel(Just<ProjectIndex?>(Self.index), clusters: true)
        // Layer 3's border colour is black, the colour of `Plain`.
        let border = try XCTUnwrap(controller.compoundRows.first { $0.view(forAttribute: "layer.borderColor") != nil })
        let part = try XCTUnwrap(border.view(forAttribute: "layer.borderColor"))
        let field = AppListViewTests.descendants(of: part) {
            $0.accessibilityIdentifier() == AttributeEditorView.hexIdentifier
        }.first as? AttributeEditField
        XCTAssertEqual(try XCTUnwrap(field).shownText, "Plain")
        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    func test_C_SRC_05_keysAreFoundWhateverTheAttributesAreCalled() async throws {
        let (controller, window, session, server) = try await panel(Just<ProjectIndex?>(Self.index), renamed: true)
        XCTAssertEqual(
            try row(Fixtures.renamed("Text"), in: controller).noteText, "Key greeting · Localizable",
            "not by the attribute's ID (C-ATTR-03)")
        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }
}
