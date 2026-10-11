import AppKit
import CutawayModel
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

    private func pick(_ title: String, on page: GeneralSettingsViewController) {
        let button = page.languageButton
        button.selectItem(withTitle: title)
        button.sendAction(button.action, to: button.target)
    }

    private func restoreButton(_ page: GeneralSettingsViewController) throws -> NSButton {
        try XCTUnwrap(
            Self.descendant(of: page.view, identifier: GeneralSettingsViewController.restoreIdentifier)
                as? NSButton)
    }

    private static func descendant(of view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let match = descendant(of: subview, identifier: identifier) { return match }
        }
        return nil
    }

    /// Ends the restart sheet with one of its buttons.
    private func answer(_ index: Int, on page: GeneralSettingsViewController) throws {
        let alert = try XCTUnwrap(page.restartAlert, "no restart sheet")
        alert.buttons[index].performClick(nil)
        XCTAssertNil(page.restartAlert)
    }

    func test_C_LOC_01_thePopUpListsTheSystemDefaultAndEachLanguageInItself() throws {
        let page = try page()
        let titles = page.languageButton.itemArray.map { $0.isSeparatorItem ? "-" : $0.title }
        XCTAssertEqual(titles, ["System Default", "-", "English", "简体中文", "繁體中文", "日本語", "한국어"])
        XCTAssertEqual(page.languageButton.titleOfSelectedItem, "System Default")
        XCTAssertEqual(page.languageButton.accessibilityIdentifier(), GeneralSettingsViewController.languageIdentifier)
        XCTAssertFalse(try restoreButton(page).isEnabled)
    }

    func test_C_LOC_01_choosingAnotherLanguageKeepsItAndOffersToRestart() throws {
        let page = try page()
        pick("日本語", on: page)
        XCTAssertEqual(try language.choice, "ja")
        XCTAssertEqual(
            defaults.persistentDomain(forName: suiteName)?[LanguageSetting.key] as? [String], ["ja"])
        XCTAssertTrue(try restoreButton(page).isEnabled)
        let alert = try XCTUnwrap(page.restartAlert)
        XCTAssertEqual(alert.messageText, "Restart Cutaway to use 日本語?")
        XCTAssertEqual(alert.buttons.map(\.title), ["Restart Now", "Later"])

        try answer(0, on: page)
        XCTAssertEqual(restarts, 1)
    }

    func test_C_LOC_01_laterKeepsTheChoiceWithoutRestarting() throws {
        let page = try page()
        pick("한국어", on: page)
        try answer(1, on: page)
        XCTAssertEqual(restarts, 0)
        XCTAssertEqual(try language.choice, "ko")
        XCTAssertEqual(page.languageButton.titleOfSelectedItem, "한국어")
    }

    func test_C_LOC_01_aChoiceThatKeepsTheLanguageShownAsksNothing() throws {
        let page = try page()
        pick("English", on: page)
        XCTAssertNil(page.restartAlert)
        XCTAssertEqual(try language.choice, "en")

        // Back to the system's, which is English here.
        pick("System Default", on: page)
        XCTAssertNil(page.restartAlert)
        XCTAssertNil(try language.choice)
    }

    func test_C_LOC_01_systemDefaultOffersToRestartWhenTheSystemIsInAnotherLanguage() throws {
        let page = try page()
        pick("English", on: page)
        system = ["zh-Hant-TW", "en-US"]
        try restoreButton(page).performClick(nil)
        XCTAssertNil(try language.choice)
        XCTAssertEqual(page.languageButton.titleOfSelectedItem, "System Default")
        XCTAssertEqual(page.restartAlert?.messageText, "Restart Cutaway to use 繁體中文?")
        try answer(1, on: page)
        XCTAssertFalse(try restoreButton(page).isEnabled)
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
