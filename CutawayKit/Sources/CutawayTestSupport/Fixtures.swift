// CutawayTestSupport: fixture loading, MockServer and FakeUsbmuxd.
//
// Used by test targets only.

import CutawayWire
import Foundation

/// One frame of a fixture scenario.
public struct FixtureFrame: Equatable, Sendable {
    public enum Direction: String, Sendable {
        case clientToServer = "c2s"
        case serverToClient = "s2c"
    }

    public var scenario: String
    /// For example `02-s2c-hello.bin`. Frames of a scenario sort by this name.
    public var fileName: String
    public var direction: Direction
    /// A plain FlatBuffer without a length prefix.
    public var payload: Data
}

/// Locates the protocol fixtures under `Protocol/fixtures/bin`.
public enum Fixtures {
    /// The repository root, found from this file's own location:
    /// `<root>/CutawayKit/Sources/CutawayTestSupport/Fixtures.swift`.
    public static let repositoryRoot: URL = .init(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CutawayTestSupport
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // CutawayKit
        .deletingLastPathComponent()  // repository root

    /// The bytes of one fixture file, for example
    /// `data(scenario: "handshake", file: "02-s2c-hello.bin")`.
    public static func data(scenario: String, file: String) throws -> Data {
        let url = repositoryRoot
            .appendingPathComponent("Protocol/fixtures/bin")
            .appendingPathComponent(scenario)
            .appendingPathComponent(file)
        return try Data(contentsOf: url)
    }

    private static var binDirectory: URL {
        repositoryRoot.appendingPathComponent("Protocol/fixtures/bin")
    }

    /// The names of all scenarios, sorted.
    public static func scenarios() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: binDirectory.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// The frames of one scenario in wire order.
    public static func frames(scenario: String) throws -> [FixtureFrame] {
        let directory = binDirectory.appendingPathComponent(scenario)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".bin") }
            .sorted()
            .map { fileName in
                // File names look like NN-<direction>-<name>.bin.
                let parts = fileName.split(separator: "-")
                guard parts.count >= 3, let direction = FixtureFrame.Direction(rawValue: String(parts[1]))
                else { throw CocoaError(.fileReadCorruptFile) }
                return FixtureFrame(
                    scenario: scenario, fileName: fileName, direction: direction,
                    payload: try Data(contentsOf: directory.appendingPathComponent(fileName)))
            }
    }

    /// The exact bytes one side sends in a scenario, or nil when that side sends nothing.
    public static func stream(scenario: String, direction: FixtureFrame.Direction) throws -> Data? {
        let url = binDirectory.appendingPathComponent(scenario)
            .appendingPathComponent("\(direction.rawValue).stream")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}

extension Fixtures {
    /// The `Hierarchy` of the `hierarchy` scenario: one window, nine nodes
    /// (Protocol/fixtures/README.md).
    public static func hierarchy() throws -> Hierarchy {
        let frame = try FrameCodec.decode(
            try data(scenario: "hierarchy", file: "02-s2c-hierarchy.bin"))
        guard case .hierarchy(let hierarchy) = frame.body else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return hierarchy
    }

    /// The answer to `GetSubtree(4)` in the `subtree` scenario: nodes 4 and 5, as in
    /// `hierarchy()` (Protocol/fixtures/README.md). Protocol 0.3.
    public static func subtreeOfNode4() throws -> Hierarchy {
        let frame = try FrameCodec.decode(
            try data(scenario: "subtree", file: "02-s2c-hierarchy.bin"))
        guard case .hierarchy(let hierarchy) = frame.body else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return hierarchy
    }
}

extension Fixtures {
    /// Every `LayerDetail` the server sends in a scenario, in the order they arrive.
    public static func layerDetails(scenario: String) throws -> [LayerDetail] {
        try frames(scenario: scenario)
            .filter { $0.direction == .serverToClient }
            .flatMap { frame -> [LayerDetail] in
                guard case .layerDetailsChunk(let chunk) = try FrameCodec.decode(frame.payload).body
                else { return [] }
                return chunk.details
            }
    }
}

extension Fixtures {
    /// The constraints the `layout-constraints` scenario brings for one layer, in its order
    /// (Protocol/fixtures/README.md). Empty for a layer it has none for. Protocol 0.4;
    /// constraints 8 to 11 as of 0.5.
    public static func constraints(of id: UInt64) throws -> [LayoutConstraint] {
        try layerDetails(scenario: "layout-constraints").first { $0.layerID == id }?.constraints
            ?? []
    }

