import CutawayTransport
import CutawayWire
import Foundation

/// What the editor asks of the attributes store, and tells it. What an answer means for the
/// attributes shown is the store's to decide; the editor only sequences the changes and
/// keeps what can be undone.
@MainActor
protocol AttributeEditorDelegate: AnyObject {
    /// The attribute as the panel holds it now, if it does.
    func editor(_ editor: AttributeEditor, heldAttribute key: AttributeKey) -> Attribute?
    /// A `SetAttribute` is about to go out. Returns what it waits for, or nil (C-DET-06).
    func editorWillSendChange(_ editor: AttributeEditor) -> Task<Void, Never>?
    /// A `SetAttribute` succeeded: its answer replaces the layer's attributes (P-SET-01).
    /// Told before the change ends, so that a row that stops sending shows the new value.
    func editor(_ editor: AttributeEditor, changed key: AttributeKey, to result: SetAttributeResult)
    /// The app says the changed layer does not exist (P-DET-02).
    func editor(_ editor: AttributeEditor, foundLayerGone id: UInt64)
    /// A `SetAttribute` failed; the row says why, if it is the row's to say.
    func editorDidFailToChange(_ editor: AttributeEditor)
    /// `edits` changed.
    func editorDidChangeEdits(_ editor: AttributeEditor)
    /// A change ended, or an answer was taken: what waited for it may go on (C-LAYOUT-01).
    func editorDidSettle(_ editor: AttributeEditor)
}

/// Changes attributes (C-ATTR-04 to C-ATTR-08): at most one `SetAttribute` on its way for an
/// attribute, with only the latest value waiting meanwhile; a drag is one change; changes
/// that succeed are steps of `undoManager`. Whether a change may start at all, and for which
/// layer, is the attributes store's to say.
@MainActor
final class AttributeEditor {
    /// A change of one attribute: from its first value to the answer to its last. A drag
    /// sends many values and is one change.
    private struct Change {
        /// The value before the change, for undo, and the attribute's title.
        var before: AttributeValue?
        var title: String
        /// A change the user made, or one an undo or redo made.
        var step: EditStep?
        var isSending = false
        /// The latest value that waits for the one on its way to be answered.
        var waiting: AttributeValue??
        /// The latest value of all.
        var latest: AttributeValue?
        /// Whether the last value has come: the drag ended, or it was not a drag.
        var isFinished: Bool
    }

    private let source: any InspectionSource
    /// Weak: a task may hold the editor while it delivers an answer after the attributes are
    /// gone, which then does nothing.
    private weak var delegate: (any AttributeEditorDelegate)?
    /// The name of a change in the Edit menu, from its attribute's title (C-LOC-01).
    private let undoActionName: @Sendable (String) -> String

    /// The changes that succeeded, to undo and redo (C-ATTR-08). Its groups are opened and
    /// closed here, one to a change.
    let undoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()

    /// The changes under way and the ones that failed, by attribute (C-ATTR-06).
    private(set) var edits: [AttributeKey: EditStatus] = [:] {
        didSet { delegate?.editorDidChangeEdits(self) }
    }

    private var editingSupported = false
    /// Until the app says otherwise: a connection starts with the app active (P-EVT-02).
    private var isAppActive = true
    /// Set while an archive is saved: no changes meanwhile (C-ARCH-02).
    private var isSuspended = false
    /// Set once the connection is gone: no changes from then on (C-WIN-03).
    private var isDisconnected = false
    private var changes: [AttributeKey: Change] = [:]
    /// The steps the undo manager has actions for. It does not keep its targets.
    private var steps: [EditStep] = []
    /// The last `SetAttribute` sent; the next goes once it is answered.
    private var lastSend: Task<Void, Never>?

    init(
        source: any InspectionSource, undoActionName: @escaping @Sendable (String) -> String,
        delegate: any AttributeEditorDelegate
    ) {
        self.source = source
        self.undoActionName = undoActionName
        self.delegate = delegate
    }

    /// Whether attributes may be changed: the source is an app (C-ATTR-04), the app is active
    /// (P-APP-01), no archive is being saved (C-ARCH-02), and the connection holds (C-WIN-03).
    var canEdit: Bool {
        editingSupported && isAppActive && !isSuspended && !isDisconnected
    }

    func setSupported(_ supported: Bool) {
        editingSupported = supported
    }

