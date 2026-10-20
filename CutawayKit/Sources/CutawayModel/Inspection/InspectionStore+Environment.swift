import CutawayWire

extension InspectionStore {
    // MARK: - The environment (C-ENV-01 to C-ENV-03)

    /// Whether the environment can be changed now: it is known, and no archive is saved.
    public var canChangeEnvironment: Bool { environmentController.canChange }

    /// Overrides one kind of trait, the others as they are shown; an unspecified value
    /// removes its override (C-ENV-02).
    public func setEnvironment(_ kind: TraitKind, to value: Traits.Value) {
        environmentController.set(kind, to: value)
    }

    /// Removes every override (C-ENV-02).
    public func resetEnvironment() {
        environmentController.reset()
    }

    /// Overrides the appearance with the opposite of the one the app shows (C-MENU-05).
    public func toggleAppearance() {
        environmentController.toggleAppearance()
    }

    /// Takes an environment as `GetEnvironment` would have answered. For tests that have no
    /// server.
    package func takeEnvironment(_ environment: Environment) {
        environmentController.take(environment)
    }

    /// Forgets why the last change of the environment failed.
    public func dismissEnvironmentFailure() {
        environmentController.dismissFailure()
    }
}

extension InspectionStore: EnvironmentControllerDelegate {
    var mayChangeEnvironment: Bool { isOpen && !isSavingArchive }

    /// A change of the environment goes ahead of the screenshots, as a change of an
    /// attribute does (C-DET-06, P-REQ-06).
    func environmentWillSend(_ controller: EnvironmentController) -> Task<Void, Never>? {
        // A refresh still waiting for the last change is not wanted: this one's comes after.
        cancelEnvironmentSettle()
        changesOnTheirWay += 1
        return fetcher.cancel()
    }

    /// The app may have rebuilt its interface: the whole tree is taken again, and with it the
    /// screenshots and the attributes (C-ENV-02). Not at once: the app is given
    /// `environmentSettleDelay` to redraw, and no screenshots are asked for meanwhile, as they
    /// would show the look it had (reported by the user, 2026-10-20: Wikipedia changes its
    /// colours 0.3 s after the change).
    func environmentController(_ controller: EnvironmentController, didAnswer refresh: Bool) {
        guard refresh, isOpen else {
            endChange()
            fetchNext()
            return
        }
        let delay = environmentSettleDelay
        guard delay > .zero else {
            endChange()
            self.refresh()
            return
        }
        environmentSettle = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            environmentSettle = nil
            endChange()
            self.refresh()
        }
    }

    /// A refresh that waits for the app to redraw is not made: another change goes out, the
    /// inspection closes or the connection went. Its change is no longer on its way.
    func cancelEnvironmentSettle() {
        guard let settle = environmentSettle else { return }
        settle.cancel()
        environmentSettle = nil
        endChange()
    }

    private func endChange() {
        if changesOnTheirWay > 0 { changesOnTheirWay -= 1 }
    }

    func environmentStateChanged(_ controller: EnvironmentController) {
        environment = controller.state
    }
}
