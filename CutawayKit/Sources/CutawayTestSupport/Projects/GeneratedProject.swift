import Dispatch
import Foundation

/// The project C-SRC-02 times: 5,000 Swift files in 50 folders, 200 color sets and two String
/// Catalogs of 500 keys in five languages.
public enum GeneratedProject {
    public static let swiftFileCount = 5000
    public static let colorSetCount = 200
    public static let catalogCount = 2
    public static let keysPerCatalog = 500
    public static let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]

    /// The name of the class the file numbered `number` declares.
    public static func className(_ number: Int) -> String {
        "GeneratedView\(number)"
    }

    /// The path of the Swift file numbered `number`.
    public static func swiftFile(_ number: Int) -> String {
        "App/Feature\(number % 50)/\(className(number)).swift"
    }

    public static func write(into builder: ProjectBuilder) throws {
        for number in 0..<swiftFileCount {
            try builder.write(swiftFile(number), swiftSource(number))
        }
        for number in 0..<colorSetCount {
            try builder.write(
                "App/Assets.xcassets/Palette\(number / 50)/Color\(number).colorset/Contents.json",
                ProjectBuilder.colorSet([
                    (nil, [String(format: "%.3f", Double(number % 256) / 255), "0.500", "0.250"]),
                    ("dark", ["\(number % 256)", "64", "32"]),
                ]))
        }
        try builder.write("App/Assets.xcassets/Contents.json", #"{"info":{"author":"xcode","version":1}}"#)
        for catalog in 0..<catalogCount {
            try builder.write("App/Strings\(catalog).xcstrings", catalogSource(catalog))
        }
    }

    /// About 50 lines: a class with a nested type, members, comments and strings, and an
    /// extension.
    public static func swiftSource(_ number: Int, revision: Int = 0) -> String {
        let name = className(number)
        return """
        import UIKit

        /// A generated view, number \(number), revision \(revision).
        final class \(name): UIView {
            struct Style {
                var radius: CGFloat = 8
                var title = "class NotAType\(number)"
            }

            private let style = Style()
            private let label = UILabel()
            /* A comment with { braces } that are not code. */
            private var items: [String] = []

            override init(frame: CGRect) {
                super.init(frame: frame)
                addSubview(label)
                label.text = "Item \\(items.count) of \(number)"
            }

            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func layoutSubviews() {
                super.layoutSubviews()
                label.frame = bounds.insetBy(dx: style.radius, dy: style.radius)
                for (index, item) in items.enumerated() where index.isMultiple(of: 2) {
                    print(index, item)
                }
            }

            class func make() -> \(name) {
                \(name)(frame: .zero)
            }
        }

        extension \(name) {
            enum Mode: Int, CaseIterable {
                case compact, regular
            }

            func apply(_ mode: Mode) {
                switch mode {
                case .compact: items = ["a"]
                case .regular: items = ["a", "b"]
                }
            }
        }
        """
    }

    private static func catalogSource(_ catalog: Int) -> String {
        let keys = (0..<keysPerCatalog).map { key in
            let localizations = languages.map { language in
                let value = "\(language) text \(catalog).\(key) %@"
                return #""\#(language)":{"stringUnit":{"state":"translated","value":"\#(value)"}}"#
            }
            return #""key.\#(catalog).\#(key)":{"localizations":{\#(localizations.joined(separator: ","))}}"#
        }
        return #"{"sourceLanguage":"en","strings":{\#(keys.joined(separator: ","))},"version":"1.0"}"#
    }
}

/// The longest pause of the main thread while it is measured (C-SRC-02): a timer on the main
/// queue every 5 ms, and the longest time between two of its ticks.
@MainActor
public final class MainThreadStallMeter {
    public private(set) var longestPause: TimeInterval = 0
    private var timer: DispatchSourceTimer?
    private var lastTick = DispatchTime.now()

    public init() {}

    public func start() {
        longestPause = 0
        lastTick = .now()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(5), repeating: .milliseconds(5), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops measuring, and gives the longest pause, counting up to now.
    @discardableResult
    public func stop() -> TimeInterval {
        tick()
        timer?.cancel()
        timer = nil
        return longestPause
    }

    private func tick() {
        let now = DispatchTime.now()
        let pause = Double(now.uptimeNanoseconds - lastTick.uptimeNanoseconds) / 1_000_000_000
        longestPause = max(longestPause, pause)
        lastTick = now
    }
}
