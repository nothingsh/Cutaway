import AppKit
import DeclarativeAppKit

/// A small panel that floats over the preview, on glass that follows the window's appearance:
/// Liquid Glass on macOS 26, a material on earlier systems. Its corners are rounded to half its
/// height, at most `maximumRadius`, so a one-line panel is a capsule. By default the pointer
/// goes through it to the preview below, so it never stands in the way of a click or a hover.
final class HUDView: NSView {
    /// The corner radius of a panel taller than a capsule, such as a notice that wraps.
    static let maximumRadius: CGFloat = 16

    /// Whether the panel takes the pointer itself, as one with a button must.
    var takesPointer = false

    private let background: NSView

    init(content: NSView) {
        // The glass is behind the content and out of Auto Layout: as the content's container,
        // or pinned by constraints, it narrowed a wrapping notice to a few points.
        if #available(macOS 26.0, *) {
            background = NSGlassEffectView()
        } else {
            background = NSVisualEffectView().configure {
                $0.material = .popover
                $0.blendingMode = .withinWindow
                $0.state = .active
                $0.wantsLayer = true
                $0.layer?.cornerCurve = .continuous
                $0.layer?.masksToBounds = true
            }
        }
        super.init(frame: .zero)
        background.autoresizingMask = [.width, .height]
        addSubview(background)
        addContent(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        background.frame = bounds
        let radius = min(bounds.height / 2, Self.maximumRadius)
        if #available(macOS 26.0, *), let glass = background as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            background.layer?.cornerRadius = radius
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        takesPointer ? super.hitTest(point) : nil
    }
}

/// A view that takes every click inside it and does nothing with it.
final class ClickShieldView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Hidden, it must not take anything: AppKit's own check is in the method overridden.
        !isHidden && frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
