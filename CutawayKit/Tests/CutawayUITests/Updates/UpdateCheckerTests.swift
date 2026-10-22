import Foundation
import XCTest

@testable import CutawayUI

/// Check for Updates… asks GitHub for the repository's releases and compares them with the
/// running version (C-DIST-02). No test reaches the network: the requests go to a fake.
@MainActor
final class UpdateCheckerTests: XCTestCase {
    /// Records the requests and answers each with the given response.
    private final class FakeNetwork: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private let answer: @Sendable (URLRequest) async throws -> (Data, URLResponse)

        init(answer: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
            self.answer = answer
        }

        var requests: [URLRequest] {
            lock.withLock { recorded }
        }

        func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
            lock.withLock { recorded.append(request) }
            return try await answer(request)
        }
    }

    private nonisolated static func response(_ status: Int, _ body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: Links.releasesAPI, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }

    private nonisolated static let releases = """
    [
      {"tag_name": "v1.1.0", "html_url": "https://github.com/nothingsh/Cutaway/releases/tag/v1.1.0",
       "draft": false, "prerelease": false, "name": "Cutaway 1.1.0"},
      {"tag_name": "v1.0.0", "html_url": "https://github.com/nothingsh/Cutaway/releases/tag/v1.0.0",
       "draft": false, "prerelease": false}
    ]
    """

    private func checker(
        _ version: String, answering answer: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) -> (UpdateChecker, FakeNetwork) {
        let network = FakeNetwork(answer: answer)
        return (UpdateChecker(currentVersion: version, fetch: network.fetch), network)
    }

    func test_C_DIST_02_theRequestAsksGitHubForTheReleasesAndSaysNothingElse() async throws {
        let (checker, network) = checker("1.0.0") { _ in Self.response(200, "[]") }
        _ = await checker.check()
        let request = try XCTUnwrap(network.requests.first)
        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(request.url, Links.releasesAPI)
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.github.com")
        XCTAssertEqual(request.url?.path, "/repos/nothingsh/Cutaway/releases")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(
            request.allHTTPHeaderFields,
            ["Accept": "application/vnd.github+json", "User-Agent": "Cutaway/1.0.0"])
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func test_C_DIST_02_aNewerReleaseIsAnUpdate() async {
        let (checker, _) = checker("1.0.0") { _ in Self.response(200, Self.releases) }
        let result = await checker.check()
        XCTAssertEqual(
            result,
            .available(
                version: "1.1.0", page: URL(string: "https://github.com/nothingsh/Cutaway/releases/tag/v1.1.0")!))
    }

    func test_C_DIST_02_theNewestReleaseIsNoUpdate() async {
        let (checker, _) = checker("1.1.0") { _ in Self.response(200, Self.releases) }
        let result = await checker.check()
        XCTAssertEqual(result, .upToDate(version: "1.1.0"))
    }

    func test_C_DIST_02_anAnswerThatIsNotTheListOrNoAnswerFails() async {
        let cases: [(String, Int, String, UpdateCheckFailure)] = [
            ("not found", 404, #"{"message": "Not Found"}"#, .status(404)),
            ("server error", 500, "", .status(500)),
            ("not JSON", 200, "<html></html>", .unreadable),
            ("not a list", 200, #"{"tag_name": "v9.0.0"}"#, .unreadable),
        ]
        for (name, status, body, failure) in cases {
            let (checker, _) = checker("1.0.0") { _ in Self.response(status, body) }
            let result = await checker.check()
            XCTAssertEqual(result, .failed(failure), name)
        }
        let (offline, _) = checker("1.0.0") { _ in throw URLError(.notConnectedToInternet) }
        let result = await offline.check()
        XCTAssertEqual(
            result, .failed(.network(URLError(.notConnectedToInternet).localizedDescription)), "network")
    }

    func test_C_DIST_02_anUnknownRunningVersionFailsWithoutAsking() async {
        let (checker, network) = checker("") { _ in Self.response(200, Self.releases) }
        let result = await checker.check()
        XCTAssertEqual(result, .failed(.unknownVersion))
        XCTAssertTrue(network.requests.isEmpty)
    }

    func test_C_DIST_02_aSecondCheckWhileOneIsUnderWayAsksNothing() async {
        let gate = AsyncStream<Void>.makeStream()
        let (checker, network) = checker("1.0.0") { _ in
            for await _ in gate.stream { break }
            return Self.response(200, Self.releases)
        }
        let first = Task { await checker.check() }
        while network.requests.isEmpty {
            await Task.yield()
        }
        XCTAssertTrue(checker.isChecking)
        let second = await checker.check()
        XCTAssertNil(second, "no result: the first check gives the one answer")
        gate.continuation.yield()
        let firstResult = await first.value
        XCTAssertNotNil(firstResult)
        XCTAssertEqual(network.requests.count, 1)
        XCTAssertFalse(checker.isChecking)
    }
}
