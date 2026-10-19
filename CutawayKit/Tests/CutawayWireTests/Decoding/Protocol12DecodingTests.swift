import CutawayTestSupport
import FlatBuffers
import XCTest

@testable import CutawayWire

/// C-WIRE-12: what protocol 1.2 (`v1.2.0-dev.1`) appended — the environment's three messages,
/// `NotSupported`, light and dark colors, the Accessibility section and references. The
/// expected values come from Protocol/fixtures/README.md and Protocol/fixtures/src.
final class Protocol12DecodingTests: XCTestCase {
    private struct UnexpectedBody: Error {}

    private func decode(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    private func environment(_ scenario: String, _ file: String) throws -> Environment {
        guard case .environment(let environment) = try decode(scenario, file).body
        else { throw UnexpectedBody() }
        return environment
    }

    private func overrides(_ scenario: String, _ file: String) throws -> Traits {
        guard case .setEnvironment(let request) = try decode(scenario, file).body
        else { throw UnexpectedBody() }
        return request.overrides
    }

    private func attributes(of layerID: UInt64) throws -> [String: Attribute] {
        let detail = try XCTUnwrap(
            Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == layerID })
        return Dictionary(
            uniqueKeysWithValues: detail.attributeGroups.flatMap(\.attributes).map { ($0.id ?? "", $0) })
    }

    private static let portrait = Traits(
        userInterfaceStyle: .light, contentSizeCategory: .large, layoutDirection: .leftToRight,
        horizontalSizeClass: .compact, verticalSizeClass: .regular)
    private static let everyKind: [TraitKind] = [
        .userInterfaceStyle, .contentSizeCategory, .layoutDirection, .horizontalSizeClass,
        .verticalSizeClass,
    ]

    // MARK: - Handshake

    func test_C_WIRE_12_theHandshakeIsAtOnePointTwo() throws {
        XCTAssertEqual(ProtocolVersion.current, Version(major: 1, minor: 2))
        for file in ["01-c2s-hello.bin", "02-s2c-hello.bin"] {
            guard case .hello(let hello) = try decode("handshake", file).body
            else { throw UnexpectedBody() }
            XCTAssertEqual(hello.protocolVersion, Version(major: 1, minor: 2), file)
        }
    }

    // MARK: - Environment

    func test_C_WIRE_12_theEnvironmentScenarioReadsAsTheReadmeSays() throws {
        XCTAssertEqual(try decode("environment", "01-c2s-get-environment.bin").body, .getEnvironment)
        XCTAssertEqual(
            try environment("environment", "02-s2c-environment.bin"),
            Environment(overrides: .unspecified, current: Self.portrait, overridable: Self.everyKind))

        let three = Traits(
            userInterfaceStyle: .dark, contentSizeCategory: .accessibilityLarge,
            layoutDirection: .rightToLeft)
        XCTAssertEqual(try overrides("environment", "03-c2s-set-environment.bin"), three)
        var current = three
        current.horizontalSizeClass = .compact
        current.verticalSizeClass = .regular
        XCTAssertEqual(
            try environment("environment", "04-s2c-environment.bin"),
            Environment(overrides: three, current: current, overridable: Self.everyKind))

        let dark = Traits(userInterfaceStyle: .dark)
        XCTAssertEqual(try overrides("environment", "05-c2s-set-environment.bin"), dark)
        var darkPortrait = Self.portrait
        darkPortrait.userInterfaceStyle = .dark
        XCTAssertEqual(
            try environment("environment", "06-s2c-environment.bin"),
            Environment(overrides: dark, current: darkPortrait, overridable: Self.everyKind))

        // No `overrides` at all removes them all (P-ENV-02).
        XCTAssertEqual(try overrides("environment", "07-c2s-set-environment.bin"), .unspecified)
        XCTAssertEqual(
            try environment("environment", "08-s2c-environment.bin"),
            Environment(overrides: .unspecified, current: Self.portrait, overridable: Self.everyKind))
    }

    func test_C_WIRE_12_theRejectedScenarioReadsAsTheReadmeSays() throws {
        let unchanged = Environment(
            overrides: .unspecified, current: Self.portrait, overridable: [.userInterfaceStyle])
        for file in ["02-s2c-environment.bin", "06-s2c-environment.bin", "11-s2c-environment.bin"] {
            XCTAssertEqual(try environment("environment-rejected", file), unchanged, file)
        }
        XCTAssertEqual(
            try overrides("environment-rejected", "03-c2s-set-environment.bin"),
            Traits(userInterfaceStyle: .dark, layoutDirection: .rightToLeft))
        guard case .error(let notSupported) = try decode("environment-rejected", "04-s2c-error.bin").body,
              case .appStateChanged(let state) = try decode("environment-rejected", "07-s2c-app-state.bin").body,
              case .error(let notActive) = try decode("environment-rejected", "09-s2c-error.bin").body
        else { throw UnexpectedBody() }
        XCTAssertEqual(notSupported.code, .notSupported)
        XCTAssertEqual(state, .background)
        XCTAssertEqual(notActive.code, .appNotActive)
        XCTAssertEqual(
            try overrides("environment-rejected", "08-c2s-set-environment.bin"),
            Traits(userInterfaceStyle: .dark))
    }

