import Combine
import CutawayTransport
import CutawayWire
import Foundation

/// The attributes of the selected layer (C-ATTR-01 to C-ATTR-03).
///
/// They are asked for one layer at a time and apart from the screenshots: a `GetLayerDetails`
/// that wants the attributes and no image, sent as soon as a layer is selected. Selecting
/// another layer cancels it. Answers are kept until the next hierarchy is taken (a round);
/// in a new round the selected layer's old answer stays shown until its new one arrives.
///
/// `InspectionStore` owns it and tells it what it needs to know: the selection, whether the
/// inspection is open, whether a hierarchy is on its way, new rounds, the app's state and
/// whether the server can change attributes.
///
/// It also changes attributes (C-ATTR-04 to C-ATTR-08): `set(_:to:continuous:)` sends a
/// `SetAttribute`, at most one at a time for each attribute, and the answer replaces the
/// layer's attributes. Changes that succeed can be undone through `undoManager`. The changes
/// themselves go through `editor`; what an answer means for the attributes held is decided
/// here.
@MainActor
public final class AttributesStore: ObservableObject {
    public enum State: Equatable, Sendable {
        /// No layer is selected.
        case none
        /// The selected layer's attributes are on their way and none are held.
        case loading
        /// The selected layer's attributes, in the order they arrived, empty when it has none;
        /// and its constraints in the server's order (C-LAYOUT-01). `constraints` is nil when
        /// the server cannot give them (P-HELLO-04). Whether the layer backs a view, and so
        /// has constraints at all, is for whoever holds the tree to say.
        case loaded([AttributeGroup], constraints: [LayoutConstraint]? = nil)
        /// The app says the selected layer does not exist (P-DET-02).
        case layerGone
        /// The app is not in the foreground (P-APP-01). Asked again when it is.
        case appNotActive
        /// A timeout, another error, or an answer that left the layer out.
        case failed
    }

    /// For the selected layer.
    @Published public private(set) var state: State = .none
    /// Whether attributes may be changed: the server speaks 0.3 or later (P-HELLO-04) and the
    /// app is active (P-APP-01). The connection is the window's business (C-WIN-03).
    @Published public private(set) var canEdit = false
    /// The changes under way and the ones that failed, by attribute (C-ATTR-06).
    @Published public private(set) var edits: [AttributeKey: EditStatus] = [:]
    /// The changes that succeeded, to undo and redo (C-ATTR-08). Its groups are opened and
    /// closed by the editor, one to a change.
    public var undoManager: UndoManager { editor.undoManager }

    /// The name of a change in the Edit menu, from its attribute's title. The interface words
    /// it: the model has no text of its own (C-LOC-01).
    let undoActionName: @Sendable (String) -> String

    private enum Answer: Equatable {
        case details([AttributeGroup], constraints: [LayoutConstraint])
        case gone
    }

    private enum Outcome {
        case answered(LayerDetail)
        /// The stream completed without the layer, against P-DET-01.
        case leftOut
        case failed(any Error)
    }

    private let source: any InspectionSource
    /// The selected layer: the one `state` is about. Set only by `select(_:newRound:)`, from
    /// the inspection's selection.
    public private(set) var selectedID: UInt64?
    private var isOpen = false
    private(set) var isTreeLoading = false
    private var round: UInt64 = 0
    /// Answers by layer, with the round they belong to.
    private var answers: [UInt64: (round: UInt64, answer: Answer)] = [:]
    /// How the last request for the selected layer failed. Cleared when the selection changes
    /// or a new request starts.
    private var failure: State?
    /// A request under way: which one, for which layer, the active generation it was made
    /// under, and the task that reads it.
    private struct Fetch {
        let token: UInt64
        let layerID: UInt64
        let generation: UInt64
        let task: Task<Void, Never>
    }

