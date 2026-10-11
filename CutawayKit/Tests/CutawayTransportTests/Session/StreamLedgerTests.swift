import XCTest
@testable import CutawayTransport

/// C-CONN-12: what decides that a session stops reading, apart from the session.
final class StreamLedgerTests: XCTestCase {
    private func ledger(chunks: Int = 2, bytes: Int = 100) -> StreamLedger {
        StreamLedger(limit: ReadLimit(chunks: chunks, bytes: bytes))
    }

    func test_C_CONN_12_pausesAtTheChunkLimitOfOneStream() {
        var ledger = ledger()
        ledger.add(chunkOf: 1, to: 1)
        ledger.add(chunkOf: 1, to: 2)
        // One chunk in each of two streams: neither is at its limit.
        XCTAssertFalse(ledger.isPaused)

        ledger.add(chunkOf: 1, to: 1)
        XCTAssertTrue(ledger.isPaused)
        XCTAssertEqual(ledger.untakenChunkCount, 3)
    }

    func test_C_CONN_12_pausesAtTheByteLimitWhicheverComesFirst() {
        var ledger = ledger()
        ledger.add(chunkOf: 99, to: 1)
        XCTAssertFalse(ledger.isPaused)

        var full = self.ledger()
        full.add(chunkOf: 100, to: 1)
        XCTAssertTrue(full.isPaused)
    }

    func test_C_CONN_12_takingTheOldestChunkResumes() {
        var ledger = ledger(chunks: 3)
        ledger.add(chunkOf: 60, to: 1)
        ledger.add(chunkOf: 50, to: 1)
        XCTAssertTrue(ledger.isPaused)

        XCTAssertTrue(ledger.take(from: 1))
        // The 60 bytes went, not the 50: chunks are taken in order.
        XCTAssertFalse(ledger.isPaused)
        ledger.add(chunkOf: 49, to: 1)
        XCTAssertFalse(ledger.isPaused, "50 + 49 bytes is under the limit")
        ledger.add(chunkOf: 1, to: 3)
        XCTAssertEqual(ledger.untakenChunkCount, 3)
    }

    func test_C_CONN_12_takingFromAStreamWithNothingUntakenChangesNothing() {
        var ledger = ledger()
        XCTAssertFalse(ledger.take(from: 1))

        ledger.add(chunkOf: 1, to: 1)
        XCTAssertTrue(ledger.take(from: 1))
        XCTAssertFalse(ledger.take(from: 1))
        XCTAssertEqual(ledger.untakenChunkCount, 0)
    }

    func test_C_CONN_12_aForgottenStreamHoldsNothingUp() {
        var ledger = ledger()
        ledger.add(chunkOf: 1, to: 1)
        ledger.add(chunkOf: 1, to: 1)
        ledger.add(chunkOf: 1, to: 2)
        XCTAssertTrue(ledger.isPaused)

        ledger.forget(1)
        XCTAssertFalse(ledger.isPaused)
        // A chunk its reader still takes counts against nothing.
        XCTAssertFalse(ledger.take(from: 1))
        XCTAssertEqual(ledger.untakenChunkCount, 1)

        ledger.forgetAll()
        XCTAssertEqual(ledger.untakenChunkCount, 0)
    }
}