    /// An environment built field by field with raw values, so that values outside the schema
    /// can be written. The vtable slots follow the field order in Protocol/schema/cutaway.fbs.
    private func rawEnvironment(
        overridable: [UInt8]?, currentStyle: UInt8? = nil, currentDirection: UInt8 = 0
    ) throws -> Environment {
        var builder = FlatBufferBuilder()
        let kinds = overridable.map { builder.createVector($0) }
        var current: Offset?
        if let currentStyle {
            let start = Cutaway_Wire_Traits.startTraits(&builder)
            builder.add(element: currentStyle, def: 0, at: 4)  // user_interface_style
            builder.add(element: UInt8(4), def: 0, at: 6)  // content_size_category: Large
            builder.add(element: currentDirection, def: 0, at: 8)  // layout_direction
            current = Cutaway_Wire_Traits.endTraits(&builder, start: start)
        }
        let start = Cutaway_Wire_Environment.startEnvironment(&builder)
        if let current { Cutaway_Wire_Environment.add(current: current, &builder) }
        if let kinds { Cutaway_Wire_Environment.addVectorOf(overridable: kinds, &builder) }
        let environment = Cutaway_Wire_Environment.endEnvironment(&builder, start: start)
        let frameStart = Cutaway_Wire_Frame.startFrame(&builder)
        Cutaway_Wire_Frame.add(requestId: 1, &builder)
        Cutaway_Wire_Frame.add(bodyType: .environment, &builder)
        Cutaway_Wire_Frame.add(body: environment, &builder)
        let frame = Cutaway_Wire_Frame.endFrame(&builder, start: frameStart)
        builder.finish(offset: frame, fileId: FrameCodec.fileIdentifier)
        guard case .environment(let decoded) = try FrameCodec.decode(builder.data).body
        else { throw UnexpectedBody() }
        return decoded
    }

    func test_C_WIRE_12_anEmptyEnvironmentHasNoOverridesAndNothingOverridable() throws {
        XCTAssertEqual(
            try rawEnvironment(overridable: nil),
            Environment(overrides: .unspecified, current: .unspecified, overridable: []))
    }

    /// P-HELLO-04 keeps a peer from sending values this client does not know, but one that
    /// does anyway must not fail the decoding.
    func test_C_WIRE_12_unknownTraitsReadAsUnspecifiedAndUnknownKindsAreLeftOut() throws {
        // Known values first, so that the slots are shown to reach the fields.
        let known = try rawEnvironment(overridable: [2, 0], currentStyle: 2, currentDirection: 2)
        XCTAssertEqual(known.overridable, [.layoutDirection, .userInterfaceStyle])
        XCTAssertEqual(
            known.current,
            Traits(userInterfaceStyle: .dark, contentSizeCategory: .large, layoutDirection: .rightToLeft))

        // 7 and 200 are kinds of a later version; the generated accessor would read both as
        // UserInterfaceStyle. A repeat is left out too (P-ENV-01: each at most once).
        let unknown = try rawEnvironment(
            overridable: [7, 1, 200, 1, 4], currentStyle: 9, currentDirection: 3)
        XCTAssertEqual(unknown.overridable, [.contentSizeCategory, .verticalSizeClass])
        XCTAssertEqual(unknown.current, Traits(contentSizeCategory: .large))
    }