    /// The request under way.
    private var fetch: Fetch?
    /// Goes up each time the app reports it is active. A request remembers the value it was
    /// made under: an `AppNotActive` failure made under an earlier one is out of date.
    private var activeGeneration: UInt64 = 0
    /// The task of the latest request, cancelled or not. The next request waits for it, so
    /// that a cancelled request's `Cancel` goes out before the next request does.
    private var lastTask: Task<Void, Never>?
    private var nextToken: UInt64 = 1
    /// How many requests were started. For tests.
    private(set) var requestsStarted = 0
    /// The round of an answer that is shown but asked for again: no round has this number.
    private static let outdated = UInt64.max
    /// Whether the server gives constraints: it speaks 0.4 or later (P-HELLO-04).
    private var constraintsSupported = false
    /// The inspection that owns the store, which the changes go through (C-DET-06).
    weak var delegate: (any AttributesStoreDelegate)?
    /// Sends the changes, one at a time for each attribute, and keeps what can be undone.
    private(set) lazy var editor = AttributeEditor(
        source: source, undoActionName: undoActionName, delegate: self)

    convenience init(
        session: Session, undoActionName: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.init(source: session, undoActionName: undoActionName)
    }

    init(source: any InspectionSource, undoActionName: @escaping @Sendable (String) -> String = { $0 }) {
        self.source = source
        self.undoActionName = undoActionName
    }

    /// The layers whose answers are held, of this round or the last. For tests.
    var heldLayerIDs: Set<UInt64> {
        Set(answers.keys)
    }

    /// The selected layer changed. The inspection that owns the store says so, and only it:
    /// the store never chooses a layer of its own. A request for the layer selected before
    /// is cancelled.
    ///
    /// With `newRound`, a new hierarchy was taken too, with `id` selected in it. What is held
    /// is out of date: only the selected layer's answer stays, to be shown until its new one
    /// arrives. Told together, so that the selection's request is made once, in the new round.
    func select(_ id: UInt64?, newRound tree: LayerTree? = nil) {
        if let tree {
            round += 1
            answers = answers.filter { $0.key == id && tree.contains($0.key) }
        } else {
            guard id != selectedID else { return }
        }
        selectedID = id
        failure = nil
        cancelFetch()
        // The state first: whoever follows the edits finds the new layer's attributes.
        update()
        editor.clearFailedEdits()
        editor.finishOpenChanges()
    }

    /// The inspection opened or closed. Closing cancels the request under way and forgets
    /// what can be undone: it belongs to this visit (C-ATTR-08).
    func setOpen(_ open: Bool) {
        isOpen = open
        if !open {
            cancelFetch()
            editor.finishOpenChanges()
            editor.forgetSteps()
        }
        update()
    }

    /// Whether changes wait for something else to end: an archive being saved (C-ARCH-02).
    func setEditingSuspended(_ suspended: Bool) {
        editor.setSuspended(suspended)
        updateCanEdit()
    }

    /// What the source can do (P-HELLO-04): whether attributes can be changed, and whether
    /// constraints come.
    func setCapabilities(_ capabilities: InspectionCapabilities) {
        setEditingSupported(capabilities.canEditAttributes)
        setConstraintsSupported(capabilities.givesConstraints)
    }

    /// Whether the server can change attributes (P-HELLO-04). Tests set it alone.
    func setEditingSupported(_ supported: Bool) {
        editor.setSupported(supported)
        updateCanEdit()
    }

    /// Whether the server gives constraints (P-HELLO-04). Below 0.4 the session leaves them
    /// out of the requests, and the state has none. Tests set it alone.
    func setConstraintsSupported(_ supported: Bool) {
        constraintsSupported = supported
        publish()
    }

    /// Whether a hierarchy is on its way. Nothing is asked for meanwhile: the new tree starts
    /// a new round, which asks again; asking for the old tree's would only be cancelled.
    func setTreeLoading(_ loading: Bool) {
        isTreeLoading = loading
        update()
    }

    /// The app reported a new state. When it is active, what is missing is asked for again.
    func appStateDidChange(_ appState: AppState) {
        editor.setAppActive(appState == .active)
        updateCanEdit()
        guard appState == .active else { return }
        activeGeneration += 1
        if failure == .appNotActive { failure = nil }
        update()
    }

    /// The user asked again for the selected layer's attributes. Asks once more when the last
    /// request failed; does nothing while one is under way or an answer is held.
    func retry() {
        guard failure != nil else { return }
        failure = nil
        update()
    }

    // MARK: - Asking

    private func update() {
        fetchIfNeeded()
        publish()
    }

