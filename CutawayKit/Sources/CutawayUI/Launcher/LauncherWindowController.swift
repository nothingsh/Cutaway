import AppKit
import CutawayModel
import CutawayTransport
import DeclarativeAppKit

/// The window the app starts with (C-WIN-01): the app's icon and name, the apps that can be
/// inspected, and a line that says the search goes on (C-LIST-04).
public final class LauncherWindowController: NSWindowController {
    static let footerIdentifier = "launcher.footer"
    static let iconIdentifier = "launcher.icon"
    static let searchingIdentifier = "launcher.searching"
    static let size = NSSize(width: 480, height: 580)
    static let minimumSize = NSSize(width: 400, height: 380)

    let listController: AppListViewController

    init(
        store: AppListStore, discoversDevices: Bool, onChoose: @escaping (AppLocation) -> Void,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        listController = AppListViewController(store: store, onChoose: onChoose, openURL: openURL)
        let content = LauncherViewController(
            list: listController, discoversDevices: discoversDevices)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        // Named for the Window menu; the header shows the name instead of the title bar.
        window.title = "Cutaway"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // Too little in it for full screen; and shown after a full-screen inspector closes, a
        // window that may go full screen takes the inspector's place there.
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentViewController = content
        // The arrow keys and Return go to the list (C-LIST-04).
        window.initialFirstResponder = listController.tableView
        window.setContentSize(Self.size)
        window.contentMinSize = Self.minimumSize
        window.center()
        super.init(window: window)
        window.layoutIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// The launcher's content: a header, the list, and a footer.
final class LauncherViewController: NSViewController {
    private let list: AppListViewController
    private let discoversDevices: Bool

    init(list: AppListViewController, discoversDevices: Bool) {
        self.list = list
        self.discoversDevices = discoversDevices
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The app's icon from its own asset catalog. The system's copy comes from Launch Services,
    /// which on the first launch of a fresh build may not know the icon yet and hands out the
    /// blank template.
    static func appIcon() -> NSImage? {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    static func footerText(discoversDevices: Bool) -> String {
        discoversDevices
            ? localized("launcher.searching.all") : localized("launcher.searching.simulators")
    }

    override func loadView() {
        addChild(list)
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .followsWindowActiveState
        root.addVStack(alignment: .fill, spacing: 0, safeArea: .top) {
            HStack(alignment: .center, spacing: 14) {
                NSImageView()
                    .image(Self.appIcon())
                    .imageScaling(.scaleProportionallyUpOrDown)
                    .frame(width: 60, height: 60)
                    .accessibilityIdentifier(LauncherWindowController.iconIdentifier)
                VStack(alignment: .leading, spacing: 2) {
                    NSTextField(labelWithString: "Cutaway")
                        .font(.systemFont(ofSize: 20, weight: .semibold))
                    NSTextField(labelWithString: localized("launcher.prompt"))
                        .textColor(.secondaryLabelColor)
                }
                Spacer()
            }
            .padding(top: 6, leading: 22, bottom: 14, trailing: 22)

            list.view

            NSBox().configure { $0.boxType = .separator }
            HStack(alignment: .center, spacing: Theme.Spacing.small) {
                PulseDotView()
                    .accessibilityIdentifier(LauncherWindowController.searchingIdentifier)
                NSTextField(labelWithString: Self.footerText(discoversDevices: discoversDevices))
                    .font(Theme.Font.caption)
                    .textColor(.secondaryLabelColor)
                    .accessibilityIdentifier(LauncherWindowController.footerIdentifier)
                Spacer()
            }
            .padding(horizontal: Theme.Spacing.large, vertical: 7)
        }
        view = root
    }
}
