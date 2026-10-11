import AppKit

/// Tests that a closed window lets go of what it showed.
///
/// AppKit keeps a closing window, and with it its content view controller and everything
/// that holds, until the window's closing animation is over: about 0.3 seconds, but in two
/// full test runs on 2026-10-10 none of the animations ended for minutes, and every
/// closed window seemed to leak. What these tests check is Cutaway's own references, so they
/// close windows without the animation.
enum ClosingWindow {
    /// Makes `window` close without its closing animation.
    @MainActor
    static func closeAtOnce(_ window: NSWindow?) {
        window?.animationBehavior = .none
    }

    /// For a failure message: whether the closed `window` itself is still alive, which puts
    /// what outlived it on AppKit rather than on Cutaway.
    @MainActor
    static func lingeringNote(_ window: NSWindow?) -> String {
        guard let window else { return " (the window itself is gone)" }
        return " (the window itself is still alive, visible: \(window.isVisible))"
    }
}
