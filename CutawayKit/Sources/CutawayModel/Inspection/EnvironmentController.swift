import CutawayTransport
import CutawayWire

/// Why the last change of the environment did not happen (C-ENV-02).
public enum EnvironmentFailure: Equatable, Sendable {
    /// The app cannot apply that combination of overrides, and changed none (P-ENV-04).
    case notSupported
    /// The app is not in the foreground (P-APP-01).
    case appNotActive
    /// A timeout, the connection, or another error.
    case other
}

/// What the environment controls show while the app's environment is known (C-ENV-01).
public struct EnvironmentControls: Equatable, Sendable {
    /// The app's last answer.
    public var environment: Environment
    /// The overrides as the controls show them: the answer's, or a change on its way.
    public var shown: Traits
    /// Whether a `SetEnvironment` is on its way.
    public var isSending: Bool
    /// Why the last change failed; cleared by the next change or `dismissFailure()`.
    public var failure: EnvironmentFailure?

    public init(
        environment: Environment, shown: Traits, isSending: Bool = false,
        failure: EnvironmentFailure? = nil
    ) {
        self.environment = environment
        self.shown = shown
        self.isSending = isSending
        self.failure = failure
    }

    /// The kinds the app can override, in a fixed order whatever the server's.
    public var overridable: [TraitKind] {
        TraitKind.allCases.filter(environment.overridable.contains)
    }

    /// Whether anything is overridden, as shown.
    public var isOverriding: Bool { !shown.specifiedKinds.isEmpty }
}

/// Where the environment controls stand (C-ENV-01, C-ENV-03).
public enum EnvironmentState: Equatable, Sendable {
    /// No controls: an archive, a version below 1.2, an app that can override nothing, or
    /// no answer yet.
    case unavailable
    case available(EnvironmentControls)
    /// The connection is gone: the app put its own traits back (P-ENV-03).
    case lost

    public var controls: EnvironmentControls? {
        if case .available(let controls) = self { return controls }
        return nil
    }
}

/// What the controller asks of the inspection, and tells it.
@MainActor
protocol EnvironmentControllerDelegate: AnyObject {
    /// Whether a change may go out now: not while an archive is saved (C-ARCH-02).
    var mayChangeEnvironment: Bool { get }
    /// A `SetEnvironment` is about to go out. Returns a task that ends once what must go out
    /// first has (the screenshots' `Cancel`, P-REQ-06).
    func environmentWillSend(_ controller: EnvironmentController) -> Task<Void, Never>?
    /// A `SetEnvironment` ended. `refresh` when the environment changed and nothing more is
    /// to be sent: the whole tree is taken again (C-ENV-02).
    func environmentController(_ controller: EnvironmentController, didAnswer refresh: Bool)
    func environmentStateChanged(_ controller: EnvironmentController)
}

/// The app's trait environment and the overrides Cutaway sets on it (C-ENV-01 to C-ENV-03):
/// asked for once when the inspection opens, changed one `SetEnvironment` at a time.
@MainActor
final class EnvironmentController {
    private let source: any InspectionSource
    private weak var delegate: (any EnvironmentControllerDelegate)?

    private(set) var state = EnvironmentState.unavailable {
        didSet {
            if state != oldValue { delegate?.environmentStateChanged(self) }
        }
    }

    /// Whether `GetEnvironment` went out: only once in an inspection.
    private var asked = false
    /// The latest overrides asked for while one change was on its way (C-ENV-02).
    private var waiting: Traits?
    /// How many `SetEnvironment` were sent. For tests.
    private(set) var sentCount = 0

    init(source: any InspectionSource, delegate: any EnvironmentControllerDelegate) {
        self.source = source
        self.delegate = delegate
    }

    // MARK: - Asking

    /// Asks for the environment when the source can override it (C-ENV-03). Ends once the
    /// answer is in, or there is none; a failure leaves no controls.
    func load() async {
        guard !asked else { return }
        asked = true
        guard let capabilities = await source.capabilities, capabilities.canOverrideEnvironment,
              let environment = try? await source.environment()
        else { return }
        take(environment)
    }

