import AppKit
import Combine
import CutawayModel
import CutawayProjects

/// What the attribute panel follows besides its store: the selected layer, the hierarchy (for
/// the names of the layers constraints relate), the connection and the project folder's index
/// (C-SRC-04, C-SRC-05).
@MainActor
struct AttributesPanelInputs {
    var layer: AnyPublisher<LayerSummary?, Never> = Just(nil).eraseToAnyPublisher()
    var tree: AnyPublisher<LayerTree, Never> = Just(.empty).eraseToAnyPublisher()
    var connection: AnyPublisher<InspectionStore.Connection, Never> = Just(.live).eraseToAnyPublisher()
    var projectIndex: AnyPublisher<ProjectIndex?, Never> = Just(nil).eraseToAnyPublisher()
}

/// What the attribute panel asks of the inspection.
@MainActor
struct AttributesPanelActions {
    /// Asks for the attributes again after they failed (C-ATTR-01).
    var retry: () -> Void = {}
    /// Selects the layer at the other end of a constraint (C-LAYOUT-03), an ancestor
    /// (C-ATTR-16), or one a value refers to (C-ATTR-28).
    var showLayer: (UInt64) -> Void = { _ in }
    /// Hovers the layer an ancestor or a reference names, or none (C-ATTR-16, C-ATTR-28,
    /// C-HIER-15).
    var hoverLayer: (UInt64?) -> Void = { _ in }
    /// Hovers the other end of a constraint, or none (C-LAYOUT-06).
    var hoverConstraintEnd: (ConstraintRow.End?) -> Void = { _ in }
    /// Marks the other ends of the constraints the pointer is on, or stops (C-LAYOUT-07).
    var pointConstraints: (ConstraintPointer) -> Void = { _ in }
    /// Puts a text on the pasteboard.
    var copy: @MainActor (String) -> Void = TextPasteboard.copyToGeneral
    /// Opens where classes are declared, from the button that asked (C-SRC-03).
    var openInXcode: @MainActor ([SourceLocation], NSView) -> Void = { _, _ in }
}

extension InspectionStore {
    /// What the attribute panel of this inspection follows; `project` is the way to the app's
    /// project folder (C-SRC-03), nil for none.
    func attributesPanelInputs(project: ProjectLookup?) -> AttributesPanelInputs {
        AttributesPanelInputs(
            layer: project.map { selectedLayerSummary(index: $0.index) } ?? selectedLayerSummary,
            tree: $tree.eraseToAnyPublisher(), connection: $connection.eraseToAnyPublisher(),
            projectIndex: project?.index ?? Just(nil).eraseToAnyPublisher())
    }

    /// What the attribute panel of this inspection does. Pointing at layers and constraints
    /// does nothing once the connection is gone: the store takes none of it then.
    func attributesPanelActions(project: ProjectLookup?) -> AttributesPanelActions {
        AttributesPanelActions(
            retry: { [weak self] in self?.retryAttributes() },
            showLayer: { [weak self] id in self?.showLayer(id) },
            hoverLayer: { [weak self] id in self?.hover(id) },
            hoverConstraintEnd: { [weak self] end in
                self?.hoverConstraintEnd(end?.mark, layerID: end?.layerID)
            },
            pointConstraints: { [weak self] pointer in
                switch pointer {
                case .entered(let indices, let stresses):
                    self?.pointConstraints(indices, stresses: stresses)
                case .left(let indices):
                    self?.leaveConstraints(indices)
                }
            },
            openInXcode: { [weak project] locations, button in project?.open(locations, from: button) })
    }
}
