import AppKit

/// One library shipped with the app, as `Resources/Acknowledgements/acknowledgements.json`
/// lists it, with the text of its licence (C-MENU-03).
struct Acknowledgement: Decodable, Equatable {
    let name: String
    /// The package's identity in `Package.resolved`.
    let identity: String
    let version: String
    let url: String
    /// The licence's name.
    let license: String
    /// The licence's full text, a file next to the list.
    let file: String
}

/// The standard About panel: the app's icon, name, version and build, the copyright line
/// (`NSHumanReadableCopyright`, which the panel reads itself), and as credits the licence, the
/// source code and the acknowledgements (C-MENU-03).
@MainActor
public enum AboutPanel {
    public static var licenseLine: String { localized("about.license") }

    /// What `orderFrontStandardAboutPanel(options:)` is given, from an Info.plist's keys.
    /// Public for the app's own tests, which read the running app's.
    public static func options(
        info: [String: Any], icon: NSImage?
    ) -> [NSApplication.AboutPanelOptionKey: Any] {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits()]
        options[.applicationName] = info["CFBundleName"]
        let version = AppVersion(info: info)
        options[.applicationVersion] = version.version
        options[.version] = version.build
        options[.applicationIcon] = icon
        return options
    }

    /// The libraries, in the order the list has them, each with its licence's text. Empty when
    /// the list cannot be read; the test sees to it that it can.
    static func acknowledgements() -> [(Acknowledgement, String)] {
        guard let folder = Bundle.module.url(forResource: "Acknowledgements", withExtension: nil),
              let data = try? Data(contentsOf: folder.appendingPathComponent("acknowledgements.json")),
              let list = try? JSONDecoder().decode([Acknowledgement].self, from: data)
        else { return [] }
        return list.map { library in
            let text = try? String(
                contentsOf: folder.appendingPathComponent(library.file), encoding: .utf8)
            return (library, text ?? "")
        }
    }

    /// The panel's credits: the licence, the source code, then each library.
    static func credits() -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let bold = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let mono = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular)
        let credits = NSMutableAttributedString()
        func append(_ text: String, _ font: NSFont, link: String? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.labelColor,
            ]
            attributes[.link] = link.flatMap(URL.init(string:))
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }
        append(licenseLine + "\n", body)
        append(localized("about.sourceCode"), body)
        append(Links.repository.absoluteString, body, link: Links.repository.absoluteString)
        append("\n\n" + localized("about.acknowledgements") + "\n", bold)
        for (library, text) in acknowledgements() {
            append("\n\(library.name) \(library.version)\n", bold)
            append(library.url, body, link: library.url)
            append("\n\(library.license)\n\n", body)
            append(text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n", mono)
        }
        return credits
    }
}

extension WindowCoordinator {
    /// Cutaway › About Cutaway (C-MENU-03).
    @objc func showAbout(_ sender: Any?) {
        let app = NSApplication.shared
        app.orderFrontStandardAboutPanel(
            options: AboutPanel.options(
                info: Bundle.main.infoDictionary ?? [:], icon: app.applicationIconImage))
        app.activate()
    }
}
