import XCTest

@testable import CutawayUI

/// The search field's text on its way to the store (C-HIER-04): typing waits for a pause,
/// clearing and Return go at once, and what waits is sent or dropped when asked.
@MainActor
final class DebouncedSearchInputTests: XCTestCase {
    private var sent: [String] = []

    private func input() -> DebouncedSearchInput {
        DebouncedSearchInput { [weak self] in self?.sent.append($0) }
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    func test_C_HIER_04_typingIsSentOnceItPauses() {
        let input = input()
        input.edit("L", returned: false)
        input.edit("La", returned: false)
        input.edit("Lab", returned: false)
        XCTAssertEqual(sent, [], "typing waits")
        wait(DebouncedSearchInput.delay + 0.2)
        XCTAssertEqual(sent, ["Lab"], "the last text, once")
    }

    func test_C_HIER_04_clearingAndReturnGoAtOnce() {
        let input = input()
        input.edit("Lab", returned: false)
        input.edit("", returned: false)
        XCTAssertEqual(sent, [""])
        input.edit("Label", returned: true)
        XCTAssertEqual(sent, ["", "Label"])
        wait(DebouncedSearchInput.delay + 0.2)
        XCTAssertEqual(sent, ["", "Label"], "nothing waited")
    }

    func test_C_HIER_04_whatWaitsIsSentOnFlushAndNotOnDrop() {
        let input = input()
        input.edit("Lab", returned: false)
        input.flush()
        XCTAssertEqual(sent, ["Lab"])
        input.edit("Sep", returned: false)
        input.drop()
        input.flush()
        wait(DebouncedSearchInput.delay + 0.2)
        XCTAssertEqual(sent, ["Lab"], "the store's own text won")
    }
}
