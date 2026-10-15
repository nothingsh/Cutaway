import Combine
import CutawayScene
import Foundation

/// The settings window's values, kept in the user defaults as they change (C-PREF-01).
///
/// Reading is forgiving one key at a time: a key that is missing, of the wrong type or out of
/// range reads as its default, and what is kept is left as it is.
@MainActor
public final class AppSettings: ObservableObject {
    /// The user defaults keys.
    public enum Key {
        public static let newInspectionMode = "Settings.newInspectionMode"
        public static let layerSpacing = "Settings.layerSpacing"
        public static let showsHiddenLayers = "Settings.showsHiddenLayers"
        /// The boolean of earlier versions, read when `borderStyle` is not kept.
        public static let showsBorders = "Settings.showsBorders"
        public static let borderStyle = "Settings.borderStyle"
        public static let onlyAppClasses = "Settings.onlyAppClasses"
        public static let showsConstraintEnds = "Settings.showsConstraintEnds"
        public static let page = "Settings.page"
        public static let appearance = "Settings.appearance"
    }

    /// How Cutaway looks (C-PREF-03): as the system says, or always light or dark.
    public enum Appearance: String, CaseIterable, Sendable {
        case system, light, dark
    }

    /// Cutaway's appearance (C-PREF-03), on the General page. It applies at once to every
    /// window.
    @Published public var appearance: Appearance {
        didSet {
            if appearance == .system {
                if !isLoading { defaults.removeObject(forKey: Key.appearance) }
            } else {
                store(appearance.rawValue, at: Key.appearance)
            }
        }
    }

    /// The mode a new inspection opens in (C-PREF-02).
    @Published public var newInspectionMode: PreviewMode {
        didSet { store(newInspectionMode == .twoD ? "2d" : "3d", at: Key.newInspectionMode) }
    }

    /// The 3D layer spacing a new inspection starts with, in whole points within
    /// `Camera.spacingRange`.
    @Published public var layerSpacing: Double {
        didSet {
            // Setting it here does not run this observer again.
            let limited = Self.limitedSpacing(layerSpacing)
            if limited != layerSpacing { layerSpacing = limited }
            store(layerSpacing, at: Key.layerSpacing)
        }
    }

    /// Whether a new inspection shows hidden layers.
    @Published public var showsHiddenLayers: Bool {
        didSet { store(showsHiddenLayers, at: Key.showsHiddenLayers) }
    }

    /// How a new inspection outlines the layers (C-PREV-17).
    @Published public var borderStyle: BorderStyle {
        didSet {
            store(borderStyle.rawValue, at: Key.borderStyle)
            // The new key decides from now on.
            if !isLoading { defaults.removeObject(forKey: Key.showsBorders) }
        }
    }

    /// Whether a new inspection outlines only the app's own classes (C-PREV-17).
    @Published public var onlyAppClasses: Bool {
        didSet { store(onlyAppClasses, at: Key.onlyAppClasses) }
    }

    /// Whether a new inspection marks every end of the selected layer's constraints
    /// (C-PREV-18).
    @Published public var showsConstraintEnds: Bool {
        didSet { store(showsConstraintEnds, at: Key.showsConstraintEnds) }
    }

    /// The settings window's page last shown, by its index; the first one at first. Not a
    /// setting: Restore Defaults leaves it.
    public var page: Int {
        get {
            guard let number = defaults.object(forKey: Key.page) as? NSNumber, !Self.isBoolean(number)
            else { return 0 }
            return max(number.intValue, 0)
        }
        set { defaults.set(newValue, forKey: Key.page) }
    }

    /// Whether every value of the Preview page is its default: Restore Defaults is off then.
    @Published public private(set) var isShowingPreviewDefaults = true

    private let defaults: UserDefaults
    /// True while the model sets its own values: they are not written.
    private var isLoading = false

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let start = InspectionStart()
        newInspectionMode = switch defaults.object(forKey: Key.newInspectionMode) as? String {
        case "3d": .threeD
        default: start.previewMode
        }
        layerSpacing = Self.spacing(defaults.object(forKey: Key.layerSpacing))
            ?? start.layerSpacing
        showsHiddenLayers = Self.bool(defaults.object(forKey: Key.showsHiddenLayers))
            ?? start.showsHiddenLayers
        // The style kept, else the switch of an earlier version: on is by kind (C-PREV-17).
        borderStyle = (defaults.object(forKey: Key.borderStyle) as? String)
            .flatMap(BorderStyle.init(rawValue:))
            ?? Self.bool(defaults.object(forKey: Key.showsBorders)).map {
                BorderOptions(showsBorders: $0).style
            }
            ?? start.borders.style
        onlyAppClasses = Self.bool(defaults.object(forKey: Key.onlyAppClasses))
            ?? start.borders.onlyAppClasses
        showsConstraintEnds = Self.bool(defaults.object(forKey: Key.showsConstraintEnds))
            ?? start.showsConstraintEnds
        appearance = (defaults.object(forKey: Key.appearance) as? String)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        isShowingPreviewDefaults = computeIsShowingPreviewDefaults()
    }

    /// How a new inspection starts.
    public var inspectionStart: InspectionStart {
        InspectionStart(
            previewMode: newInspectionMode, layerSpacing: layerSpacing,
            showsHiddenLayers: showsHiddenLayers,
            borders: BorderOptions(style: borderStyle, onlyAppClasses: onlyAppClasses),
            showsConstraintEnds: showsConstraintEnds)
    }

    /// Puts every value of the Preview page back to its default and forgets what was kept.
    public func restorePreviewDefaults() {
        let start = InspectionStart()
        load {
            newInspectionMode = start.previewMode
            layerSpacing = start.layerSpacing
            showsHiddenLayers = start.showsHiddenLayers
            borderStyle = start.borders.style
            onlyAppClasses = start.borders.onlyAppClasses
            showsConstraintEnds = start.showsConstraintEnds
        }
        for key in [
            Key.newInspectionMode, Key.layerSpacing, Key.showsHiddenLayers, Key.showsBorders,
            Key.borderStyle, Key.onlyAppClasses, Key.showsConstraintEnds,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Keeping

    private func store(_ value: Any, at key: String) {
        if !isLoading { defaults.set(value, forKey: key) }
        refreshDefaultsState()
    }

    private func load(_ change: () -> Void) {
        isLoading = true
        change()
        isLoading = false
        refreshDefaultsState()
    }

    private func refreshDefaultsState() {
        let showing = computeIsShowingPreviewDefaults()
        if showing != isShowingPreviewDefaults { isShowingPreviewDefaults = showing }
    }

    private func computeIsShowingPreviewDefaults() -> Bool {
        inspectionStart == InspectionStart()
    }

    // MARK: - Reading

    private static func limitedSpacing(_ spacing: Double) -> Double {
        let range = Camera.spacingRange
        guard spacing.isFinite else { return InspectionStart().layerSpacing }
        return min(max(spacing.rounded(), range.lowerBound), range.upperBound)
    }

    /// A number that is not a boolean, finite and within range.
    private static func spacing(_ object: Any?) -> Double? {
        guard let number = object as? NSNumber, !isBoolean(number) else { return nil }
        let value = number.doubleValue
        guard value.isFinite, Camera.spacingRange.contains(value) else { return nil }
        return value
    }

    private static func bool(_ object: Any?) -> Bool? {
        guard let number = object as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
