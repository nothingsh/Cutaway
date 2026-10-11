import Combine
import Foundation

/// The language chosen for Cutaway in its settings (C-LOC-01): the system's, or one of the
/// languages the interface is written in.
///
/// It is kept as macOS keeps the language picked for an app in System Settings: `AppleLanguages`
/// in the app's own domain, so that either place shows what the other set. It takes effect
/// when the app next starts.
@MainActor
public final class LanguageSetting: ObservableObject {
    /// The user defaults key macOS reads the app's languages from.
    public static let key = "AppleLanguages"

    /// The languages that can be chosen, the first being the one to fall back to.
    public let languages: [String]
    /// The chosen language, one of `languages`; nil for the system's.
    @Published public private(set) var choice: String?

    private let defaults: UserDefaults
    private let domain: String

    /// `domain` is the name of the persistent domain `defaults` writes to: the app's bundle
    /// identifier for `.standard`, or a suite's name. Only that domain is read, not the
    /// system-wide languages.
    public init(defaults: UserDefaults, domain: String, languages: [String]) {
        self.defaults = defaults
        self.domain = domain
        self.languages = languages
        let kept = defaults.persistentDomain(forName: domain)?[Self.key]
        choice = (kept as? [String])?.first.map { Self.match($0, in: languages) }
    }

    /// Chooses a language, or the system's with nil, and keeps the choice.
    public func choose(_ language: String?) {
        guard language.map(languages.contains) ?? true else { return }
        choice = language
        if let language {
            defaults.set([language], forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    /// The language the interface will be in when the app next starts: the choice, or the
    /// first of the system's `preferences` the interface is written in.
    public func resolved(systemPreferences preferences: [String]) -> String {
        if let choice { return choice }
        return Bundle.preferredLocalizations(from: languages, forPreferences: preferences).first
            ?? languages.first ?? ""
    }

    /// The languages macOS prefers for every app, from System Settings.
    public static var systemPreferences: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key]
            as? [String] ?? []
    }

    /// The one of `languages` a kept language stands for: "zh-Hant-TW" is "zh-Hant"; one
    /// that is none of them falls back to the first.
    private static func match(_ language: String, in languages: [String]) -> String {
        Bundle.preferredLocalizations(from: languages, forPreferences: [language]).first
            ?? languages.first ?? language
    }
}
