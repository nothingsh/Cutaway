import AppKit

/// The pages on the web the app links to, in one place (C-MENU-04): the app's public repository
/// and the project's website, published from `site/`.
public enum Links {
    /// The source code (C-MENU-03).
    public static let repository = url("https://github.com/nothingsh/Cutaway")
    /// Help › Cutaway Help: the website's guide.
    public static let help = url(website + "guide/getting-started")
    /// Help › Integrating CutawayServer: the website's pages on integrating the server.
    public static let integrationGuide = url(website + "integrate/")
    /// Cutaway › Check for Updates… (C-DIST-02): the repository's releases through GitHub's API,
    /// drafts and prereleases included, newest first.
    public static let releasesAPI = url(
        "https://api.github.com/repos" + repository.path + "/releases?per_page=30")

    private static let website = "https://nothingsh.github.io/Cutaway/"

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
