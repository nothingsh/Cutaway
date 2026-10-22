import AppKit

/// Puts plain text on a pasteboard: what the attribute panel's copy buttons and Copy LLDB
/// Command do.
@MainActor
enum TextPasteboard {
    /// Puts `text` on the general pasteboard, as the copy buttons do outside tests.
    static func copyToGeneral(_ text: String) {
        copy(text, to: .general)
    }

    static func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
