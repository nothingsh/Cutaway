import CutawayWire
import Foundation

/// Answers requests by what they ask for rather than in a scripted order, for clients whose
/// requests interleave unpredictably: the preview's screenshots and an archive's capture, for
/// example. A `MockScript` hands over to it with `respond` (C-MOCK-01).
///
/// Each `GetLayerDetails` is answered at once with its chunks (`answerChunks(_:)`) and a
/// completed end, so a `Cancel` always comes after its stream ended and is passed over
/// (P-REQ-04).
public struct MockResponder: Sendable {
    /// What a `SetAttribute` gets.
    public enum Editing: Sendable {
        /// `AttributeNotEditable`, whatever is asked.
        case refuse
        /// The value is written into the layer's attributes, for the rest of the connection,
        /// and the answer is the layer's attribute groups (P-SET-01). The hierarchy follows the
        /// layer's opacity, hidden flag and position.
        case apply
    }

    public enum Failure: Sendable {
        /// The server closes the connection instead of answering.
        case disconnect
        /// The stream ends as failed with `AppNotActive` (P-APP-01).
        case appNotActive
    }

    public var icon: AppIcon
    public var hierarchy: Hierarchy
    /// Everything there is to know about each layer. A request gets the parts it asks for;
    /// a layer missing here is `LayerNotFound`.
    public var details: [UInt64: LayerDetail]
    public var editing = Editing.refuse
    /// Where layers missing from `details` are looked up: an archive being replayed.
    var archived: ArchivedDetails?
    /// Before answering the nth `GetLayerDetails` of a connection (from 1), wait at the gate.
    public var holdBeforeDetailsRequest: (Int, MockGate)?
    /// Instead of answering the nth `GetLayerDetails` of a connection (from 1), fail.
    public var failDetailsRequest: (Int, Failure)?
    /// Before answering the first `GetLayerDetails` the condition holds for, wait at the gate.
    /// For a client whose requests of several kinds interleave.
    public var holdBeforeDetails: (@Sendable (GetLayerDetails) -> Bool, MockGate)?
    /// Instead of answering any `GetLayerDetails` the condition holds for, fail.
    public var failDetails: (@Sendable (GetLayerDetails) -> Bool, Failure)?
    /// The app's trait environment (C-ENV-02). Nil answers as an app that can override
    /// nothing, as `MockScript.unscriptedEnvironment` does.
    public var environment: MockEnvironment?
    /// Before answering the nth `SetEnvironment` of a connection (from 1), wait at the gate.
    public var holdBeforeSetEnvironment: (Int, MockGate)?
    /// Instead of answering the nth `SetEnvironment` of a connection (from 1), fail.
    public var failSetEnvironment: (Int, Failure)?

    /// A request an archive's capture makes: every part of every layer (C-ARCH-02).
    public static let isArchiveBatch: @Sendable (GetLayerDetails) -> Bool = { request in
        request.requests.allSatisfy { $0.wantSolo && $0.wantGroup && $0.wantAttributes }
    }

    public init(icon: AppIcon, hierarchy: Hierarchy, details: [UInt64: LayerDetail]) {
        self.icon = icon
        self.hierarchy = hierarchy
        self.details = details
    }

    /// The fixtures' app: the `hierarchy` scenario's nine layers, the `app-icon` icon, the
    /// screenshots and attributes of `layer-details` and `layer-details-edge`, and the
    /// constraints of `layout-constraints`. Layers they say nothing about are `ok` and empty.
    public static func demo() throws -> Self {
        guard case .appIcon(let icon) = try FrameCodec.decode(
            try Fixtures.data(scenario: "app-icon", file: "02-s2c-app-icon.bin")).body
        else { throw CocoaError(.fileReadCorruptFile) }
        let hierarchy = try Fixtures.hierarchy()
        let known = try Fixtures.layerDetails(scenario: "layer-details")
            + Fixtures.layerDetails(scenario: "layer-details-edge")
        var details: [UInt64: LayerDetail] = [:]
        for node in hierarchy.nodes {
            var detail = LayerDetail(
                layerID: node.id, status: .ok, solo: nil, group: nil, attributeGroups: [],
                constraints: try Fixtures.constraints(of: node.id))
            for part in known where part.layerID == node.id && part.status != .layerNotFound {
                detail.solo = part.solo ?? detail.solo
                detail.group = part.group ?? detail.group
                if !part.attributeGroups.isEmpty { detail.attributeGroups = part.attributeGroups }
            }
            details[node.id] = detail
        }
        return Self(icon: icon, hierarchy: hierarchy, details: details)
    }

    /// What a `GetLayerDetails` gets: each layer in the order asked, with only the parts
    /// asked for.
    public func answer(_ request: GetLayerDetails) -> [LayerDetail] {
        request.requests.map { asked in
            guard var detail = details[asked.layerID] ?? archived?.detail(of: asked.layerID) else {
                return LayerDetail(
                    layerID: asked.layerID, status: .layerNotFound, solo: nil, group: nil,
                    attributeGroups: [], constraints: [])
            }
            if !asked.wantSolo { detail.solo = nil }
            if !asked.wantGroup { detail.group = nil }
            if !asked.wantAttributes { detail.attributeGroups = [] }
            if !asked.wantConstraints { detail.constraints = [] }
            return detail
        }
    }

    /// The most decompressed pixels one chunk carries (P-DET-06).
    public static let chunkPixelLimit = 16 * 1024 * 1024