    /// Asks for the selected layer's attributes and constraints when it has no answer in this
    /// round, its last request did not fail, nothing is under way, the inspection is open and
    /// no hierarchy is on its way; with constraints, also not while one of its attributes is
    /// being changed (C-LAYOUT-01). A failure is cleared by `retry()`, a new selection or a
    /// new round; "not active" also by the app becoming active.
    private func fetchIfNeeded() {
        guard isOpen, !isTreeLoading, fetch == nil, failure == nil, let id = selectedID,
              answers[id]?.round != round,
              !(constraintsSupported && editor.isChanging(layer: id))
        else { return }
        let token = nextToken
        nextToken += 1
        requestsStarted += 1
        // The session leaves the constraints out for a server below 0.4.
        let request = GetLayerDetails(
            requests: [LayerDetailRequest(
                layerID: id, wantSolo: false, wantGroup: false, wantAttributes: true,
                wantConstraints: true)],
            maxTextureDimension: 0)
        let previous = lastTask
        let task = Task { [weak self, source] in
            await previous?.value
            // Cancelled before it was sent: there is nothing to send and nothing to cancel.
            guard !Task.isCancelled else { return }
            let stream = await source.layerDetails(request)
            var outcome = Outcome.leftOut
            do {
                // The whole stream is read. A request for one layer ends right after its
                // detail; stopping early would send a Cancel that races the end.
                for try await details in stream.chunks {
                    if case .leftOut = outcome,
                       let detail = details.first(where: { $0.layerID == id })
                    {
                        outcome = .answered(detail)
                    }
                }
            } catch {
                outcome = .failed(error)
            }
            if Task.isCancelled {
                // Awaited here, so that the Cancel goes out before the next request.
                await stream.cancel()
                return
            }
            self?.finishFetch(token, outcome)
        }
        fetch = Fetch(token: token, layerID: id, generation: activeGeneration, task: task)
        lastTask = task
    }

    /// The end of a request. Ignored for one that was cancelled or replaced.
    private func finishFetch(_ token: UInt64, _ outcome: Outcome) {
        guard let current = fetch, current.token == token else { return }
        fetch = nil
        switch outcome {
        case .answered(let detail):
            // A layer whose capture failed still brings its attributes (P-DET-03). No image is
            // asked for, so an `ok` answer without groups means it has none.
            let answer: Answer = detail.status == .layerNotFound
                ? .gone : .details(detail.attributeGroups, constraints: detail.constraints)
            answers[current.layerID] = (round, answer)
        case .leftOut:
            failure = .failed
        case .failed(let error):
            switch error as? RequestError {
            case .appNotActive where current.generation != activeGeneration:
                // The app became active after this request went out, and that news came
                // first: asked again rather than shown.
                update()
                return
            case .appNotActive:
                failure = .appNotActive
            case .disconnected:
                // The app is about to leave the list, and this inspection with it (C-CONN-07).
                break
            default:
                failure = .failed
            }
        }
        publish()
    }

    private func cancelFetch() {
        guard let current = fetch else { return }
        fetch = nil
        current.task.cancel()
    }

    private func publish() {
        let new: State
        if let id = selectedID {
            if let failure {
                new = failure
            } else {
                switch answers[id]?.answer {
                case .details(let groups, let constraints):
                    new = .loaded(groups, constraints: constraintsSupported ? constraints : nil)
                case .gone: new = .layerGone
                case nil: new = .loading
                }
            }
        } else {
            new = .none
        }
        if new != state { state = new }
    }
}

// MARK: - Changing attributes

extension AttributesStore {
    /// Changes an attribute (C-ATTR-06). `continuous` while a drag goes on; the drag's last
    /// value comes with `continuous` false. At most one `SetAttribute` is on its way for an
    /// attribute; values that come meanwhile wait, and only the latest is sent once the
    /// answer is in (C-ATTR-07). Nothing happens while `canEdit` is false. The panel checks
    /// what was typed; a value with a number that is not finite is still never sent, whatever
    /// made it: a component left as it came from the app, say (C-ATTR-09). Only the selected
    /// layer's attributes are set: an editor left over from a layer selected before (a color
    /// well the color panel still drives) changes nothing. Its drag already ended with the
    /// selection; undo and redo do not come through here.
    public func set(_ key: AttributeKey, to value: AttributeValue?, continuous: Bool) {
        guard key.layerID == selectedID else { return }
        editor.set(key, to: value, continuous: continuous)
    }

