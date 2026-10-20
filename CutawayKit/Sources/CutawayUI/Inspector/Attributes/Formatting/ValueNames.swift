import CutawayModel
import CutawayWire

/// What a value is known by, besides itself (C-ATTR-22, C-SRC-04, C-SRC-05): a colour's name
/// from the app's asset catalog or UIKit, its two appearances (C-ATTR-25), and the key of the
/// string table a text comes from.
struct ValueNames: Equatable {
    /// The colour's name, shown in place of its code; nil for a colour known by its code.
    var colorName: String?
    /// The colour's other names, for its tooltip before the code: "Asset: BrandBlue (Dark)",
    /// "System Blue".
    var colorNotes: [String] = []
    /// The colour in light and in dark when they differ (C-ATTR-25, P-ATTR-17).
    var appearance: AppearanceColors?
    /// "Key home.title · Localizable", the note under a text; nil for a text from no table.
    var stringKey: String?
    /// Every key the text is a value of, a line each, for the note's tooltip.
    var stringKeys: String?

    static let none = Self()

    /// A UIKit system colour's name alone (C-ATTR-22).
    init(systemColorName: String?) {
        colorName = systemColorName.map(AttributeText.systemColorName)
    }

    init(
        colorName: String? = nil, colorNotes: [String] = [], stringKey: String? = nil,
        stringKeys: String? = nil
    ) {
        self.colorName = colorName
        self.colorNotes = colorNotes
        self.stringKey = stringKey
        self.stringKeys = stringKeys
    }

    /// The names of an attribute's value: the first colour set it matches in the project, then
    /// UIKit's name (C-ATTR-24, until the app's own names in 1.2's `dev.2`); the first key of a
    /// text. Only the value the app gave has names: one on its way has none.
    init(_ attribute: Attribute, index: ProjectIndex?) {
        switch attribute.value {
        case .color(let color):
            let system = attribute.systemColorName.map(AttributeText.systemColorName)
            let assets = index?.colors.matches(color, appearanceColors: attribute.appearanceColors) ?? []
            guard let first = assets.first else {
                self.init(systemColorName: attribute.systemColorName)
                appearance = attribute.appearanceColors
                return
            }
            self.init(colorName: first.name, colorNotes: assets.map(Self.note) + [system].compactMap { $0 })
            appearance = attribute.appearanceColors
        case .string(let text):
            let keys = index?.keys.matches(text) ?? []
            guard let first = keys.first else {
                self = .none
                return
            }
            self.init(
                stringKey: Self.line(first),
                stringKeys: keys.count > 1 ? keys.map(Self.line).joined(separator: "\n") : nil)
        default:
            self.init(systemColorName: attribute.systemColorName)
        }
    }

    /// "Asset: BrandBlue", with the appearance whose colour it is when that is not any.
    private static func note(_ match: AssetColorMatch) -> String {
        switch match.appearance {
        case .light: localized("attributes.color.assetInAppearance", match.name, localized("attributes.color.light"))
        case .dark: localized("attributes.color.assetInAppearance", match.name, localized("attributes.color.dark"))
        case .any, nil: localized("attributes.color.asset", match.name)
        }
    }

    private static func line(_ key: StringKeyMatch) -> String {
        localized("attributes.value.stringKey", key.key, key.table)
    }
}
