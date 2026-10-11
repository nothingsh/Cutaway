import AppKit
import Combine
import DeclarativeAppKit
import DeclarativeCombine

/// A view that shows one line of text. Nothing in the app uses it; the toolchain probe for the
/// declarative libraries does, and stays so that an update of Xcode or of the libraries that
/// breaks them shows up at once.
final class PlaceholderViewController: NSViewController {
    /// The accessibility identifier of the message label.
    static let messageIdentifier = "placeholder.message"

    private let message: AnyPublisher<String, Never>

    init(message: AnyPublisher<String, Never>) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        root.addVStack(alignment: .center) {
            // The spacers take whatever height the view is given. Without them the view is
            // as tall as its label and no taller, and so is whatever sits beside it.
            Spacer()
            NSTextField(labelWithString: "")
                .font(.preferredFont(forTextStyle: .title2))
                .textColor(.secondaryLabelColor)
                .accessibilityIdentifier(Self.messageIdentifier)
                .bind(\.stringValue, to: message)
            Spacer()
        }
        view = root
    }
}
