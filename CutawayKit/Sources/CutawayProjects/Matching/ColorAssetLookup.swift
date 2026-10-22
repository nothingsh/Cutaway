import CutawayWire

/// A colour set an attribute's colour is (C-SRC-04).
public struct AssetColorMatch: Equatable, Hashable, Sendable {
    /// The set's name, namespace and all: `Brand/Blue`.
    public var name: String
    /// The appearance whose colour matched; nil when the colour is dynamic and both of its
    /// appearances matched.
    public var appearance: AssetAppearance?

    public init(name: String, appearance: AssetAppearance?) {
        self.name = name
        self.appearance = appearance
    }
}

/// The colour sets of a project by their colours (C-SRC-04), made once when the index is
/// built, so that a look-up costs the same however many sets there are.
public struct ColorAssetLookup: Equatable, Sendable {
    /// Each set's colour in each appearance, every idiom's.
    private var byColor: [RoundedColor: [AssetColorMatch]] = [:]
    /// Each set's colours in the light and in the dark appearance; a set without one of them
    /// has its colour for any appearance there.
    private var byPair: [Pair: [String]] = [:]

    private struct Pair: Hashable, Sendable {
        var light: RoundedColor
        var dark: RoundedColor
    }

    public init(_ sets: [ColorSet] = []) {
        for set in sets {
            var idioms: [String: [AssetAppearance: RoundedColor]] = [:]
            for entry in set.entries {
                guard let (appearance, color) = AssetColor.resolve(entry) else { continue }
                byColor[color, default: []].append(AssetColorMatch(name: set.name, appearance: appearance))
                idioms[entry.idiom ?? "", default: [:]][appearance] = color
            }
            for colors in idioms.values {
                guard let light = colors[.light] ?? colors[.any], let dark = colors[.dark] ?? colors[.any]
                else { continue }
                byPair[Pair(light: light, dark: dark), default: []].append(set.name)
            }
        }
    }

    /// The sets a colour is, the first by name first. With `appearanceColors` (a dynamic
    /// colour, P-ATTR-17) both appearances must match; without, the value matches a set's
    /// colour in any of its appearances, and the most general one is named.
    public func matches(_ value: Color, appearanceColors: AppearanceColors? = nil) -> [AssetColorMatch] {
        if let appearanceColors {
            let pair = Pair(light: RoundedColor(appearanceColors.light), dark: RoundedColor(appearanceColors.dark))
            return Set(byPair[pair] ?? []).sorted().map { AssetColorMatch(name: $0, appearance: nil) }
        }
        var best: [String: AssetAppearance] = [:]
        for match in byColor[RoundedColor(value)] ?? [] {
            guard let appearance = match.appearance else { continue }
            if let known = best[match.name], Self.rank(known) <= Self.rank(appearance) { continue }
            best[match.name] = appearance
        }
        return best.keys.sorted().map { AssetColorMatch(name: $0, appearance: best[$0]) }
    }

    /// Any before light before dark.
    private static func rank(_ appearance: AssetAppearance) -> Int {
        switch appearance {
        case .any: 0
        case .light: 1
        case .dark: 2
        }
    }
}
