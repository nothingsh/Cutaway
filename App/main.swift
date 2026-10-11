import AppKit

// NSApplication holds its delegate weakly: this constant keeps it.
// swiftlint:disable:next prefixed_toplevel_constant
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
