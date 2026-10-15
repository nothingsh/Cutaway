import AppKit
import Combine

/// The mark that the search goes on (C-LIST-04): a small dot in the accent colour that slowly
/// brightens and dims, and stays still when the system asks for reduced motion.
final class PulseDotView: NSView {
    static let side: CGFloat = 13
    static let dot: CGFloat = 7
    /// The key of the layer's animation.
    static let animationKey = "pulse"

    /// The dot; the view's own layer is the halo around it.
    private let dotLayer = CALayer()

    /// Whether motion should be left out. The system's setting by default.
    private let reducesMotion: @MainActor () -> Bool
    private var settingChanges: AnyCancellable?

    init(reducesMotion: @escaping @MainActor () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }) {
        self.reducesMotion = reducesMotion
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        layer?.addSublayer(dotLayer)
        setAccessibilityElement(false)
        settingChanges = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateMotion() } }
        updateMotion()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.side) }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // The dot with a 3-point halo of the accent colour.
        let accent = NSColor.controlAccentColor
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = accent.withAlphaComponent(dark ? 0.28 : 0.16).cgColor
            dotLayer.backgroundColor = accent.cgColor
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        dotLayer.frame = NSRect(
            x: (bounds.width - Self.dot) / 2, y: (bounds.height - Self.dot) / 2, width: Self.dot,
            height: Self.dot)
        dotLayer.cornerRadius = Self.dot / 2
    }

    /// Starts or stops the pulse as the system's setting says.
    func updateMotion() {
        guard let layer else { return }
        if reducesMotion() {
            layer.removeAnimation(forKey: Self.animationKey)
            layer.opacity = 1
        } else if layer.animation(forKey: Self.animationKey) == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.35
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: Self.animationKey)
        }
    }
}