    /// `answer(_:)` in chunks of at most `chunkPixelLimit` decompressed pixels, in order; a
    /// layer whose images alone are larger has a chunk to itself. Always at least one chunk.
    public func answerChunks(_ request: GetLayerDetails) -> [[LayerDetail]] {
        var chunks: [[LayerDetail]] = [[]]
        var pixels = 0
        for detail in answer(request) {
            let size = [detail.solo, detail.group].reduce(0) { sum, image in
                sum + (image.map { Int($0.bytesPerRow) * Int($0.pixelHeight) } ?? 0)
            }
            if !chunks[chunks.count - 1].isEmpty, pixels + size > Self.chunkPixelLimit {
                chunks.append([])
                pixels = 0
            }
            chunks[chunks.count - 1].append(detail)
            pixels += size
        }
        return chunks
    }

    /// What a `SetAttribute` gets, as `editing` says; an edit that is applied changes this
    /// responder.
    public mutating func edit(_ request: SetAttribute) -> Body {
        func failure(_ code: ErrorCode) -> Body { .error(ServerError(code: code, message: nil)) }
        guard editing == .apply else { return failure(.attributeNotEditable) }
        guard var detail = details[request.layerID] else { return failure(.layerNotFound) }
        for (g, group) in detail.attributeGroups.enumerated() {
            guard let a = group.attributes.firstIndex(where: { $0.id == request.attributeID })
            else { continue }
            let attribute = group.attributes[a]
            guard attribute.editable else { return failure(.attributeNotEditable) }
            if let value = request.value {
                guard value.kind == attribute.valueKind else { return failure(.invalidAttributeValue) }
            } else {
                guard attribute.acceptsNil else { return failure(.invalidAttributeValue) }
            }
            detail.attributeGroups[g].attributes[a].value = request.value
            details[request.layerID] = detail
            followInHierarchy(request)
            return .setAttributeResult(
                SetAttributeResult(layerID: request.layerID, attributeGroups: detail.attributeGroups))
        }
        // The protocol has no code for an attribute the layer does not have.
        return failure(.attributeNotEditable)
    }

    private mutating func followInHierarchy(_ request: SetAttribute) {
        guard let index = hierarchy.nodes.firstIndex(where: { $0.id == request.layerID }) else {
            return
        }
        switch (request.attributeID, request.value) {
        case ("layer.opacity", .double(let opacity)):
            hierarchy.nodes[index].opacity = Float(opacity)
        case ("layer.hidden", .bool(let hidden)):
            hierarchy.nodes[index].isHidden = hidden
        case ("layer.position", .point(let position)):
            hierarchy.nodes[index].position = position
        default:
            break
        }
    }

    /// What a `GetEnvironment` gets.
    func environmentAnswer() -> Environment {
        environment?.answer ?? MockScript.unscriptedEnvironment
    }

    /// What a `SetEnvironment` gets: the new environment, or `NotSupported` for a kind the
    /// app cannot override, changing nothing (P-ENV-02, P-ENV-04). An app with no
    /// `environment` can override nothing.
    mutating func setEnvironment(_ request: SetEnvironment) -> Body {
        var environment = self.environment ?? MockEnvironment(overridable: [], own: .unspecified)
        guard request.overrides.specifiedKinds.allSatisfy(environment.overridable.contains) else {
            return .error(ServerError(code: .notSupported, message: "cannot override that"))
        }
        environment.overrides = request.overrides
        self.environment = environment
        return .environment(environment.answer)
    }

    /// A layer and all its descendants, as `GetSubtree` answers (P-HIER-10). Nil for a layer
    /// that is not in the hierarchy.
    func subtree(of id: UInt64) -> Hierarchy? {
        guard let start = hierarchy.nodes.firstIndex(where: { $0.id == id }) else { return nil }
        var inside: Set<UInt64> = [id]
        var nodes = [hierarchy.nodes[start]]
        // Pre-order: the descendants follow the layer until the first node outside it.
        for node in hierarchy.nodes[(start + 1)...] {
            guard inside.contains(node.parentID) else { break }
            inside.insert(node.id)
            nodes.append(node)
        }
        return Hierarchy(nodes: nodes, keyWindowID: hierarchy.keyWindowID)
    }
}

/// An app's trait environment as a `MockResponder` keeps it (P-ENV-01).
public struct MockEnvironment: Equatable, Sendable {
    /// What the app can override, in the server's order.
    public var overridable: [TraitKind]
    /// The key window's traits without overrides.
    public var own: Traits
    /// What the client has set on this connection.
    public var overrides = Traits.unspecified

    public init(overridable: [TraitKind], own: Traits) {
        self.overridable = overridable
        self.own = own
    }

    /// The `environment` fixtures' app (Protocol/fixtures/README.md): an iPhone in portrait,
    /// Light, Large, Left to Right, Compact width, Regular height. On iOS 17 it can
    /// override every kind; before, only the appearance.
    public static func iPhone(overridable: [TraitKind] = TraitKind.allCases) -> Self {
        Self(
            overridable: overridable,
            own: Traits(
                userInterfaceStyle: .light, contentSizeCategory: .large,
                layoutDirection: .leftToRight, horizontalSizeClass: .compact,
                verticalSizeClass: .regular))
    }

    public var answer: Environment {
        Environment(overrides: overrides, current: own.overridden(by: overrides), overridable: overridable)
    }
}
