import AppKit
import CutawayModel
import CutawayProjects
import XCTest

@testable import CutawayUI

/// The settings window's General page (C-LOC-01): the language pop-up, Restore Defaults, and the
/// sheet that offers to restart into a new language.
@MainActor
final class LanguageSettingsPageTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults()
    private var restarts = 0
    /// The system's languages the page reads when a choice is made.
    private var system = ["en-US"]

    override func setUp() async throws {
        suiteName = "LanguageSettingsPageTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        restarts = 0
        system = ["en-US"]
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var window: SettingsWindowController?

    private var language: LanguageSetting {
        get throws { try XCTUnwrap(window?.generalPage.language) }
    }

    /// The settings window on its General page, in English as the tests run, reading this
    /// test's system languages.
    private func page() throws -> GeneralSettingsViewController {
        let settingsName = suiteName + ".settings"
        let settingsSuite = try XCTUnwrap(UserDefaults(suiteName: settingsName))
        let controller = SettingsWindowController(
            settings: AppSettings(defaults: settingsSuite),
            language: WindowCoordinator.languageSetting(defaults: defaults, domain: suiteName),
            projects: ProjectSources(folders: ProjectFolders(defaults: settingsSuite)),
            shownLanguage: "en", systemPreferences: { [weak self] in self?.system ?? [] },
            restart: { [weak self] in self?.restarts += 1 })
        window = controller
        addTeardownBlock { @MainActor in
            controller.close()
            settingsSuite.removePersistentDomain(forName: settingsName)
        }
        controller.showWindow(nil)
        controller.generalPage.view.layoutSubtreeIfNeeded()
        return controller.generalPage
    }

    private static func descendant(of view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let match = descendant(of: subview, identifier: identifier) { return match }
        }
        return nil
    }

    func test_C_LOC_01_theRestartWaitsForTheAppToEndThenOpensIt() {
        let arguments = Relaunch.arguments(waitingFor: 4321, thenOpening: "/Applications/Cut away.app")
        XCTAssertEqual(arguments.first, "-c")
        XCTAssertEqual(Array(arguments.suffix(2)), ["4321", "/Applications/Cut away.app"])
        let script = arguments[1]
        XCTAssertTrue(script.contains(#"kill -0 "$1""#))
        XCTAssertTrue(script.hasSuffix(#"open "$2""#))
        XCTAssertFalse(script.contains("Cut away"), "the path is a parameter, not part of the script")
    }
}