    /// A layer's detail as the attribute panel asks for it (C-LAYOUT-01): its attributes from
    /// `layer-details`, none for a layer that scenario does not have, and its constraints from
    /// `layout-constraints`. Both scenarios use the layers of `hierarchy`.
    public static func panelDetail(of id: UInt64) throws -> LayerDetail {
        let attributes = try layerDetails(scenario: "layer-details")
            .first { $0.layerID == id }?.attributeGroups ?? []
        return LayerDetail(
            layerID: id, status: .ok, solo: nil, group: nil, attributeGroups: attributes,
            constraints: try constraints(of: id))
    }
}

extension Fixtures {
    /// A string no list of attributes could know, in place of `text`, the same every time
    /// (C-ATTR-03): "Frame" becomes "r5-emarF".
    public static func renamed(_ text: String) -> String {
        "r\(text.count)-" + String(text.reversed())
    }

    /// The groups with every group ID, attribute ID and title renamed. Values and the flags
    /// of protocol 0.3 stay.
    public static func renamingAttributes(_ groups: [AttributeGroup]) -> [AttributeGroup] {
        groups.map { group in
            AttributeGroup(
                id: group.id.map(renamed), title: group.title.map(renamed),
                attributes: group.attributes.map { attribute in
                    var renamedAttribute = attribute
                    renamedAttribute.id = attribute.id.map(renamed)
                    renamedAttribute.title = attribute.title.map(renamed)
                    return renamedAttribute
                })
        }
    }

    /// The groups with no clusters: every attribute on a row of its own (C-ATTR-19).
    public static func withoutClusters(_ groups: [AttributeGroup]) -> [AttributeGroup] {
        groups.map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                attribute.cluster = nil
                return attribute
            }
            return group
        }
    }

    /// The groups as a 1.1 server sends them (C-WIRE-12): no light and dark colors, no
    /// Accessibility section, none of the clusters and slots 1.2 appended to P-ATTR-12's
    /// table, and references as text naming the objects, the way such a server describes them
    /// (Protocol/PROTOCOL.md, after P-ATTR-18).
    public static func withoutProtocol12(_ groups: [AttributeGroup]) -> [AttributeGroup] {
        groups.map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                attribute.appearanceColors = nil
                if attribute.section == .accessibility { attribute.section = .unspecified }
                if let cluster = attribute.cluster, protocol12Clusters.contains(cluster.name)
                    || protocol12Slots.contains(cluster)
                {
                    attribute.cluster = nil
                }
                if attribute.valueKind == .references {
                    attribute.valueKind = .string
                    if case .references(let references) = attribute.value {
                        attribute.value = .string(
                            references.map { $0.className ?? $0.displayClassName }
                                .joined(separator: ", "))
                    }
                }
                return attribute
            }
            return group
        }
    }

    private static let protocol12Clusters: Set = ["image", "indexPath", "listCounts"]
    private static let protocol12Slots: Set = [
        AttributeCluster(name: "font", slot: "textStyle"),
        AttributeCluster(name: "font", slot: "scalable"),
        AttributeCluster(name: "lines", slot: "drawn"),
        AttributeCluster(name: "lines", slot: "truncated"),
    ]

    /// The groups as a 1.0 server sends them: nothing of 1.1, so no sections and no limits
    /// either (C-WIRE-10).
    public static func withoutProtocol11(_ groups: [AttributeGroup]) -> [AttributeGroup] {
        withoutTheOptionalFields(withoutProtocol12(groups)).map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                attribute.section = .unspecified
                attribute.limits = nil
                return attribute
            }
            return group
        }
    }

    /// The hierarchy as a 1.0 server sends it: nothing of 1.1, so no addresses either
    /// (C-WIRE-10).
    public static func withoutProtocol11(_ hierarchy: Hierarchy) -> Hierarchy {
        var hierarchy = withoutTheOptionalFields(hierarchy)
        hierarchy.nodes = hierarchy.nodes.map { node in
            var node = node
            node.layerAddress = nil
            node.viewAddress = nil
            node.viewControllerAddress = nil
            return node
        }
        return hierarchy
    }

    /// The groups as a server that leaves out what 1.1 lets it leave out sends them
    /// (C-WIRE-11): no clusters, inactive causes, units, system color names or class names,
    /// and no Content, Appearance or Behavior section.
    public static func withoutTheOptionalFields(_ groups: [AttributeGroup]) -> [AttributeGroup] {
        groups.map { group in
            var group = group
            group.className = nil
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                attribute.cluster = nil
                attribute.inactiveCause = nil
                attribute.unit = .unspecified
                attribute.systemColorName = nil
                switch attribute.section {
                case .content, .appearance, .behavior: attribute.section = .general
                case .unspecified, .identity, .general, .layout, .accessibility: break
                }
                return attribute
            }
            return group
        }
    }

    /// The hierarchy as a server that leaves out what 1.1 lets it leave out sends it
    /// (C-WIRE-11): no origins, base classes or visibility.
    public static func withoutTheOptionalFields(_ hierarchy: Hierarchy) -> Hierarchy {
        var hierarchy = hierarchy
        hierarchy.nodes = hierarchy.nodes.map { node in
            var node = node
            node.layerClassOrigin = .unknown
            node.viewClassOrigin = .unknown
            node.viewControllerClassOrigin = .unknown
            node.layerBaseClassName = nil
            node.viewBaseClassName = nil
            node.viewControllerVisibility = .unknown
            return node
        }
        return hierarchy
    }

    /// The constraints as a server that leaves out what 1.1 lets it leave out sends them
    /// (C-WIRE-11): no origins and no guide kinds.
    public static func withoutTheOptionalFields(_ constraints: [LayoutConstraint]) -> [LayoutConstraint] {
        constraints.map { constraint in
            var constraint = constraint
            constraint.origin = .unknown
            constraint.firstItem = constraint.firstItem.map(withoutTheOptionalFields)
            constraint.secondItem = constraint.secondItem.map(withoutTheOptionalFields)
            return constraint
        }
    }

    private static func withoutTheOptionalFields(_ item: LayoutItem) -> LayoutItem {
        guard case .layoutGuide(var guide) = item else { return item }
        guide.kind = .unknown
        return .layoutGuide(guide)
    }

    /// The answers of the `set-attribute` scenario, in order (Protocol/fixtures/README.md).
    /// Protocol 0.3.
    public static func setAttributeResults() throws -> [SetAttributeResult] {
        try frames(scenario: "set-attribute").compactMap { fixture in
            guard case .setAttributeResult(let result) = try FrameCodec.decode(fixture.payload).body
            else { return nil }
            return result
        }
    }

    /// Layer 4 of the `set-attribute` scenario as it is before the scenario changes it: its
    /// background colour nil, its opacity and alpha 1. Only that scenario has layer 4's
    /// attributes; this is its third answer with the background set back.
    public static func layerFourBeforeEditing() throws -> [AttributeGroup] {
        let third = try setAttributeResults()[2].attributeGroups
        return third.map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                if attribute.id == "view.backgroundColor" { attribute.value = nil }
                return attribute
            }
            return group
        }
    }

    /// The attributes a scenario brings for one layer.
    public static func attributes(of id: UInt64, scenario: String) throws -> [AttributeGroup] {
        guard let detail = try layerDetails(scenario: scenario).first(where: { $0.layerID == id })
        else { throw CocoaError(.fileReadCorruptFile) }
        return detail.attributeGroups
    }
}

