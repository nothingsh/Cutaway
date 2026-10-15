import AppKit
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The toolbar's app capsule in an app's window (C-WIN-06): where it is, what it shows as the
/// inspection goes, and what its parts do.
final class AppCapsuleTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    @MainActor
    private func window(
        savedNoticeDuration: Duration = .seconds(4)
    ) throws -> (InspectorWindowController, InspectionStore, AppCapsuleView) {
        let store = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let inspector = InspectorWindowController(
            location: .simulator(port: 48160), entry: nil, store: store,
            savedNoticeDuration: savedNoticeDuration)
        addTeardownBlock { @MainActor in inspector.close() }
        return (inspector, store, try XCTUnwrap(inspector.appCapsule))
    }

    @MainActor
    func test_C_ARCH_02_savingCountsAndTheSaveButtonCancelsThenShowsTheFile() async throws {
        let (_, store, capsule) = try window(savedNoticeDuration: .milliseconds(50))
        var cancelled = 0
        var revealed: [URL] = []
        capsule.onCancelSave = { cancelled += 1 }
        capsule.onReveal = { revealed.append($0) }

        store.archiveSave = .saving(completed: 3, total: 9)
        XCTAssertEqual(capsule.subtitleButton.title, "Saving 3 / 9")
        XCTAssertEqual(capsule.progressBar.fraction, 1.0 / 3, accuracy: 1e-9)
        XCTAssertFalse(capsule.refreshButton.isEnabled)
        XCTAssertTrue(capsule.saveButton.isEnabled)
        XCTAssertTrue(capsule.saveButton.showsFill, "pressed while saving")
        XCTAssertEqual(capsule.saveButton.toolTip, "Cancel Saving")
        capsule.saveButton.performClick(nil)
        XCTAssertEqual(cancelled, 1)

        let url = URL(fileURLWithPath: "/tmp/Demo.cutaway")
        store.archiveSave = .saved(url)
        XCTAssertEqual(capsule.subtitleButton.title, "Saved \u{00B7} Show in Finder")
        XCTAssertTrue(capsule.subtitleButton.isEnabled)
        XCTAssertFalse(capsule.saveButton.showsFill)
        XCTAssertEqual(capsule.saveButton.toolTip, "Show in Finder")
        capsule.saveButton.performClick(nil)
        capsule.subtitleButton.performClick(nil)
        XCTAssertEqual(revealed, [url, url])

        // A few seconds later it goes back to the device.
        let dismissed = await Wait.until { await MainActor.run { store.archiveSave == .idle } }
        XCTAssertTrue(dismissed, "still \(store.archiveSave)")
        XCTAssertFalse(capsule.subtitleButton.isEnabled)
        XCTAssertEqual(capsule.saveButton.toolTip, "Save Archive (\u{2318}S)")
    }

    @MainActor
    func test_C_ARCH_02_anotherSaveKeepsItsSavedForItsOwnTime() async throws {
        let (_, store, _) = try window(savedNoticeDuration: .milliseconds(150))
        let first = URL(fileURLWithPath: "/tmp/First.cutaway")
        let second = URL(fileURLWithPath: "/tmp/Second.cutaway")
        store.archiveSave = .saved(first)
        try await Task.sleep(for: .milliseconds(100))
        store.archiveSave = .saved(second)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.archiveSave, .saved(second), "the first one's time is not the second's")
    }
}
