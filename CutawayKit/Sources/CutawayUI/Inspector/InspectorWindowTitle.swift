import CutawayScene
import CutawayWire
import Foundation

/// What an inspector window's title bar says, and the names it offers for the files saved
/// from it.
struct InspectorWindowTitle: Equatable {
    var title: String
    var subtitle: String

    /// An app's window (C-WIN-01): the app's name, and its device and system under it.
    init(app info: AppInfo?) {
        title = AppEntryPresentation.name(of: info)
        subtitle = AppEntryPresentation.deviceLine(info) ?? ""
    }

    /// An archive's window (C-ARCH-05): its file's name is the title; the app, its device and
    /// when it was saved are under it, the date written as the region writes it (C-LOC-02).
    init(archive url: URL, app: AppInfo, savedAt: Date, locale: Locale = .current) {
        let date = savedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
        let saved = localized("archive.subtitle.saved", date)
        subtitle = [AppEntryPresentation.name(of: app), AppEntryPresentation.deviceLine(app), saved]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
        title = url.deletingPathExtension().lastPathComponent
    }

    /// The name a new archive is offered: the app's, and the local time to the minute. A file
    /// name has no colons.
    static func archiveName(appName: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "\(appName) \(formatter.string(from: date))"
    }

    /// "CardView 4", or "CardView 4 with Sublayers". In English whatever the interface's
    /// language, as the archive's name is.
    static func screenshotName(title: String, layerID: UInt64, kind: TextureKey.Kind) -> String {
        "\(title) \(layerID)" + (kind == .group ? " with Sublayers" : "")
    }
}
