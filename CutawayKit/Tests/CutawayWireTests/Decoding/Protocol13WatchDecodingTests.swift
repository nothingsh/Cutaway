import CutawayTestSupport
import XCTest

@testable import CutawayWire

/// C-WIRE-13, what protocol 1.3's `dev.2` (`v1.3.0-dev.2`) appended: turning hierarchy change
/// notifications on and off, and the event. The expected values come from
/// Protocol/fixtures/README.md and Protocol/fixtures/src/watch-hierarchy.
final class Protocol13WatchDecodingTests: XCTestCase {
    private func decode(_ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: "watch-hierarchy", file: file))
    }

    func test_C_WIRE_13_theWatchScenarioDecodesAsTheFixturesSay() throws {
        XCTAssertEqual(try decode("01-c2s-get-hierarchy.bin"), Frame(requestID: 1, body: .getHierarchy))
        XCTAssertEqual(
            try decode("03-c2s-watch-hierarchy.bin"),
            Frame(requestID: 2, body: .watchHierarchy(WatchHierarchy(enabled: true))))
        XCTAssertEqual(
            try decode("04-s2c-watch-hierarchy-result.bin"),
            Frame(requestID: 2, body: .watchHierarchyResult(WatchHierarchyResult(enabled: true))))
        XCTAssertEqual(
            try decode("05-s2c-hierarchy-changed.bin"),
            Frame(requestID: 0, body: .hierarchyChanged(HierarchyChanged(roots: [3, 4], whole: false))))
        XCTAssertEqual(
            try decode("06-c2s-get-subtree.bin"),
            Frame(requestID: 3, body: .getSubtree(GetSubtree(rootID: 3))))
        XCTAssertEqual(
            try decode("07-c2s-get-subtree.bin"),
            Frame(requestID: 4, body: .getSubtree(GetSubtree(rootID: 4))))
        // Between the two chunks of the details stream (P-WATCH-04).
        XCTAssertEqual(
            try decode("12-s2c-hierarchy-changed.bin"),
            Frame(requestID: 0, body: .hierarchyChanged(HierarchyChanged(roots: [], whole: true))))
        XCTAssertEqual(
            try decode("15-c2s-watch-hierarchy.bin"),
            Frame(requestID: 6, body: .watchHierarchy(WatchHierarchy(enabled: false))))
        XCTAssertEqual(
            try decode("16-s2c-watch-hierarchy-result.bin"),
            Frame(requestID: 6, body: .watchHierarchyResult(WatchHierarchyResult(enabled: false))))
    }

    func test_C_WIRE_13_theImagesOfTheRootsAreAskedForWithTheirDigests() throws {
        guard case .getLayerDetails(let request) = try decode("08-c2s-get-layer-details.bin").body
        else {
            XCTFail("not GetLayerDetails")
            return
        }
        XCTAssertEqual(request.requests.map(\.layerID), [3, 4])
        XCTAssertTrue(request.requests.allSatisfy { $0.wantGroup && $0.knownGroupDigest?.count == 16 })
        for file in ["11-s2c-chunk-0.bin", "13-s2c-chunk-1.bin"] {
            guard case .layerDetailsChunk(let chunk) = try decode(file).body
            else {
                XCTFail("not a chunk")
                return
            }
            XCTAssertTrue(chunk.details.allSatisfy {
                if case .unchanged = $0.group { return true }
                return false
            }, file)
        }
    }

    func test_C_WIRE_13_theWatchMessagesSurviveARoundTrip() throws {
        for body: Body in [
            .watchHierarchy(WatchHierarchy(enabled: true)),
            .watchHierarchy(WatchHierarchy(enabled: false)),
            .watchHierarchyResult(WatchHierarchyResult(enabled: true)),
            .watchHierarchyResult(WatchHierarchyResult(enabled: false)),
            .hierarchyChanged(HierarchyChanged(roots: [1, 2, 3], whole: false)),
            .hierarchyChanged(HierarchyChanged(roots: [], whole: true)),
        ] {
            let frame = Frame(requestID: 9, body: body)
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
    }
}