    func setAppActive(_ active: Bool) {
        isAppActive = active
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
    }

    func connectionLost() {
        isDisconnected = true
    }

    /// Whether one of the layer's attributes is being changed.
    func isChanging(layer id: UInt64) -> Bool {
        changes.keys.contains { $0.layerID == id }
    }

    /// Changes an attribute, as `AttributesStore.set(_:to:continuous:)` describes.
    func set(_ key: AttributeKey, to value: AttributeValue?, continuous: Bool) {
        guard canEdit else {
            // A drag that was under way when editing stopped still ends, without its value.
            if !continuous { finish(key) }
            return
        }
        let failure: EditFailure? = if !(value?.isFinite ?? true) {
            .notFinite
        } else if let violation = violation(of: value, for: key) {
            .outOfRange(violation)
        } else {
            nil
        }
        if let failure {
            // The row shows the value from before, as after any change that failed. A drag
            // under way keeps its last good value and ends when it would have.
            if changes[key] == nil {
                edits[key] = .failed(failure)
            } else if !continuous {
                finish(key)
            }
            return
        }
        // A continuous change (the colour panel) that gives the value it gave last sends
        // nothing more; its end ends it.
        if let current = changes[key], !current.isFinished, current.step == nil,
           current.latest == value
        {
            if !continuous { finish(key) }
            return
        }
        change(key, to: value, continuous: continuous, step: nil)
    }

    /// Ends the drags that are still open, as a new selection, a new round or leaving does:
    /// none of them is left showing as sending, or without its undo (C-ATTR-08).
    func finishOpenChanges() {
        for (key, change) in changes where !change.isFinished { finish(key) }
    }

    /// Ends a drag without a new value, as `AttributesStore.finish(_:)` describes.
    func finish(_ key: AttributeKey) {
        guard var current = changes[key], !current.isFinished else { return }
        current.isFinished = true
        guard !current.isSending else {
            changes[key] = current
            return
        }
        changes[key] = nil
        edits[key] = nil
        let after = delegate?.editor(self, heldAttribute: key)?.value ?? current.latest
        if current.step == nil, after != current.before {
            record(EditStep(key: key, before: current.before, after: after, title: current.title))
        }
        // The layer's constraints may be asked for again now (C-LAYOUT-01).
        delegate?.editorDidSettle(self)
    }

    /// Forgets what can be undone: it belongs to one visit (C-ATTR-08).
    func forgetSteps() {
        undoManager.removeAllActions()
        steps.removeAll()
    }

    func clearFailedEdits() {
        let kept = edits.filter {
            if case .failed = $0.value { return false }
            return true
        }
        if kept.count != edits.count { edits = kept }
    }

    private func change(
        _ key: AttributeKey, to value: AttributeValue?, continuous: Bool, step: EditStep?
    ) {
        if var current = changes[key] {
            current.latest = value
            current.isFinished = !continuous
            // An undo or redo that comes while the attribute is changing takes over: the
            // change becomes that step's, and records nothing of its own.
            if let step { current.step = step }
            if current.isSending {
                current.waiting = .some(value)
                changes[key] = current
            } else {
                changes[key] = current
                send(key, value)
            }
        } else {
            let attribute = delegate?.editor(self, heldAttribute: key)
            changes[key] = Change(
                before: attribute?.value, title: attribute?.title ?? key.attributeID,
                step: step, latest: value, isFinished: !continuous)
            send(key, value)
        }
        edits[key] = .sending(value)
    }

    private func send(_ key: AttributeKey, _ value: AttributeValue?) {
        changes[key]?.isSending = true
        changes[key]?.waiting = nil
        let request = SetAttribute(layerID: key.layerID, attributeID: key.attributeID, value: value)
        let cancelling = delegate?.editorWillSendChange(self)
        // One after another: the app takes them in order (P-REQ-06), and one that waits for a
        // cancel must not be overtaken by the next (C-DET-06).
        let previous = lastSend
        lastSend = Task { [weak self, source] in
            await previous?.value
            await cancelling?.value
            let outcome: Result<SetAttributeResult, any Error>
            do {
                outcome = .success(try await source.setAttribute(request))
            } catch {
                outcome = .failure(error)
            }
            self?.finishChange(key, outcome)
        }
    }

