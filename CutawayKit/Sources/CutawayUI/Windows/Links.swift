import AppKit

/// The pages on the web the app links to, in one place (C-MENU-04): the app's public repository
/// and CutawayServer's.
public enum Links {
    /// The source code (C-MENU-03).
    public static let repository = url("https://github.com/nothingsh/Cutaway")
    /// Help › Cutaway Help: the repository's README.
    public static let help = url("https://github.com/nothingsh/Cutaway#readme")
    /// Help › Integrating CutawayServer: the server's README.
    public static let integrationGuide = url("https://github.com/nothingsh/CutawayServer#readme")
    /// Cutaway › Check for Updates… (C-DIST-02): the repository's releases through GitHub's API,
    /// drafts and prereleases included, newest first.
    public static let releasesAPI = url(
        "https://api.github.com/repos" + repository.path + "/releases?per_page=30")

    private static func url(_ string: String) -> URL {
        // Only ever given the literals above, each a valid URL; the tests read every one.
        // swiftlint:disable:next force_unwrapping
        URL(string: string)!
    }
}

extension WindowCoordinator {
    /// Help › Cutaway Help (C-MENU-04).
    @objc func openHelp(_ sender: Any?) {
        openURL(Links.help)
    }

    /// Help › Integrating CutawayServer (C-MENU-04).
    @objc func openIntegrationGuide(_ sender: Any?) {
        openURL(Links.integrationGuide)
    }
}
