import CutawayTestSupport
import Foundation
import XCTest

/// `scripts/replay.sh`: serves the archive named in `CUTAWAY_REPLAY_ARCHIVE` on the first free
/// port of the protocol's simulator ports, where a running Cutaway finds it as an app in a
/// simulator, until the process is stopped (C-MOCK-04). Skipped without the variable; a
/// skipped test covers no requirement.
final class ArchiveReplayServiceTests: XCTestCase {
    func test_C_MOCK_04_serveTheArchiveNamedInTheEnvironment() async throws {
        guard let path = ProcessInfo.processInfo.environment["CUTAWAY_REPLAY_ARCHIVE"] else {
            throw XCTSkip("set CUTAWAY_REPLAY_ARCHIVE, or run scripts/replay.sh")
        }
        let script = try MockScript.replaying(
            archive: try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped))
        var server: MockServer?
        for port in UInt16(48160)...48167 where server == nil {
            server = try? await MockServer.start(port: port, script: script, records: false)
        }
        guard let server else {
            XCTFail("ports 48160 to 48167 are all taken")
            return
        }
        // On standard error: `swift test` holds back what a test prints until it ends.
        FileHandle.standardError.write(
            Data("Replaying \(path) on port \(server.port). Stop with Ctrl-C.\n".utf8))
        while true {
            try await Task.sleep(for: .seconds(60))
            FileHandle.standardError.write(
                Data("\(await server.connectionCount) connection(s) so far\n".utf8))
        }
    }
}
