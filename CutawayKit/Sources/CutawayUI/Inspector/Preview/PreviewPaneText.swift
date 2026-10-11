import CutawayModel
import Foundation

/// What the panels over the preview say, and the values written over its drawing.
enum PreviewPaneText {
    // MARK: - The panels

    /// "Saved “Demo 2026-10-06 08.30”": the archive's name without its extension.
    static func savedText(_ url: URL) -> String {
        localized("preview.saved", url.deletingPathExtension().lastPathComponent)
    }

    /// Why a screenshot was not exported (C-ARCH-06).
    static func screenshotFailureText(
        _ failure: ScreenshotExportFailure, appName: String
    ) -> String {
        switch failure {
        case .layerGone: localized("preview.screenshot.layerGone", appName)
        case .notCaptured: localized("preview.screenshot.notCaptured", appName)
        case .appNotActive: localized("preview.screenshot.appNotActive", appName)
        case .disconnected: localized("preview.screenshot.disconnected", appName)
        case .other: localized("preview.screenshot.other", appName)
        case .writeFailed(let system): localized("preview.screenshot.writeFailed", system)
        }
    }

    /// Why an archive was not saved (C-ARCH-02).
    static func archiveFailureText(_ failure: ArchiveSaveFailure, appName: String) -> String {
        switch failure {
        case .disconnected: localized("preview.archive.disconnected", appName)
        case .appNotActive: localized("preview.archive.appNotActive", appName)
        case .incompleteAnswer: localized("preview.archive.incomplete", appName)
        case .writeFailed(let system): localized("preview.archive.writeFailed", system)
        }
    }

    /// What the notice of a lost connection says (C-WIN-03, C-WIN-04).
    static func disconnectedText(appName: String, waiting: Bool) -> String {
        waiting
            ? localized("preview.disconnected.waiting", appName)
            : localized("preview.disconnected", appName)
    }

    /// What the notice says, or nil when there is none (C-DET-04).
    static func noticeText(_ notice: InspectionStore.Notice?, appName: String) -> String? {
        switch notice {
        case .appNotActive:
            return localized("preview.notice.appNotActive", appName)
        case .screenshotsFailed:
            return localized("preview.notice.screenshotsFailed")
        case .layersFailed:
            return localized("preview.notice.layersFailed")
        case .layerGone:
            return localized("preview.notice.layerGone", appName)
        case nil:
            return nil
        }
    }

    /// "12 / 40" until every screenshot is settled, then nil (C-DET-02).
    static func progressText(_ progress: DetailProgress, locale: Locale = .current) -> String? {
        guard progress.total > 0, progress.completed < progress.total else { return nil }
        return countText(progress.completed, of: progress.total, locale: locale)
    }

    /// "1,234 / 5,000", the numbers written as the region writes them (C-LOC-02).
    static func countText(_ completed: Int, of total: Int, locale: Locale = .current) -> String {
        localized(
            "preview.progress", completed.formatted(.number.locale(locale)),
            total.formatted(.number.locale(locale)))
    }

    // MARK: - Over the drawing

    /// A distance in points, with one decimal at most and no trailing zero (C-PREV-10).
    static func distanceText(_ value: Double) -> String {
        let tenths = (value * 10).rounded()
        return tenths.truncatingRemainder(dividingBy: 10) == 0
            ? String(format: "%.0f", tenths / 10) : String(format: "%.1f", tenths / 10)
    }
}
