/// The words the model needs from the interface (C-LOC-01): the model has no text of its own,
/// and what it must name it names as the interface does. Given once, when an inspection is
/// made; the defaults say nothing, for tests.
public struct InspectionText: Sendable {
    /// What the interface calls a layer without a class name; the search finds such a layer
    /// by it (C-HIER-04).
    public var untitledLayer: String
    /// The name of a change in the Edit menu, from its attribute's title (C-ATTR-08).
    public var undoActionName: @Sendable (String) -> String

    public init(
        untitledLayer: String = "", undoActionName: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.untitledLayer = untitledLayer
        self.undoActionName = undoActionName
    }
}
