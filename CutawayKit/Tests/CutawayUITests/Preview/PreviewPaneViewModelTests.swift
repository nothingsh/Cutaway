import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// What the panels over the preview show, without the panels: C-DET-02, C-DET-04,
/// C-HIER-01, C-PREV-03, C-PREV-07, C-WIN-03, C-WIN-04, C-ARCH-02, C-ARCH-06.
final class PreviewPaneViewModelTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    @MainActor
    private func model() -> InspectionStore {
        InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
    }

    @MainActor
    private func viewModel(
        for model: InspectionStore, savedNoticeDuration: Duration = .seconds(4)
    ) -> PreviewPaneViewModel {
        PreviewPaneViewModel(
            store: model, appName: "Demo", savedNoticeDuration: savedNoticeDuration)
    }

    /// Everything a publisher sends while the subscription lasts.
    private final class Recorder<Value> {
        private(set) var values: [Value] = []
        private var subscription: AnyCancellable?

        init(_ publisher: AnyPublisher<Value, Never>) {
            subscription = publisher.sink { [weak self] in self?.values.append($0) }
        }

        var last: Value? { values.last }
    }

    // MARK: - The notice and the screenshots' progress

    @MainActor
    func test_C_DET_04_theNoticeAndItsSymbolFollowTheModel() {
        let model = model()
        let viewModel = viewModel(for: model)
        let notice = Recorder(viewModel.notice)
        let symbol = Recorder(viewModel.noticeSymbol)
        XCTAssertEqual(notice.values, [nil])

        model.notice = .appNotActive
        XCTAssertEqual(
            notice.last, "Demo is not active. Loading continues when it comes to the foreground.")
        XCTAssertEqual(symbol.last, .notActive)
        XCTAssertEqual(symbol.last?.name, Theme.Symbol.notActive)

        model.notice = .screenshotsFailed
        XCTAssertEqual(notice.last, "Some screenshots could not be loaded. Refresh to try again.")
        XCTAssertEqual(symbol.last, .failed)
        XCTAssertEqual(symbol.last?.name, Theme.Symbol.screenshotsFailed)

        // The same text again is not sent again.
        model.notice = .screenshotsFailed
        XCTAssertEqual(notice.values.count, 3)
    }

    @MainActor
    func test_C_WIN_03_aLostConnectionTakesThePlaceOfTheNotice() {
        let model = model()
        let viewModel = viewModel(for: model)
        let notice = Recorder(viewModel.notice)
        model.notice = .layersFailed
        XCTAssertEqual(notice.last, "The layers could not be loaded again. Refresh to try again.")
        model.connectionLost()
        XCTAssertEqual(notice.last, .some(nil))
    }

    @MainActor
    func test_C_DET_02_theProgressShowsUntilEveryScreenshotIsSettled() {
        let model = model()
        let viewModel = viewModel(for: model)
        let progress = Recorder(viewModel.progress)
        let fraction = Recorder(viewModel.fraction)
        let shown = Recorder(viewModel.progressShown)
        XCTAssertEqual(progress.values, [nil])
        XCTAssertEqual(fraction.last, 0)

        model.detailProgress = DetailProgress(completed: 12, total: 40)
        XCTAssertEqual(progress.last, "12 / 40")
        XCTAssertEqual(fraction.last, 0.3)
        XCTAssertEqual(shown.last?.0, true)
        XCTAssertEqual(shown.last?.1, false)

        // Every screenshot settled: the panel fades out.
        model.detailProgress = DetailProgress(completed: 40, total: 40)
        XCTAssertEqual(progress.last, .some(nil))
        XCTAssertEqual(fraction.last, 1)
        XCTAssertEqual(shown.last?.0, false)
        XCTAssertEqual(shown.last?.1, false)
    }

    @MainActor
    func test_C_DET_04_aNoticeTakesThePlaceOfTheProgressAtOnce() {
        let model = model()
        let viewModel = viewModel(for: model)
        let progress = Recorder(viewModel.progress)
        let shown = Recorder(viewModel.progressShown)
        model.detailProgress = DetailProgress(completed: 12, total: 40)
        model.notice = .appNotActive
        XCTAssertEqual(progress.last, .some(nil))
        XCTAssertEqual(shown.last?.0, false)
        XCTAssertEqual(shown.last?.1, true, "goes at once")
    }

    @MainActor
    func test_C_HIER_01_loadingShowsUntilTheFirstTree() throws {
        let model = model()
        let isLoading = Recorder(viewModel(for: model).isLoading)
        XCTAssertEqual(isLoading.values, [true])
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(isLoading.values, [true, false])
    }

    @MainActor
    func test_C_WIN_03_aLostConnectionStopsLoading() {
        let model = model()
        let viewModel = viewModel(for: model)
        let isLoading = Recorder(viewModel.isLoading)
        model.connectionLost()
        XCTAssertEqual(isLoading.values, [true, false])
    }

    // MARK: - The readout and the controls

    @MainActor
    func test_C_PREV_03_theReadoutIsTheHoveredLayerOrElseTheSelectedOne() throws {
        let model = model()
        let viewModel = viewModel(for: model)
        let readout = Recorder(viewModel.readout)
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(readout.last, .some(nil), "nothing hovered, nothing selected")

        model.select(3)
        XCTAssertEqual(readout.last??.title, "UILabel")
        XCTAssertEqual(readout.last??.size, "200 × 24")
        model.hover(4)
        XCTAssertEqual(readout.last??.title, "CardView")
        model.hover(nil)
        XCTAssertEqual(readout.last??.title, "UILabel")

        model.connectionLost()
        XCTAssertEqual(readout.last, .some(nil))
    }

    @MainActor
    func test_C_PREV_07_theSpacingWorksOnlyIn3DAndTheControlsOnlyWhileConnected() {
        let model = model()
        let viewModel = viewModel(for: model)
        let spacing = Recorder(viewModel.spacingIsEnabled)
        let connected = Recorder(viewModel.isConnected)
        XCTAssertEqual(spacing.last, false)
        XCTAssertEqual(connected.last, true)

        model.setPreviewMode(.threeD)
        XCTAssertEqual(spacing.last, true)

        model.connectionLost()
        XCTAssertEqual(spacing.last, false)
        XCTAssertEqual(connected.last, false)
    }

    @MainActor
    func test_C_WIN_04_theDisconnectedNoticeSaysWhetherTheWindowWaits() {
        let model = model()
        let viewModel = viewModel(for: model)
        let text = Recorder(viewModel.disconnectedText)
        XCTAssertEqual(text.last, "Lost the connection to Demo.")
        model.connectionLost(waiting: true)
        XCTAssertEqual(text.last, "Lost the connection to Demo. Waiting for it to come back\u{2026}")
    }

    // MARK: - Saving an archive and exporting a screenshot

    @MainActor
    func test_C_ARCH_02_savingShowsItsProgressThenSavedOrWhy() {
        let model = model()
        let viewModel = viewModel(for: model)
        let saving = Recorder(viewModel.saving)
        let fraction = Recorder(viewModel.archiveFraction)
        let count = Recorder(viewModel.archiveCount)
        let savedURL = Recorder(viewModel.savedURL)
        let savedText = Recorder(viewModel.savedText)
        let failure = Recorder(viewModel.failure)
        XCTAssertNil(saving.last.flatMap { $0 })
        XCTAssertEqual(savedURL.values, [nil])
        XCTAssertEqual(savedText.values, [])
        XCTAssertEqual(failure.values, [nil])

        model.archiveSave = .saving(completed: 0, total: 0)
        XCTAssertEqual(fraction.last, 0)
        XCTAssertEqual(count.last, "")
        model.archiveSave = .saving(completed: 3, total: 9)
        XCTAssertEqual(saving.last??.completed, 3)
        XCTAssertEqual(saving.last??.total, 9)
        XCTAssertEqual(fraction.last ?? 0, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(count.last, "3 / 9")

        let url = URL(fileURLWithPath: "/tmp/Demo.cutaway")
        model.archiveSave = .saved(url)
        XCTAssertNil(saving.last.flatMap { $0 })
        XCTAssertEqual(savedURL.last, url)
        XCTAssertEqual(savedText.last, "Saved \u{201C}Demo\u{201D}")

        // The last name stays while the panel fades out.
        model.archiveSave = .failed(.appNotActive)
        XCTAssertEqual(savedURL.last, .some(nil))
        XCTAssertEqual(savedText.values, ["Saved \u{201C}Demo\u{201D}"])
        XCTAssertEqual(
            failure.last, "The archive wasn\u{2019}t saved: Demo went to the background.")

        // The same state again is not sent again.
        let sent = failure.values.count
        model.archiveSave = .failed(.appNotActive)
        XCTAssertEqual(failure.values.count, sent)
    }

    @MainActor
    func test_C_ARCH_02_savedGoesAfterItsDurationUnlessAnotherSaveTookItsPlace() async {
        let model = model()
        let viewModel = viewModel(for: model, savedNoticeDuration: .milliseconds(50))
        let first = URL(fileURLWithPath: "/tmp/First.cutaway")
        let second = URL(fileURLWithPath: "/tmp/Second.cutaway")

        model.archiveSave = .saved(first)
        viewModel.dismissSaved(after: first)
        let dismissed = await Wait.until { await MainActor.run { model.archiveSave == .idle } }
        XCTAssertTrue(dismissed, "still \(model.archiveSave)")

        // Another save took its place: the first one's time running out leaves it.
        model.archiveSave = .saved(first)
        viewModel.dismissSaved(after: first)
        model.archiveSave = .saved(second)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.archiveSave, .saved(second))

        // Nothing saved any more: the wait is cancelled.
        model.archiveSave = .saved(first)
        viewModel.dismissSaved(after: first)
        viewModel.dismissSaved(after: nil)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.archiveSave, .saved(first))
    }

    @MainActor
    func test_C_ARCH_06_aFailedExportSaysWhy() {
        let model = model()
        let failure = Recorder(viewModel(for: model).screenshotFailure)
        XCTAssertEqual(failure.values, [nil])
        model.screenshotExport = .failed(.notCaptured)
        XCTAssertEqual(
            failure.last,
            "The screenshot wasn\u{2019}t exported: Demo couldn\u{2019}t capture this layer.")
        model.screenshotExport = .idle
        XCTAssertEqual(failure.last, .some(nil))
    }
}
