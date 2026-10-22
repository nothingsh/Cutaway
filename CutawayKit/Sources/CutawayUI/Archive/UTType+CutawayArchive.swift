import UniformTypeIdentifiers

extension UTType {
    /// A Cutaway archive, the type the app's Info.plist exports (C-ARCH-02, C-ARCH-04).
    static var cutawayArchive: UTType { UTType(exportedAs: "dev.cutaway.archive") }
}
