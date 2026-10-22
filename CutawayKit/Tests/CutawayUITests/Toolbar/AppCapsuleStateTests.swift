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
        save: ArchiveSaveState = .idle, disconnected: Bool = false
    ) -> AppCapsuleState {
        AppCapsuleState(
            subtitle: Self.device, detailProgress: progress, notice: notice, archiveSave: save,
            isDisconnected: disconnected, locale: Locale(identifier: "en_US"))
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
}
