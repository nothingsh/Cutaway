import CutawayModel
import Foundation
import XCTest

@testable import CutawayUI

/// What the panels over the preview say, and the distances written over its drawing:
/// C-DET-02, C-DET-04, C-DET-07, C-WIN-03, C-WIN-04, C-ARCH-02, C-ARCH-06, C-PREV-10.
final class PreviewPaneTextTests: XCTestCase {
    func test_C_DET_02_progressReadsCompletedOfTotalUntilEveryScreenshotIsSettled() {
        XCTAssertEqual(
            PreviewPaneText.progressText(DetailProgress(completed: 12, total: 40)), "12 / 40")
        XCTAssertNil(PreviewPaneText.progressText(DetailProgress(completed: 0, total: 0)))
        XCTAssertNil(PreviewPaneText.progressText(DetailProgress(completed: 7, total: 7)))
    }

    func test_C_DET_04_theNoticesSayWhatHappened() {
        XCTAssertEqual(
            PreviewPaneText.noticeText(.appNotActive, appName: "Demo"),
            "Demo is not active. Loading continues when it comes to the foreground.")
        XCTAssertEqual(
            PreviewPaneText.noticeText(.screenshotsFailed, appName: "Demo"),
            "Some screenshots could not be loaded. Refresh to try again.")
        XCTAssertEqual(
            PreviewPaneText.noticeText(.layersFailed, appName: "Demo"),
            "The layers could not be loaded again. Refresh to try again.")
        XCTAssertNil(PreviewPaneText.noticeText(nil, appName: "Demo"))
    }

    func test_C_DET_07_theNoticeSaysTheLayerIsGone() {
        XCTAssertEqual(
            PreviewPaneText.noticeText(.layerGone, appName: "Demo"),
            "The layer is no longer in Demo. Refresh to load all layers again.")
    }

    func test_C_WIN_04_theDisconnectedNoticeSaysWhetherTheWindowWaits() {
        XCTAssertEqual(
            PreviewPaneText.disconnectedText(appName: "Demo", waiting: true),
            "Lost the connection to Demo. Waiting for it to come back\u{2026}")
        XCTAssertEqual(
            PreviewPaneText.disconnectedText(appName: "Demo", waiting: false),
            "Lost the connection to Demo.")
    }

    func test_C_ARCH_02_savedNamesTheArchiveWithoutItsExtension() {
        XCTAssertEqual(
            PreviewPaneText.savedText(URL(fileURLWithPath: "/tmp/Demo.cutaway")),
            "Saved \u{201C}Demo\u{201D}")
    }

    func test_C_ARCH_02_aFailedSaveSaysWhy() {
        XCTAssertEqual(
            PreviewPaneText.archiveFailureText(.appNotActive, appName: "Demo"),
            "The archive wasn\u{2019}t saved: Demo went to the background.")
        XCTAssertEqual(
            PreviewPaneText.archiveFailureText(.disconnected, appName: "Demo"),
            "The archive wasn\u{2019}t saved: the connection to Demo was lost.")
        XCTAssertEqual(
            PreviewPaneText.archiveFailureText(.incompleteAnswer, appName: "Demo"),
            "The archive wasn\u{2019}t saved: Demo didn\u{2019}t send every layer.")
        XCTAssertEqual(
            PreviewPaneText.archiveFailureText(.writeFailed("Disk full."), appName: "Demo"),
            "The archive wasn\u{2019}t saved: the file couldn\u{2019}t be written. Disk full.")
    }

    func test_C_ARCH_06_aFailedExportSaysWhy() {
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.layerGone, appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: the layer is no longer in Demo.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.notCaptured, appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: Demo couldn\u{2019}t capture this layer.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.appNotActive, appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: Demo went to the background.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.disconnected, appName: "Unnamed app"),
            "The screenshot wasn\u{2019}t exported: the connection to Unnamed app was lost.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.other, appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: Demo didn\u{2019}t send it.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.writeFailed("Disk full."), appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: the file couldn\u{2019}t be written. Disk full.")
    }

    func test_C_PREV_10_aDistanceHasOneDecimalAtMostAndNoTrailingZero() {
        XCTAssertEqual(PreviewPaneText.distanceText(26.5), "26.5")
        XCTAssertEqual(PreviewPaneText.distanceText(68), "68")
        XCTAssertEqual(PreviewPaneText.distanceText(15.057713659400522), "15.1")
        XCTAssertEqual(PreviewPaneText.distanceText(0.96), "1")
        XCTAssertEqual(PreviewPaneText.distanceText(720), "720")
    }
}
