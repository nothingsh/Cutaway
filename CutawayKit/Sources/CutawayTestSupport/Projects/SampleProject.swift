import Foundation

/// The sample project of C-SRC-03: the four kinds of declaration (a Swift class, an
/// Objective-C header, a nested type and a generic one), a type with only an extension, a
/// class declared twice, and words that look like declarations in comments, strings and
/// function bodies. It has color sets and string tables for C-SRC-02, and declarations in the
/// folders the index leaves out.
public enum SampleProject {
    /// Where the sample's declarations are: the file and the line of the type's name.
    public struct Place: Equatable, CustomStringConvertible {
        public var file: String
        public var line: Int

        public init(file: String, line: Int) {
            self.file = file
            self.line = line
        }

        public var description: String { "\(file):\(line)" }
    }

    public static let homeViewController = "Shop/Home/HomeViewController.swift"
    public static let outer = "Shop/Home/Views/Outer.swift"
    public static let listCell = "Shop/Lists/ListCell.swift"
    public static let headerView = "Shop/Home/Views/HomeHeaderView.swift"
    public static let legacyHeaderView = "ShopLegacy/Home/HomeHeaderView.swift"
    public static let cardViewHeader = "Legacy/LegacyCardView.h"
    public static let cardViewImplementation = "Legacy/LegacyCardView.m"

    /// The files and their text.
    public static let files: [String: String] = [
        homeViewController: """
        import UIKit

        // class NotInAComment {}
        /* class NotInABlock { /* nested */ class StillNotInABlock {} } */

        @MainActor
        final class HomeViewController: UIViewController {
            private let caption = "class NotInAString"
            let multiline = \"\"\"
                struct NotInAMultilineString {}
                \"\"\"
            let raw = #"enum NotInARawString "quoted" \\#(1) {}"#
            let interpolated = "\\(items.map { "class NotInAnInterpolation \\($0)" })"
            let regex = #/class NotInARegex/#

            class func make() -> HomeViewController { HomeViewController() }
            class var shared: Int { 0 }
            override class func awakeFromNib() {}

            func viewDidLoad() {
                struct LocalType {}
                let make = { class LocalInAClosure {} }
            }

            var computed: Int {
                enum LocalInAnAccessor {}
                return 0
            }
        }
        """,
        outer: """
        enum Outer {
            struct Inner {}
        }

        struct Other {
            struct Inner {}
        }

        extension Outer {
            actor Worker {}
        }

        extension Outer.Inner {
            @objc(SHPDeep) public final class Deep {}
        }
        """,
        listCell: """
        import UIKit

        public class ListCell<Item: Hashable>: UICollectionViewCell where Item: Sendable {
            func configure(_ item: Item) {}
        }
        """,
        "Shop/Lists/ExtensionOnly.swift": """
        extension OnlyExtended {
            func help() {}
        }

        protocol Listing: class {}
        """,
        headerView: """
        import UIKit

        final class HomeHeaderView: UIView {}
        """,
        legacyHeaderView: """
        import UIKit

        #if LEGACY
        class HomeHeaderView: UIView {}
        #endif
        """,
        cardViewHeader: """
        #import <UIKit/UIKit.h>

        // @interface NotInAComment : NSObject
        NS_ASSUME_NONNULL_BEGIN

        @interface LegacyCardView : UIView
        @property (nonatomic, copy) NSString *title;
        @end

        @interface LegacyCardView (Shadow)
        @end

        @interface Box<ObjectType> : NSObject
        @end

        NS_ASSUME_NONNULL_END
        """,
        cardViewImplementation: """
        #import "LegacyCardView.h"

        static NSString *const note = @"@interface NotInAString : NSObject";

        @interface LegacyCardView ()
        @end

        @implementation LegacyCardView
        @end

        @implementation LegacyCardView (Shadow)
        @end

        @implementation LegacyOnlyImplemented
        @end
        """,
        // The folders the index leaves out (C-SRC-02).
        "Pods/Alamofire/Session.swift": "class InPods {}",
        "Carthage/Checkouts/Kit/Kit.swift": "class InCarthage {}",
        "DerivedData/Shop/Generated.swift": "class InDerivedData {}",
        "build/Generated.swift": "class InBuild {}",
        ".build/checkouts/Package.swift": "class InDotBuild {}",
        "SourcePackages/checkouts/Package/Source.swift": "class InSourcePackages {}",
        ".hidden/Hidden.swift": "class InHidden {}",
        // The asset catalog: one set at the top, one in a group that provides a namespace and
        // one in a group that does not; an image set is not a color set.
        "Shop/Assets.xcassets/Contents.json": #"{"info":{"author":"xcode","version":1}}"#,
        "Shop/Assets.xcassets/AccentColor.colorset/Contents.json":
            ProjectBuilder.colorSet([(nil, ["0.000", "0.478", "1.000"])]),
        "Shop/Assets.xcassets/Brand/Contents.json":
            #"{"info":{"author":"xcode","version":1},"properties":{"provides-namespace":true}}"#,
        "Shop/Assets.xcassets/Brand/Blue.colorset/Contents.json":
            ProjectBuilder.colorSet([(nil, ["0x1E", "0x6B", "0xFF"]), ("dark", ["91", "231", "255"])]),
        "Shop/Assets.xcassets/Plain/Contents.json": #"{"info":{"author":"xcode","version":1}}"#,
        "Shop/Assets.xcassets/Plain/Gray.colorset/Contents.json":
            #"{"colors":[{"idiom":"universal","color":{"platform":"ios","reference":"systemGrayColor"}}]}"#,
        "Shop/Assets.xcassets/Logo.imageset/Contents.json": #"{"images":[]}"#,
        // The string tables.
        "Shop/Localizable.xcstrings": #"""
        {
          "sourceLanguage" : "en",
          "strings" : {
            "home.title" : {
              "localizations" : {
                "en" : { "stringUnit" : { "state" : "translated", "value" : "Home" } },
                "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "首页" } }
              }
            },
            "items.count" : {
              "localizations" : {
                "en" : { "variations" : { "plural" : {
                  "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld item" } },
                  "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld items" } }
                } } }
              }
            },
            "Sign In" : { }
          },
          "version" : "1.0"
        }
        """#,
        "Shop/en.lproj/InfoPlist.strings": #""CFBundleDisplayName" = "Demo Shop";"#,
        "Shop/zh-Hans.lproj/InfoPlist.strings": #""CFBundleDisplayName" = "演示商店";"#,
    ]

    /// Writes the sample into `builder`'s folder.
    public static func write(into builder: ProjectBuilder) throws {
        for (path, text) in files {
            try builder.write(path, text)
        }
    }

    /// The line of the first line of `file` that holds `marker`.
    public static func place(_ file: String, _ marker: String) -> Place {
        let lines = (files[file] ?? "").components(separatedBy: "\n")
        let index = lines.firstIndex { $0.contains(marker) } ?? -1
        return Place(file: file, line: index + 1)
    }
}