    /// `set(_:to:continuous:)` for any layer, as an undo or redo changes one. Internal for
    /// tests whose change is about what follows it, not about the selection.
    func setRegardlessOfSelection(_ key: AttributeKey, to value: AttributeValue?, continuous: Bool) {
        editor.set(key, to: value, continuous: continuous)
    }

    /// Ends a drag without a new value: the color panel says nothing when the mouse goes up,
    /// so the panel ends the change after a pause (C-ATTR-08: a drag is one step). Once the
    /// last answer is in, the change is one step to undo.
    public func finish(_ key: AttributeKey) {
        editor.finish(key)
    }

    private func updateCanEdit() {
        let new = editor.canEdit
        if new != canEdit { canEdit = new }
    }
}

// MARK: - What the editor's answers mean

extension AttributesStore: AttributeEditorDelegate {
    func editor(_ editor: AttributeEditor, heldAttribute key: AttributeKey) -> Attribute? {
        guard case .details(let groups, _) = answers[key.layerID]?.answer else { return nil }
        return AttributeEditor.attribute(key, in: groups)
    }

    func editorWillSendChange(_ editor: AttributeEditor) -> Task<Void, Never>? {
        delegate?.attributesStoreWillSendChange(self)
    }

    /// What the app read back is what the panel shows (P-SET-01, P-SET-04). It belongs to
    /// this round, like an answer to `GetLayerDetails`.
    func editor(_ editor: AttributeEditor, changed key: AttributeKey, to result: SetAttributeResult) {
        // Other layers' may have changed with it (a tint colour passes down, a layout moves
        // frames): asked for again when they are selected (C-DET-06). The selected one's stay
        // shown until its new ones come, as in a new round.
        var kept: [UInt64: (round: UInt64, answer: Answer)] = [:]
        if let id = selectedID, id != key.layerID, let held = answers[id] {
            kept[id] = (Self.outdated, held.answer)
        }
        // The answer brings no constraints, and the change may have moved them in or out of
        // effect (P-LAYOUT-06): the old ones stay shown, and are asked for again once the
        // layer's changes are over (C-LAYOUT-01). Without old ones nothing is kept: the layer
        // loads when it is selected, rather than showing it has none. A request under way for
        // the layer was made before this change.
        if !constraintsSupported {
            kept[key.layerID] = (round, .details(result.attributeGroups, constraints: []))
        } else if case .details(_, let held)? = answers[key.layerID]?.answer {
            kept[key.layerID] = (Self.outdated, .details(result.attributeGroups, constraints: held))
        }
        answers = kept
        if constraintsSupported, fetch?.layerID == key.layerID { cancelFetch() }
        // The new attributes first: a row that stops sending shows them, not the old.
        update()
        delegate?.attributesStore(self, didChangeLayer: key.layerID)
    }

    /// The panel says it, as for an answer to `GetLayerDetails` (P-DET-02).
    func editor(_ editor: AttributeEditor, foundLayerGone id: UInt64) {
        answers[id] = (round, .gone)
        publish()
    }

    func editorDidFailToChange(_ editor: AttributeEditor) {
        delegate?.attributesStoreDidFailToChange(self)
    }

    /// The store publishes what the editor holds, as soon as it changes.
    func editorDidChangeEdits(_ editor: AttributeEditor) {
        edits = editor.edits
    }

    func editorDidSettle(_ editor: AttributeEditor) {
        update()
    }
}

/// What the changes tell the inspection that owns the store (C-DET-06).
@MainActor
protocol AttributesStoreDelegate: AnyObject {
    /// A `SetAttribute` is about to go out: screenshots asked for before it would hold it up
    /// (P-REQ-06). Returns what the `SetAttribute` waits for: the task that ends once what
    /// was cancelled has said so on the wire, or nil.
    func attributesStoreWillSendChange(_ store: AttributesStore) -> Task<Void, Never>?
    /// A `SetAttribute` for this layer succeeded; the app has laid out by then (P-SET-05).
    func attributesStore(_ store: AttributesStore, didChangeLayer id: UInt64)
    /// A `SetAttribute` failed.
    func attributesStoreDidFailToChange(_ store: AttributesStore)
}