    func test_C_WIRE_12_theEnvironmentsMessagesSurviveARoundTrip() throws {
        let traits = Traits(
            userInterfaceStyle: .light, contentSizeCategory: .accessibilityExtraExtraExtraLarge,
            layoutDirection: .leftToRight, horizontalSizeClass: .regular, verticalSizeClass: .compact)
        let bodies: [Body] = [
            .getEnvironment,
            .setEnvironment(SetEnvironment(overrides: traits)),
            .setEnvironment(SetEnvironment(overrides: .unspecified)),
            .environment(Environment(
                overrides: traits, current: Self.portrait, overridable: Self.everyKind.reversed())),
            .error(ServerError(code: .notSupported, message: "no")),
        ]
        for body in bodies {
            let frame = Frame(requestID: 3, body: body)
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
    }

    /// The round trip above cannot catch a mapping that is wrong the same way in both
    /// directions, so the values on the wire are checked against the schema's.
    func test_C_WIRE_12_enumsAreWrittenWithTheSchemasValues() throws {
        let traits = Traits(
            userInterfaceStyle: .dark, contentSizeCategory: .accessibilityExtraExtraExtraLarge,
            layoutDirection: .rightToLeft, horizontalSizeClass: .compact, verticalSizeClass: .regular)
        let frame = Frame(requestID: 1, body: .environment(Environment(
            overrides: traits, current: Traits(contentSizeCategory: .extraSmall),
            overridable: Self.everyKind)))
        let root = try FrameCodec.checkedRoot(FrameCodec.encode(frame))
        let wire = try XCTUnwrap(root.body(type: Cutaway_Wire_Environment.self))
        let overrides = try XCTUnwrap(wire.overrides)
        XCTAssertEqual(
            [overrides.userInterfaceStyle.rawValue, overrides.contentSizeCategory.rawValue,
             overrides.layoutDirection.rawValue, overrides.horizontalSizeClass.rawValue,
             overrides.verticalSizeClass.rawValue],
            [2, 12, 2, 1, 2])
        XCTAssertEqual(wire.current?.contentSizeCategory.rawValue, 1)
        XCTAssertEqual(wire.overridable.map(\.rawValue), [0, 1, 2, 3, 4])

        let error = try FrameCodec.checkedRoot(FrameCodec.encode(Frame(
            requestID: 1, body: .error(ServerError(code: .notSupported, message: nil)))))
        XCTAssertEqual(error.body(type: Cutaway_Wire_Error.self)?.code.rawValue, 9)

        let attribute = Attribute(
            id: "a", title: nil, value: .references([]), valueKind: .references,
            section: .accessibility).makeObject()
        XCTAssertEqual(attribute.valueKind.rawValue, 12)
        XCTAssertEqual(attribute.value?.type.rawValue, 12)
        XCTAssertEqual(attribute.section.rawValue, 7)
    }

    // MARK: - Attributes

    func test_C_WIRE_12_layer3CarriesTheAttributesOfOnePointTwo() throws {
        let attributes = try attributes(of: 3)
        XCTAssertEqual(attributes.count, 22)

        let textStyle = try XCTUnwrap(attributes["label.fontTextStyle"])
        XCTAssertEqual(textStyle.value, .string("body"))
        XCTAssertEqual(textStyle.cluster, AttributeCluster(name: "font", slot: "textStyle"))
        XCTAssertEqual(textStyle.section, .content)
        XCTAssertFalse(textStyle.editable)
        let scalable = try XCTUnwrap(attributes["label.adjustsFontForContentSizeCategory"])
        XCTAssertEqual(scalable.value, .bool(true))
        XCTAssertEqual(scalable.cluster, AttributeCluster(name: "font", slot: "scalable"))

        let label = try XCTUnwrap(attributes["view.accessibilityLabel"])
        XCTAssertEqual(label.value, .string("Welcome"))
        XCTAssertEqual(label.section, .accessibility)
        XCTAssertEqual(
            attributes.filter { $0.value.section == .accessibility }.keys.sorted(),
            ["view.accessibilityLabel"])

        // P-ATTR-17: the dynamic tint has both; a CGColor and the nil background have neither.
        XCTAssertEqual(
            attributes.compactMapValues(\.appearanceColors),
            ["view.tintColor": AppearanceColors(
                light: Color(red: 0, green: 0.47843137, blue: 1, alpha: 1),
                dark: Color(red: 0.039215688, green: 0.5176471, blue: 1, alpha: 1))])
        XCTAssertEqual(attributes["view.tintColor"]?.value, .color(Color(red: 0, green: 0.47843137, blue: 1, alpha: 1)))
    }

    func test_C_WIRE_12_layer6CarriesReferences() throws {
        let detail = try XCTUnwrap(
            Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 6 })
        XCTAssertEqual(detail.status, .ok)
        XCTAssertEqual(detail.attributeGroups.map(\.id), ["scrollView", "view"])
        XCTAssertEqual(detail.attributeGroups.map(\.className), ["UIScrollView", "UIView"])

        let attributes = try attributes(of: 6)
        let delegate = try XCTUnwrap(attributes["scrollView.delegate"])
        XCTAssertEqual(
            delegate.value,
            .references([ObjectReference(
                layerID: 2, className: "Demo.HomeViewController",
                displayClassName: "HomeViewController")]))
        XCTAssertEqual(delegate.valueKind, .references)
        XCTAssertEqual(delegate.section, .content)
        XCTAssertFalse(delegate.editable)

        let recognizers = try XCTUnwrap(attributes["view.gestureRecognizers"])
        XCTAssertEqual(
            recognizers.value,
            .references(
                ["UIScrollViewDelayedTouchesBeganGestureRecognizer", "UIScrollViewPanGestureRecognizer"]
                    .map { ObjectReference(layerID: nil, className: $0, displayClassName: $0) }))
        XCTAssertEqual(recognizers.section, .behavior)
    }