extension Fixtures {
    /// An archive of the fixtures' app (`MockResponder.demo()`): every layer with all its
    /// parts, `chunkSize` layers to a chunk, in tree order. `state` is the interface state
    /// section as it is written (Resources/ARCHIVE.md).
    public static func archive(
        chunkSize: Int = 4, state: Data = Data(),
        protocolVersion: Version = ProtocolVersion.current,
        savedAt: Date = Date(timeIntervalSince1970: 1_791_280_000)
    ) throws -> Data {
        let responder = try MockResponder.demo()
        var encoder = ArchiveEncoder()
        var data = encoder.header(
            manifest: ArchiveManifest(
                protocolVersion: protocolVersion, cutawayVersion: "0.1.0", savedAt: savedAt),
            state: state)
        data += try encoder.frame(try Self.data(scenario: "handshake", file: "02-s2c-hello.bin"))
        data += try encoder.frame(FrameCodec.encode(Frame(requestID: 1, body: .appIcon(responder.icon))))
        data += try encoder.frame(
            FrameCodec.encode(Frame(requestID: 2, body: .hierarchy(responder.hierarchy))))
        let ids = responder.hierarchy.nodes.map(\.id)
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let details = ids[start..<min(start + chunkSize, ids.count)].compactMap {
                responder.details[$0]
            }
            let chunk = LayerDetailsChunk(sequence: 0, details: details)
            data += try encoder.frame(
                FrameCodec.encode(Frame(requestID: 3, body: .layerDetailsChunk(chunk))))
        }
        return data + encoder.trailer()
    }
}
