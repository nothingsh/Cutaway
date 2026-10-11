import CutawayModel

extension InspectionText {
    /// The interface's words, in its language (C-LOC-01). Given to every inspection the
    /// interface makes.
    static var interface: InspectionText {
        InspectionText(
            untitledLayer: localized("layer.untitled"),
            undoActionName: { localized("undo.change", $0) })
    }
}

extension LayerTree {
    /// The layer's title as the interface shows it: its class name, or "Layer" in the
    /// interface's language for a layer without one (C-HIER-01, C-LOC-01).
    func displayTitle(of id: UInt64) -> String {
        title(of: id) ?? localized("layer.untitled")
    }

    /// The title in a file's name, which stays in English whatever the interface's language.
    func fileTitle(of id: UInt64) -> String {
        title(of: id) ?? "Layer"
    }
}