    func test_C_WIRE_12_setAttributeRepliesCarryTheAttributesOfOnePointTwo() throws {
        let results = try Fixtures.setAttributeResults().filter { $0.layerID == 3 }
        XCTAssertFalse(results.isEmpty)
        for result in results {
            let attributes = result.attributeGroups.flatMap(\.attributes)
            XCTAssertEqual(attributes.count, 22)
            XCTAssertEqual(attributes.first { $0.id == "view.accessibilityLabel" }?.section, .accessibility)
            XCTAssertNotNil(attributes.first { $0.id == "view.tintColor" }?.appearanceColors)
        }
    }

    func test_C_WIRE_12_framesWithoutTheNewFieldsReadAsAbsent() throws {
        let details = try Fixtures.layerDetails(scenario: "layer-details").map { detail in
            var detail = detail
            detail.attributeGroups = Fixtures.withoutProtocol12(detail.attributeGroups)
            return detail
        }
        let frame = Frame(requestID: 3, body: .layerDetailsChunk(LayerDetailsChunk(
            sequence: 0, details: details)))
        guard case .layerDetailsChunk(let chunk) = try FrameCodec.decode(FrameCodec.encode(frame)).body
        else { throw UnexpectedBody() }
        let attributes = chunk.details.flatMap(\.attributeGroups).flatMap(\.attributes)
        XCTAssertEqual(attributes.count, 22 + 2)
        XCTAssertTrue(attributes.allSatisfy { $0.appearanceColors == nil })
        XCTAssertFalse(attributes.contains { $0.section == .accessibility })
        XCTAssertFalse(attributes.contains { $0.valueKind == .references })
        XCTAssertEqual(attributes.first { $0.id == "view.accessibilityLabel" }?.section, .unspecified)
        XCTAssertEqual(
            attributes.first { $0.id == "scrollView.delegate" }?.value,
            .string("Demo.HomeViewController"))
        XCTAssertEqual(
            attributes.first { $0.id == "label.fontSize" }?.cluster,
            AttributeCluster(name: "font", slot: "size"), "1.1's slots stay")
        XCTAssertNil(attributes.first { $0.id == "label.fontTextStyle" }?.cluster)
    }

    /// An attribute made with the generated object API, which can leave out what the value
    /// types always pair.
    private func attribute(_ object: Cutaway_Wire_AttributeT) throws -> Attribute {
        var object = object
        var builder = FlatBufferBuilder()
        let end = Cutaway_Wire_Attribute.pack(&builder, obj: &object)
        Cutaway_Wire_Attribute.finish(&builder, end: end)
        var buffer = builder.sizedBuffer
        let wire: Cutaway_Wire_Attribute = try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
        return Attribute(wire)
    }

    func test_C_WIRE_12_lightWithoutDarkIsNeither() throws {
        let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let both = Attribute(
            id: "c", title: nil, value: .color(blue), valueKind: .color,
            appearanceColors: AppearanceColors(light: blue, dark: .zero))
        XCTAssertEqual(try attribute(both.makeObject()), both)

        for keepsLight in [true, false] {
            let object = both.makeObject()
            let color = try XCTUnwrap(object.value?.value as? Cutaway_Wire_ColorValueT)
            if keepsLight { color.dark = nil } else { color.light = nil }
            let decoded = try attribute(object)
            XCTAssertNil(decoded.appearanceColors, keepsLight ? "light alone" : "dark alone")
            XCTAssertEqual(decoded.value, .color(blue))
        }
    }

    func test_C_WIRE_12_referencesFallBackToTheClassNameAndDropNamelessEntries() throws {
        let object = Attribute(
            id: "r", title: nil, value: .references([]), valueKind: .references).makeObject()
        let value = try XCTUnwrap(object.value?.value as? Cutaway_Wire_LayerReferenceValueT)
        func entry(_ id: UInt64, _ className: String?, _ display: String?) -> Cutaway_Wire_ObjectReferenceT {
            let entry = Cutaway_Wire_ObjectReferenceT()
            entry.layerId = id
            entry.className = className
            entry.displayClassName = display
            return entry
        }
        value.references = [
            entry(4, "Demo.CardView", nil),
            entry(0, nil, nil),
            entry(5, "", ""),
            entry(0, nil, "Anchor"),
        ]
        XCTAssertEqual(
            try attribute(object).value,
            .references([
                ObjectReference(layerID: 4, className: "Demo.CardView", displayClassName: "Demo.CardView"),
                ObjectReference(layerID: nil, className: nil, displayClassName: "Anchor"),
            ]))
    }
}
