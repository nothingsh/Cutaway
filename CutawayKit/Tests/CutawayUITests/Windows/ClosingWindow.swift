import AppKit

/// Tests that a closed window lets go of what it showed.
///
/// AppKit keeps a window, and with it its content view controller and everything that holds,
/// until the window's opening or closing animation is over: about 0.3 seconds, but in two
/// full test runs on 2026-10-10 none of the closing animations ended for minutes, and every
/// closed window seemed to leak; on 2026-10-21 an opening animation that never ended held a
/// window the soak had closed. What these tests check is Cutaway's own references, so their
/// windows open and close without the animation: `WindowCoordinator.animatesWindows` is off
/// before any window opens. Turned off once the window is shown, it would leave the opening
/// animation under way.
enum ClosingWindow {
    /// For a failure message: whether the closed `window` itself is still alive, which puts
    /// what outlived it on AppKit rather than on Cutaway.
    @MainActor
    static func lingeringNote(_ window: NSWindow?) -> String {
        guard let window else { return " (the window itself is gone)" }
        return " (the window itself is still alive, visible: \(window.isVisible))"
    }
}
