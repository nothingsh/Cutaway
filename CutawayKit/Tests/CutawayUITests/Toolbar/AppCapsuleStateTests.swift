import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// What the toolbar's app capsule shows as the inspection goes (C-WIN-06), with the
/// screenshots' progress (C-DET-02) and saving an archive (C-ARCH-02).
@MainActor
final class AppCapsuleStateTests: XCTestCase {
    private static let device = "iPhone 18 Pro \u{00B7} iOS 27.0"

    private func state(
        progress: DetailProgress = .none, notice: InspectionStore.Notice? = nil,
        save: ArchiveSaveState = .idle, disconnected: Bool = false, removed: Int? = nil
    ) -> AppCapsuleState {
        AppCapsuleState(
            subtitle: Self.device, detailProgress: progress, notice: notice, archiveSave: save,
            isDisconnected: disconnected, removed: removed, locale: Locale(identifier: "en_US"))
    }

    func test_C_DET_04_aNoticeOrALostConnectionStopsTheScreenshotsProgress() {
        let progress = DetailProgress(completed: 12, total: 40)
        XCTAssertEqual(state(progress: progress, notice: .appNotActive).subtitle, Self.device)
        XCTAssertNil(state(progress: progress, notice: .appNotActive).progress)
        XCTAssertNil(state(progress: progress, disconnected: true).progress)
    }

    func test_C_WIN_06_disconnectedRefreshAndSaveAreOff() {
        let lost = state(disconnected: true)
        XCTAssertEqual(lost.subtitle, Self.device)
        XCTAssertFalse(lost.canRefresh)
        XCTAssertFalse(lost.canSave)
    }

    func test_C_LIVE_05_layersThatWentAreToldOverTheProgressButNotOverASave() {
        let progress = DetailProgress(completed: 12, total: 40)
        let removed = state(progress: progress, removed: 1_234)
        XCTAssertEqual(removed.subtitle, "1,234 removed")
        XCTAssertEqual(removed.progress, 0.3, "the hairline goes on")
        XCTAssertEqual(removed.tone, .progress)
        XCTAssertEqual(state(removed: 3).subtitle, "3 removed")
        XCTAssertEqual(state(progress: progress).subtitle, "Screenshots 12 / 40")
        XCTAssertEqual(
            state(progress: progress, save: .saving(completed: 1, total: 4), removed: 3).subtitle,
            "Saving 1 / 4")
    }
}
