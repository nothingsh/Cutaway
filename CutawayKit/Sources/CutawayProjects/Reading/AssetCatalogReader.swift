import Foundation

/// Reads the `Contents.json` files of an asset catalog (C-SRC-02): a color set's colours, and
/// whether a folder provides a namespace for the sets inside it. The components are kept as
/// written; nothing here says what colour they make.
enum AssetCatalogReader {
    struct NotReadable: Error {}

    /// A color set's entries, from its `Contents.json`.
    static func colorEntries(in data: Data) throws -> [ColorSet.Entry] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotReadable()
        }
        let colors = root["colors"] as? [[String: Any]] ?? []
        return colors.map { item in
            let appearances = (item["appearances"] as? [[String: Any]] ?? []).compactMap { appearance in
                (appearance["appearance"] as? String).flatMap { name in
                    (appearance["value"] as? String).map { ColorSet.Entry.Appearance(appearance: name, value: $0) }
                }
            }
            let color = item["color"] as? [String: Any]
            let components = (color?["components"] as? [String: Any] ?? [:]).compactMapValues(text)
            return ColorSet.Entry(
                idiom: item["idiom"] as? String, appearances: appearances,
                colorSpace: color?["color-space"] as? String, components: components,
                systemReference: color?["reference"] as? String)
        }
    }

    /// Whether a folder's `Contents.json` says it provides a namespace.
    static func providesNamespace(_ data: Data) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotReadable()
        }
        let properties = root["properties"] as? [String: Any]
        return (properties?["provides-namespace"] as? Bool) ?? false
    }

    /// A component as written: a string, or a number some tools write instead.
    private static func text(_ value: Any) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }
        return nil
    }
}
