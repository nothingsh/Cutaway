import AppKit
import DeclarativeAppKit

/// A small coloured capsule with a symbol and a word: the state of an app in the list.
final class StatusCapsule: NSView {
    typealias Kind = AppEntryPresentation.Badge

    private(set) var kind: Kind?
    private let symbolView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    /// What the capsule says; empty when it is hidden.
    var text: String { label.stringValue }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        addHStack(alignment: .center, spacing: 3) {
            symbolView
            label.font(.systemFont(ofSize: 11, weight: .medium))
        }
        .padding(horizontal: 6, vertical: 1)
        setAccessibilityIdentifier(AppRowView.Identifier.badge)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ kind: Kind?) {
        self.kind = kind
        isHidden = kind == nil
        label.stringValue = kind?.text ?? ""
        symbolView.image = kind.flatMap { Theme.symbol($0.symbol, size: 9, weight: .semibold) }
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        guard let kind else { return }
        label.textColor = kind.color
        symbolView.contentTintColor = kind.color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = kind.color.withAlphaComponent(0.15).cgColor
        }
    }
}

extension AppEntryPresentation.Badge {
    var color: NSColor {
        switch self {
        case .inactive: return .systemOrange
        case .background: return .systemIndigo
        case .incompatible: return .systemRed
        }
    }
}
