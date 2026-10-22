import Combine
import Foundation

/// The search field's text on its way to the store (C-HIER-04): typing waits for a pause, so
/// that a word typed quickly filters the whole tree once, not once a letter. Clearing the
/// field and pressing Return do not wait. A newer edit replaces one still waiting.
@MainActor
final class DebouncedSearchInput {
    /// How long, in seconds, typing must pause before its text is sent.
    nonisolated static let delay: TimeInterval = 0.15

    /// A text on its way, and whether it goes at once. No text drops the one still waiting
    /// and sends nothing.
    private struct Edit {
        let text: String?
        let isImmediate: Bool
    }

    private let edits = PassthroughSubject<Edit, Never>()
    /// The typed text still waiting for its pause, if any.
    private var waitingText: String?
    private let send: @MainActor (String) -> Void
    private var cancellable: AnyCancellable?

    /// `send` is called with each text that is to reach the store, on the main thread.
    init(send: @escaping @MainActor (String) -> Void) {
        self.send = send
        cancellable = Self.delayed(edits).sink { [weak self] text in
            MainActor.assumeIsolated {
                self?.waitingText = nil
                self?.send(text)
            }
        }
    }

    /// The field's text was edited: typing waits; an empty text and Return go at once.
    func edit(_ text: String, returned: Bool) {
        let isImmediate = returned || text.isEmpty
        waitingText = isImmediate ? nil : text
        edits.send(Edit(text: text, isImmediate: isImmediate))
    }

    /// The store's text, set elsewhere, wins over typing still waiting; it is the store's
    /// already, so nothing is sent.
    func drop() {
        waitingText = nil
        edits.send(Edit(text: nil, isImmediate: true))
    }

    /// Typing still waiting is sent now, as when the list goes away: the inspection's
    /// settings carry it over (C-WIN-04).
    func flush() {
        guard let text = waitingText else { return }
        drop()
        send(text)
    }

    /// The texts of the edits, each as soon as no newer edit replaced it: typed ones after
    /// `delay`, the others at once. Delivered on the main queue, as the field's are.
    private static func delayed(_ edits: some Publisher<Edit, Never>) -> AnyPublisher<String, Never> {
        edits
            .map { edit -> AnyPublisher<String, Never> in
                guard let text = edit.text.map(Just.init) else {
                    return Empty().eraseToAnyPublisher()
                }
                if edit.isImmediate { return text.eraseToAnyPublisher() }
                return text.delay(for: .seconds(delay), scheduler: DispatchQueue.main)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }
}
