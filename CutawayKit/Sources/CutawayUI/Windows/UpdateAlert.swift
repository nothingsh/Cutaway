import AppKit

/// The alert that tells what Check for Updates… found (C-DIST-02).
@MainActor
enum UpdateAlert {
    /// For an update, the first button opens its release page.
    static func make(_ result: UpdateCheckResult, currentVersion: String) -> NSAlert {
        let alert = NSAlert()
        switch result {
        case .available(let version, _):
            alert.messageText = localized("update.available.title", version)
            alert.informativeText = localized("update.available.text", currentVersion)
            alert.addButton(withTitle: localized("update.available.view"))
            alert.addButton(withTitle: localized("update.later"))
        case .upToDate(let version):
            alert.messageText = localized("update.upToDate.title")
            alert.informativeText = localized("update.upToDate.text", version)
        case .failed(let failure):
            alert.alertStyle = .warning
            alert.messageText = localized("update.failed.title")
            alert.informativeText = text(failure)
        }
        return alert
    }

    private static func text(_ failure: UpdateCheckFailure) -> String {
        switch failure {
        case .network(let description): description
        case .status(let status): localized("update.failed.status", status)
        case .unreadable: localized("update.failed.unreadable")
        case .unknownVersion: localized("update.failed.unknownVersion")
        }
    }
}

extension WindowCoordinator {
    /// Cutaway › Check for Updates… (C-DIST-02).
    @objc func checkForUpdates(_ sender: Any?) {
        checkForUpdatesNow()
    }

    /// Checks, then tells what it found. While a check is under way, choosing the item again
    /// asks nothing more: that check's alert is the one answer.
    @discardableResult
    func checkForUpdatesNow() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self, let result = await updateChecker.check() else { return }
            showUpdateResult(result)
        }
    }

    func showUpdateResult(_ result: UpdateCheckResult) {
        NSApp.activate()
        let response = runAlert(UpdateAlert.make(result, currentVersion: updateChecker.currentVersion))
        if case .available(_, let page) = result, response == .alertFirstButtonReturn {
            openURL(page)
        }
    }
}
