import AppKit
import CutawayModel

/// Opens a declaration in Xcode at its line (C-SRC-03): the Xcode Launch Services finds runs
/// its own `xed`, with `DEVELOPER_DIR` set to it, so that the global developer directory, which
/// may be the Command Line Tools, does not matter. Without Xcode, without its `xed`, or when
/// `xed` cannot start or fails, the file opens in its default app, without the line.
///
/// Each step can be replaced: tests record what would run instead of running it.
@MainActor
struct XcodeOpener {
    static let xcodeBundleID = "com.apple.dt.Xcode"
    /// Inside Xcode's bundle.
    static let xedPath = "Contents/Developer/usr/bin/xed"

    /// Where Xcode is, or nil.
    var locateXcode: @MainActor () -> URL? = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.xcodeBundleID)
    }

    /// Whether a file can be run.
    var isExecutable: @MainActor (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }

    /// Starts a program with arguments and environment, and calls back on the main thread with
    /// its exit status once it ends; throws when it cannot start.
    var run: @MainActor (URL, [String], [String: String], @escaping @MainActor (Int32) -> Void) throws -> Void =
        Self.runProcess

    /// Opens a file in its default app.
    var openFile: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }

    func open(_ location: SourceLocation) {
        let file = location.file
        guard let xcode = locateXcode() else {
            openFile(file)
            return
        }
        let xed = xcode.appendingPathComponent(Self.xedPath)
        guard isExecutable(xed) else {
            openFile(file)
            return
        }
        var environment = ProcessInfo.processInfo.environment
        environment["DEVELOPER_DIR"] = xcode.appendingPathComponent("Contents/Developer").path
        let openFile = openFile
        do {
            try run(xed, ["--line", String(location.line), file.path], environment) { status in
                if status != 0 { openFile(file) }
            }
        } catch {
            openFile(file)
        }
    }

    private static func runProcess(
        _ executable: URL, _ arguments: [String], _ environment: [String: String],
        _ ended: @escaping @MainActor (Int32) -> Void
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            let status = process.terminationStatus
            Task { @MainActor in ended(status) }
        }
        try process.run()
    }
}