    private func finishChange(_ key: AttributeKey, _ outcome: Result<SetAttributeResult, any Error>) {
        // The attributes are gone: nothing is shown, and nothing more is sent.
        guard delegate != nil else {
            changes[key] = nil
            return
        }
        guard var current = changes[key] else { return }
        current.isSending = false
        switch outcome {
        case .success(let result):
            delegate?.editor(self, changed: key, to: result)
            if let waiting = current.waiting {
                changes[key] = current
                send(key, waiting)
            } else if !current.isFinished {
                // A drag that goes on: the row keeps the dragged value.
                changes[key] = current
            } else {
                changes[key] = nil
                edits[key] = nil
                let after = Self.attribute(key, in: result.attributeGroups)?.value ?? current.latest
                if current.step == nil, after != current.before {
                    record(EditStep(
                        key: key, before: current.before, after: after, title: current.title))
                }
            }
        case .failure(let error):
            changes[key] = nil
            if let step = current.step {
                // An undo or redo that failed takes its step out of the stack (C-ATTR-08).
                undoManager.removeAllActions(withTarget: step)
                steps.removeAll { $0 === step }
            }
            switch error as? RequestError {
            case .layerNotFound:
                // The panel says it, as for an answer to `GetLayerDetails` (P-DET-02).
                delegate?.editor(self, foundLayerGone: key.layerID)
                edits[key] = nil
            case .disconnected:
                // The window says it (C-WIN-03).
                edits[key] = nil
            case .invalidAttributeValue:
                edits[key] = .failed(.rejected)
            case .attributeNotEditable:
                edits[key] = .failed(.notEditable)
            case .appNotActive:
                edits[key] = .failed(.appNotActive)
            default:
                edits[key] = .failed(.noAnswer)
            }
            delegate?.editorDidFailToChange(self)
        }
        delegate?.editorDidSettle(self)
    }

    /// Registers a change that succeeded, as one step of the undo manager (C-ATTR-08).
    private func record(_ step: EditStep) {
        steps.append(step)
        undoManager.beginUndoGrouping()
        register(step, towardBefore: true)
        undoManager.endUndoGrouping()
    }

    /// Registers the way to set the step's attribute to its value before (or after), and,
    /// once that is under way, the way back.
    private func register(_ step: EditStep, towardBefore: Bool) {
        undoManager.registerUndo(withTarget: step) { [weak self] step in
            MainActor.assumeIsolated {
                guard let self else { return }
                let value = towardBefore ? step.before : step.after
                // A value outside the limits the attribute has now is not sent: the step
                // fails and leaves the stack, as one whose layer is gone (C-ATTR-13).
                if let violation = self.violation(of: value, for: step.key) {
                    self.undoManager.removeAllActions(withTarget: step)
                    self.steps.removeAll { $0 === step }
                    self.edits[step.key] = .failed(.outOfRange(violation))
                    self.delegate?.editorDidFailToChange(self)
                    return
                }
                // Registered while the undo manager undoes or redoes: it is the way back.
                self.register(step, towardBefore: !towardBefore)
                self.change(step.key, to: value, continuous: false, step: step)
            }
        }
        undoManager.setActionName(undoActionName(step.title))
    }

    /// The component of a value outside the limits the attribute has now, as the panel last
    /// received them (P-SET-07). The panel checks first; this holds for every way a value
    /// takes, undo and redo among them.
    private func violation(of value: AttributeValue?, for key: AttributeKey) -> LimitViolation? {
        delegate?.editor(self, heldAttribute: key)?.limitViolation(of: value)
    }

    static func attribute(_ key: AttributeKey, in groups: [AttributeGroup]) -> Attribute? {
        for group in groups {
            if let attribute = group.attributes.first(where: { $0.id == key.attributeID }) {
                return attribute
            }
        }
        return nil
    }
}

/// One change that can be undone: an attribute, its value before and after, and its title for
/// the Edit menu (C-ATTR-08). The undo manager registers its actions with the step as their
/// target, so that a step whose undo or redo failed can be taken out alone.
private final class EditStep {
    let key: AttributeKey
    let before: AttributeValue?
    let after: AttributeValue?
    let title: String

    init(key: AttributeKey, before: AttributeValue?, after: AttributeValue?, title: String) {
        self.key = key
        self.before = before
        self.after = after
        self.title = title
    }
}
