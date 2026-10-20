// MARK: - Environment (protocol 1.2)

/// The trait values a client may override (P-ENV-01). `unspecified` means not overridden, or,
/// in `Environment.current`, not readable; values this client does not know read as it too.
public enum UserInterfaceStyle: Equatable, Sendable { case unspecified, light, dark }

public enum ContentSizeCategory: Equatable, Sendable {
    case unspecified, extraSmall, small, medium, large, extraLarge, extraExtraLarge
    case extraExtraExtraLarge, accessibilityMedium, accessibilityLarge, accessibilityExtraLarge
    case accessibilityExtraExtraLarge, accessibilityExtraExtraExtraLarge
}

public enum LayoutDirection: Equatable, Sendable { case unspecified, leftToRight, rightToLeft }

public enum SizeClass: Equatable, Sendable { case unspecified, compact, regular }

/// A kind of trait a server can override (P-ENV-01).
public enum TraitKind: Equatable, Hashable, Sendable, CaseIterable {
    case userInterfaceStyle, contentSizeCategory, layoutDirection, horizontalSizeClass
    case verticalSizeClass
}

/// The five traits. An absent `Traits` on the wire reads as all `unspecified` (P-ENV-01).
public struct Traits: Equatable, Sendable {
    public var userInterfaceStyle: UserInterfaceStyle
    public var contentSizeCategory: ContentSizeCategory
    public var layoutDirection: LayoutDirection
    public var horizontalSizeClass: SizeClass
    public var verticalSizeClass: SizeClass

    public init(
        userInterfaceStyle: UserInterfaceStyle = .unspecified,
        contentSizeCategory: ContentSizeCategory = .unspecified,
        layoutDirection: LayoutDirection = .unspecified,
        horizontalSizeClass: SizeClass = .unspecified, verticalSizeClass: SizeClass = .unspecified
    ) {
        self.userInterfaceStyle = userInterfaceStyle
        self.contentSizeCategory = contentSizeCategory
        self.layoutDirection = layoutDirection
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
    }

    /// No trait set: as overrides, none at all (P-ENV-02).
    public static let unspecified = Self()
}

extension Traits {
    /// One trait's value, whatever its kind.
    public enum Value: Equatable, Sendable {
        case userInterfaceStyle(UserInterfaceStyle)
        case contentSizeCategory(ContentSizeCategory)
        case layoutDirection(LayoutDirection)
        case sizeClass(SizeClass)
    }

    /// The value of one kind of trait.
    public subscript(kind: TraitKind) -> Value {
        get {
            switch kind {
            case .userInterfaceStyle: .userInterfaceStyle(userInterfaceStyle)
            case .contentSizeCategory: .contentSizeCategory(contentSizeCategory)
            case .layoutDirection: .layoutDirection(layoutDirection)
            case .horizontalSizeClass: .sizeClass(horizontalSizeClass)
            case .verticalSizeClass: .sizeClass(verticalSizeClass)
            }
        }
        set {
            switch (kind, newValue) {
            case (.userInterfaceStyle, .userInterfaceStyle(let value)): userInterfaceStyle = value
            case (.contentSizeCategory, .contentSizeCategory(let value)): contentSizeCategory = value
            case (.layoutDirection, .layoutDirection(let value)): layoutDirection = value
            case (.horizontalSizeClass, .sizeClass(let value)): horizontalSizeClass = value
            case (.verticalSizeClass, .sizeClass(let value)): verticalSizeClass = value
            default: preconditionFailure("a \(newValue) is not a value of \(kind)")
            }
        }
    }

    /// Whether the trait of this kind is set: as overrides, whether it is overridden.
    public func isSpecified(_ kind: TraitKind) -> Bool {
        self[kind] != Self.unspecified[kind]
    }

    /// The kinds that are set, in the order of `TraitKind.allCases`.
    public var specifiedKinds: [TraitKind] { TraitKind.allCases.filter(isSpecified) }

    /// These traits with every trait `overrides` sets put in their place, as the server
    /// applies overrides over the app's own traits (P-ENV-02).
    public func overridden(by overrides: Traits) -> Traits {
        var result = self
        for kind in overrides.specifiedKinds { result[kind] = overrides[kind] }
        return result
    }
}

/// Replaces every override of the connection (P-ENV-02).
public struct SetEnvironment: Equatable, Sendable {
    public var overrides: Traits

    public init(overrides: Traits) {
        self.overrides = overrides
    }
}

/// The answer to `GetEnvironment` and `SetEnvironment` (P-ENV-01).
public struct Environment: Equatable, Sendable {
    /// What the client has set on this connection.
    public var overrides: Traits
    /// The key window's effective traits, overrides included.
    public var current: Traits
    /// What the server can override on this device, each at most once, in the server's order.
    /// Kinds this client does not know are left out.
    public var overridable: [TraitKind]

    public init(overrides: Traits, current: Traits, overridable: [TraitKind]) {
        self.overrides = overrides
        self.current = current
        self.overridable = overridable
    }
}
