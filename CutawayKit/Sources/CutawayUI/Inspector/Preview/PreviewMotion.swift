import AppKit
import QuartzCore

/// Where the preview's transitions take the time from, and when they draw.
@MainActor
protocol PreviewClock: AnyObject {
    /// Seconds, from any origin.
    var now: Double { get }
    /// Calls `tick` once a frame until `stop()`.
    func start(_ tick: @escaping @MainActor () -> Void)
    func stop()
}

/// How the preview goes from one picture to the next (C-PREV-11, C-PREV-12).
@MainActor
struct PreviewMotion {
    /// How long a transition takes, in seconds.
    nonisolated static let duration = 0.3

    /// The clock for a preview view; nil for no transitions.
    let makeClock: (@MainActor (NSView) -> any PreviewClock)?
    /// Asked as each transition would start: true leaves it out.
    let reducesMotion: @MainActor (NSView) -> Bool

    /// Paced by the display. Leaves transitions out when the system asks for reduced motion,
    /// and when the window is not on screen, where nobody would see them and the display does
    /// not pace them.
    static let system = Self(
        makeClock: { DisplayClock(view: $0) },
        reducesMotion: { view in
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                || view.window?.isVisible != true
        })

    /// No transitions: every change shows at once.
    static let instant = Self(makeClock: nil, reducesMotion: { _ in true })

    /// Paced by a clock the caller drives. For tests.
    static func paced(
        by clock: any PreviewClock, reducesMotion: @escaping @MainActor () -> Bool = { false }
    ) -> Self {
        Self(makeClock: { _ in clock }, reducesMotion: { _ in reducesMotion() })
    }

    /// Slow at both ends: cubic ease in and out, from 0 to 1 as `t` goes from 0 to 1.
    nonisolated static func eased(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        if t < 0.5 { return 4 * t * t * t }
        let u = 2 - 2 * t
        return 1 - u * u * u / 2
    }
}

/// Ticks with the display the view is on (`NSView.displayLink`, macOS 14).
@MainActor
final class DisplayClock: PreviewClock {
    private weak var view: NSView?
    private var link: CADisplayLink?
    private var tick: (@MainActor () -> Void)?

    init(view: NSView) {
        self.view = view
    }

    var now: Double { CACurrentMediaTime() }

    func start(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
        guard link == nil, let view else { return }
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        tick = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        tick?()
    }
}
