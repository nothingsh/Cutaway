// MARK: - Editing (protocol 0.3)

/// Changes one attribute of one layer (P-SET-01, P-SET-02).
public struct SetAttribute: Equatable, Sendable {
    public var layerID: UInt64
    public var attributeID: String?
    /// Nil sets the attribute to nil.
    public var value: AttributeValue?

    public init(layerID: UInt64, attributeID: String?, value: AttributeValue?) {
        self.layerID = layerID
        self.attributeID = attributeID
        self.value = value
    }
}

/// The answer to `SetAttribute`: all the layer's attribute groups, read after the change
/// (P-SET-01).
public struct SetAttributeResult: Equatable, Sendable {
    public var layerID: UInt64
    public var attributeGroups: [AttributeGroup]

    public init(layerID: UInt64, attributeGroups: [AttributeGroup]) {
        self.layerID = layerID
        self.attributeGroups = attributeGroups
    }
}

/// Asks for a layer and all its descendants. Answered with `Hierarchy` (P-HIER-10).
public struct GetSubtree: Equatable, Sendable {
    public var rootID: UInt64

    public init(rootID: UInt64) {
        self.rootID = rootID
    }
}
