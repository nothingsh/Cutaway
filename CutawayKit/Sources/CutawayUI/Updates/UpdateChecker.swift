import Foundation

/// A release as GitHub's API lists it: the fields Check for Updates… reads (C-DIST-02).
public struct PublishedRelease: Decodable, Equatable, Sendable {
    public let tag: String
    /// The release's page, where the user downloads it.
    public let page: URL
    public let isDraft: Bool

    public init(tag: String, page: URL, isDraft: Bool) {
        self.tag = tag
        self.page = page
        self.isDraft = isDraft
    }

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case page = "html_url"
        case isDraft = "draft"
    }
}

/// Which release, if any, is an update (C-DIST-02).
enum UpdateChoice {
    /// The newest release above `current`. A release sees releases only; a beta sees betas and
    /// releases. GitHub's own prerelease mark is not read: the version says it. Drafts and tags
    /// that are not a version are skipped.
    static func newest(
        in releases: [PublishedRelease], over current: SemanticVersion
    ) -> (version: SemanticVersion, release: PublishedRelease)? {
        releases
            .filter { !$0.isDraft }
            .compactMap { release in SemanticVersion(tag: release.tag).map { (version: $0, release: release) } }
            .filter { current.isPrerelease || !$0.version.isPrerelease }
            .filter { $0.version > current }
            .max { $0.version < $1.version }
    }
}

/// Why a check found nothing out.
public enum UpdateCheckFailure: Equatable, Sendable {
    /// The request did not get an answer; the system's description of why.
    case network(String)
    /// An answer other than 200: 404 while the repository is private.
    case status(Int)
    /// An answer that is not a list of releases.
    case unreadable
    /// The running app's version is not one of C-DIST-01, so nothing compares with it.
    case unknownVersion
}

/// What Check for Updates… found.
public enum UpdateCheckResult: Equatable, Sendable {
    case available(version: String, page: URL)
    case upToDate(version: String)
    case failed(UpdateCheckFailure)
}

/// Asks GitHub for the repository's releases, once each time the user chooses Check for
/// Updates… (C-DIST-02): the app's only request beyond this Mac. It sends no information about
/// the Mac; the user agent names the app and its version, as GitHub asks.
@MainActor
public final class UpdateChecker {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// The real network.
    public nonisolated static let network: Fetch = { request in
        try await URLSession.shared.data(for: request)
    }

    public let currentVersion: String
    private let fetch: Fetch
    /// Whether a check is under way.
    public private(set) var isChecking = false

    public init(currentVersion: String = AppVersion.current.version, fetch: @escaping Fetch = UpdateChecker.network) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    /// The request for the list of releases.
    var request: URLRequest {
        var request = URLRequest(url: Links.releasesAPI, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cutaway/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Checks once. Nil while another check is under way: that one gives the answer.
    public func check() async -> UpdateCheckResult? {
        guard !isChecking else { return nil }
        guard let current = SemanticVersion(currentVersion) else { return .failed(.unknownVersion) }
        isChecking = true
        defer { isChecking = false }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            return .failed(.network(error.localizedDescription))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return .failed(.status(status)) }
        guard let releases = try? JSONDecoder().decode([PublishedRelease].self, from: data) else {
            return .failed(.unreadable)
        }
        guard let newest = UpdateChoice.newest(in: releases, over: current) else {
            return .upToDate(version: currentVersion)
        }
        return .available(version: newest.version.description, page: newest.release.page)
    }
}
