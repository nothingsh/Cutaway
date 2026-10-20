import CutawayModel
import CutawayWire

/// What the environment controls, the View menu and an archive's subtitle call each trait
/// and value (C-ENV-01, C-ENV-04, C-MENU-05).
enum EnvironmentNames {
    /// The twelve text sizes, smallest first, as the slider and the menu list them.
    static let textSizes: [ContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]

    /// The values a kind is chosen from, App's Own first.
    static func choices(of kind: TraitKind) -> [Traits.Value] {
        switch kind {
        case .userInterfaceStyle:
            [UserInterfaceStyle.unspecified, .light, .dark].map { .userInterfaceStyle($0) }
        case .contentSizeCategory:
            ([.unspecified] + textSizes).map { .contentSizeCategory($0) }
        case .layoutDirection:
            [LayoutDirection.unspecified, .leftToRight, .rightToLeft].map { .layoutDirection($0) }
        case .horizontalSizeClass, .verticalSizeClass:
            [SizeClass.unspecified, .compact, .regular].map { .sizeClass($0) }
        }
    }

    /// The kind's name in the popover.
    static func title(of kind: TraitKind) -> String {
        switch kind {
        case .userInterfaceStyle: localized("environment.appearance")
        case .contentSizeCategory: localized("environment.textSize")
        case .layoutDirection: localized("environment.layoutDirection")
        case .horizontalSizeClass: localized("environment.widthClass")
        case .verticalSizeClass: localized("environment.heightClass")
        }
    }

    /// A value as a control or a menu item names it; an unspecified one is App's Own.
    static func name(of value: Traits.Value) -> String {
        switch value {
        case .userInterfaceStyle(let style):
            switch style {
            case .unspecified: localized("environment.appsOwn")
            case .light: localized("environment.light")
            case .dark: localized("environment.dark")
            }
        case .contentSizeCategory(.unspecified):
            localized("environment.appsOwn")
        case .contentSizeCategory(let size):
            shortName(of: size)
        case .layoutDirection(let direction):
            switch direction {
            case .unspecified: localized("environment.appsOwn")
            case .leftToRight: localized("environment.leftToRight")
            case .rightToLeft: localized("environment.rightToLeft")
            }
        case .sizeClass(let sizeClass):
            switch sizeClass {
            case .unspecified: localized("environment.appsOwn")
            case .compact: localized("environment.compact")
            case .regular: localized("environment.regular")
            }
        }
    }

    /// XS to AX5, as the system's text size settings abbreviate them; the same in every
    /// language.
    static func shortName(of size: ContentSizeCategory) -> String {
        switch size {
        case .unspecified: ""
        case .extraSmall: "XS"
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .extraLarge: "XL"
        case .extraExtraLarge: "XXL"
        case .extraExtraExtraLarge: "XXXL"
        case .accessibilityMedium: "AX1"
        case .accessibilityLarge: "AX2"
        case .accessibilityExtraLarge: "AX3"
        case .accessibilityExtraExtraLarge: "AX4"
        case .accessibilityExtraExtraExtraLarge: "AX5"
        }
    }

    /// "Now: Light" under a control: the key window's value, overrides included.
    static func now(_ kind: TraitKind, in current: Traits) -> String {
        let value = current[kind]
        let name = current.isSpecified(kind) ? name(of: value) : localized("environment.unknown")
        return localized("environment.now", name)
    }

    /// One override as a list of them names it: "Dark", "AX3", "Right to Left", "Compact
    /// Width". Nil when the kind is not overridden.
    static func overrideName(_ kind: TraitKind, in overrides: Traits) -> String? {
        guard overrides.isSpecified(kind) else { return nil }
        switch (kind, overrides[kind]) {
        case (.horizontalSizeClass, .sizeClass(.compact)): return localized("environment.compactWidth")
        case (.horizontalSizeClass, .sizeClass(.regular)): return localized("environment.regularWidth")
        case (.verticalSizeClass, .sizeClass(.compact)): return localized("environment.compactHeight")
        case (.verticalSizeClass, .sizeClass(.regular)): return localized("environment.regularHeight")
        default: return name(of: overrides[kind])
        }
    }

    /// Every override, in the popover's order: "Dark", "AX3". Empty when there is none.
    static func overrideNames(_ overrides: Traits) -> [String] {
        TraitKind.allCases.compactMap { overrideName($0, in: overrides) }
    }

    /// Why a change failed (C-ENV-02).
    static func failure(_ failure: EnvironmentFailure) -> String {
        switch failure {
        case .notSupported: localized("environment.failure.notSupported")
        case .appNotActive: localized("environment.failure.appNotActive")
        case .other: localized("environment.failure.other")
        }
    }
}