    /// The app's environment, as asked for when the inspection opened: controls when it can
    /// override something. Nothing once the connection is gone.
    func take(_ environment: Environment) {
        guard state == .unavailable, !environment.overridable.isEmpty else { return }
        state = .available(EnvironmentControls(environment: environment, shown: environment.overrides))
    }

    /// The connection is gone (C-ENV-03): the controls show the app's own traits. A change
    /// on its way is not waited for.
    func connectionLost() {
        waiting = nil
        state = .lost
    }

    // MARK: - Changing

    /// Whether a change may be made now.
    var canChange: Bool {
        state.controls != nil && delegate?.mayChangeEnvironment == true
    }

    /// Overrides one kind, the others as shown (C-ENV-02). An unspecified value removes its
    /// override.
    func set(_ kind: TraitKind, to value: Traits.Value) {
        guard let controls = state.controls, canChange,
              controls.overridable.contains(kind) || value == Traits.unspecified[kind]
        else { return }
        var overrides = controls.shown
        overrides[kind] = value
        request(overrides)
    }

    /// Removes every override.
    func reset() {
        guard let controls = state.controls, controls.isOverriding else { return }
        request(.unspecified)
    }

    /// Overrides the appearance with the opposite of the one the app shows (C-MENU-05).
    func toggleAppearance() {
        guard let controls = state.controls else { return }
        let shown = controls.shown.isSpecified(.userInterfaceStyle)
            ? controls.shown.userInterfaceStyle : controls.environment.current.userInterfaceStyle
        set(.userInterfaceStyle, to: .userInterfaceStyle(shown == .dark ? .light : .dark))
    }

    /// Forgets why the last change failed.
    func dismissFailure() {
        guard var controls = state.controls, controls.failure != nil else { return }
        controls.failure = nil
        state = .available(controls)
    }

    private func request(_ overrides: Traits) {
        guard var controls = state.controls, controls.shown != overrides || controls.failure != nil
        else { return }
        controls.shown = overrides
        controls.failure = nil
        if controls.isSending {
            // Only the latest goes, once the answer is in.
            waiting = overrides
            state = .available(controls)
            return
        }
        controls.isSending = true
        state = .available(controls)
        send(overrides)
    }

    private func send(_ overrides: Traits) {
        sentCount += 1
        let before = delegate?.environmentWillSend(self)
        Task { [weak self, source] in
            await before?.value
            let result: Result<Environment, any Error>
            do {
                result = .success(try await source.setEnvironment(overrides))
            } catch {
                result = .failure(error)
            }
            self?.finish(result)
        }
    }

    private func finish(_ result: Result<Environment, any Error>) {
        guard var controls = state.controls else {
            // The connection went meanwhile.
            delegate?.environmentController(self, didAnswer: false)
            return
        }
        switch result {
        case .success(let environment):
            controls.environment = environment
            if let next = waiting, next != environment.overrides {
                waiting = nil
                controls.shown = next
                state = .available(controls)
                // Sent before this one is told ended, so screenshots do not start between.
                send(next)
                delegate?.environmentController(self, didAnswer: false)
                return
            }
            waiting = nil
            controls.shown = environment.overrides
            controls.isSending = false
            state = .available(controls)
            delegate?.environmentController(self, didAnswer: true)
        case .failure(let error):
            // The app changed nothing (P-ENV-04); what waited was made on top of the failed one.
            waiting = nil
            controls.shown = controls.environment.overrides
            controls.isSending = false
            controls.failure = Self.failure(for: error)
            state = .available(controls)
            delegate?.environmentController(self, didAnswer: false)
        }
    }

    private static func failure(for error: any Error) -> EnvironmentFailure {
        switch error as? RequestError {
        case .notSupported: .notSupported
        case .appNotActive: .appNotActive
        default: .other
        }
    }
}
