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
public enum TraitKind: Equatable, Hashable, Sendable {
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
