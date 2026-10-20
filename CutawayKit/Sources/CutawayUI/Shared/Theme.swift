import AppKit
import CutawayRender

/// The constants the interface is drawn with: spacing, corner radii, fonts and the SF Symbols
/// it uses. Colours are the system's semantic colours, so light and dark follow the system.
enum Theme {
    enum Spacing {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    /// How firmly the inspector's texts keep their width: less than the split view holds the
    /// panes' widths with (250 and 260), so that a long text is cut short or wraps instead of
    /// widening the inspector and moving the preview beside it.
    static let textGivesWay = NSLayoutConstraint.Priority(rawValue: 200)

    enum Radius {
        static let control: CGFloat = 6
        static let panel: CGFloat = 8
        /// A 36-point app icon.
        static let appIcon: CGFloat = 8
    }

    @MainActor
    enum Font {
        static let body = NSFont.systemFont(ofSize: 13)
        static let bodyEmphasized = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let caption = NSFont.systemFont(ofSize: 11)
        static let captionEmphasized = NSFont.systemFont(ofSize: 11, weight: .semibold)
        static let digits = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        static let captionDigits = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        /// A constraint's equation (C-LAYOUT-02).
        static let constraint = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    /// The names of every SF Symbol the interface uses. A misspelt name makes no image and no
    /// error, so a test loads each of them.
    enum Symbol {
        static let appPlaceholder = "app.dashed"
        static let inactive = "pause.circle.fill"
        static let background = "moon.fill"
        static let incompatible = "exclamationmark.triangle.fill"
        static let twoD = "square"
        static let threeD = "square.3.layers.3d"
        /// The toolbar's Environment button (C-ENV-01): the appearance is what is changed most.
        static let environment = "circle.lefthalf.filled"
        static let notActive = "moon.zzz.fill"
        static let screenshotsFailed = "exclamationmark.triangle.fill"
        static let disconnected = "cable.connector.slash"
        static let expandMenu = "list.bullet.indent"
        static let leaveFocus = "xmark.circle.fill"
        static let noMatches = "magnifyingglass"
        static let showHidden = "eye"
        static let hideHidden = "eye.slash"
        static let refresh = "arrow.clockwise"
        static let editFailed = "exclamationmark.triangle.fill"
        static let saveArchive = "archivebox"
        static let archiveFailed = "exclamationmark.triangle.fill"
        /// The app capsule's save button while saving, and once saved (C-WIN-06).
        static let cancelSave = "stop.fill"
        static let saved = "checkmark"
        static let showApps = "chevron.down"
        /// Above the hierarchy's status text (C-HIER-01).
        static let hierarchyNotActive = "moon.zzz"
        static let hierarchyFailed = "exclamationmark.triangle"
        static let emptyTree = "rectangle.dashed"
        /// The mark of a hidden layer's row (C-HIER-03).
        static let hiddenLayer = "eye.slash"
        /// The open triangle of a sticky row (C-HIER-13).
        static let stickyRowOpen = "chevron.down"
        /// The settings' pages (C-PREF-01).
        static let generalSettings = "gearshape"
        static let previewSettings = "square.3.layers.3d"
        static let projectsSettings = "folder"
        /// Beside a class declared in the app's project folder (C-SRC-03).
        static let openInXcode = "hammer"
        /// A linked project folder that is gone (C-SRC-01).
        static let missingFolder = "exclamationmark.triangle.fill"

        static let all = [
            appPlaceholder, inactive, background, incompatible, twoD, threeD, notActive,
            screenshotsFailed,
            disconnected, expandMenu, leaveFocus, noMatches, showHidden, hideHidden, refresh,
            editFailed, saveArchive, archiveFailed, cancelSave, saved, showApps,
            hierarchyNotActive, hierarchyFailed, emptyTree, hiddenLayer, stickyRowOpen,
            generalSettings, previewSettings, projectsSettings, openInXcode, missingFolder,
        ]
    }

    /// The fill of a row under the pointer, in the hierarchy list (C-HIER-15) and the app list
    /// (C-LIST-04).
    static var hoverFill: NSColor { .quaternaryLabelColor }

    /// The other ends of constraints (C-LAYOUT-04, C-LAYOUT-06): the preview's marks, so that
    /// the panel's constraint icon and chips read as the same thing. Taken from the render
    /// style of the appearance it is drawn in.
    static var constraintEnd: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return RenderStyle.preview(dark: dark).endBorder.nsColor
        }
    }

    /// An SF Symbol at a point size and weight, or nil when the system does not have it.
    static func symbol(
        _ name: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
        scale: NSImage.SymbolScale = .medium, description: String? = nil
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: size, weight: weight, scale: scale)
        return NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
    }

    /// An SF Symbol drawn at its own aspect ratio, centred in a square of `side` points. A path
    /// control draws its items' images into squares and stretches one that is not square.
    static func squareSymbol(_ name: String, size: CGFloat, side: CGFloat) -> NSImage? {
        guard let symbol = self.symbol(name, size: size) else { return nil }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let scale = min(side / symbol.size.width, side / symbol.size.height, 1)
            let width = symbol.size.width * scale
            let height = symbol.size.height * scale
            symbol.draw(in: NSRect(
                x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
            return true
        }
        image.isTemplate = true
        return image
    }
}
