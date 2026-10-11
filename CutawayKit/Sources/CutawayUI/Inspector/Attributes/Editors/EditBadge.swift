import AppKit
import DeclarativeAppKit

/// The spinner or the warning sign at the end of a field (C-ATTR-06). It floats over the
/// field and is small, so showing it changes no size; the warning's reason is its tooltip.
final class EditBadge: NSView {
    private let spinner = NSProgressIndicator()
        .accessibilityIdentifier(AttributeEditorView.spinnerIdentifier)
        .configure {
            $0.style = .spinning
            $0.controlSize = .mini
            $0.isIndeterminate = true
            $0.isDisplayedWhenStopped = false
        }

    private let warning = NSImageView()
        .image(Theme.symbol(Theme.Symbol.editFailed, size: 11))
        .contentTintColor(.systemOrange)
        .accessibilityIdentifier(AttributeEditorView.failureIdentifier)

    init() {
        super.init(frame: .zero)
        addHStack(alignment: .center, spacing: 0) {
            spinner.frame(width: 12, height: 12)
            warning.frame(width: 14, height: 14)
        }
        show(sending: false, failure: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(sending: Bool, failure: String?) {
        spinner.isHidden = !sending
        if sending {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        warning.isHidden = failure == nil
        warning.toolTip = failure
        warning.setAccessibilityLabel(failure)
        isHidden = !sending && failure == nil
    }

    var isShowingSpinner: Bool { !isHidden && !spinner.isHidden }
    var failureText: String? { isHidden || warning.isHidden ? nil : warning.toolTip }

    /// Only the warning sign takes the mouse, for its tooltip; clicks elsewhere reach the field.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !warning.isHidden else { return nil }
        return super.hitTest(point)
    }
}
