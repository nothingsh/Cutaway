import AppKit
import Foundation
import Security
import UniformTypeIdentifiers
import XCTest

/// C-APP-01. These tests run inside the app process, so they check the product that was
/// actually built rather than the text of project.yml.
final class AppFormTests: XCTestCase {
    func test_C_APP_01_minimumSystemVersionIsMacOS14() {
        XCTAssertEqual(
            Bundle.main.bundleIdentifier, "dev.cutaway.Cutaway",
            "this test must be hosted by the app")
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String, "14.0")
    }

    func test_C_APP_01_appIsNotSandboxed() throws {
        XCTAssertEqual(
            Bundle.main.bundleIdentifier, "dev.cutaway.Cutaway",
            "this test must be hosted by the app")

        let task = try XCTUnwrap(SecTaskCreateFromSelf(nil))
        let entitlement = SecTaskCopyValueForEntitlement(
            task, "com.apple.security.app-sandbox" as CFString, nil)
        XCTAssertNotEqual(entitlement as? Bool, true, "the app carries the sandbox entitlement")

        // The system sets this for every sandboxed process.
        XCTAssertNil(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"])
    }

    /// The launcher shows the icon from the app's own asset catalog: on the first launch of a
    /// fresh build the system's copy can still be the blank template.
    @MainActor
    func test_C_APP_01_theAppCarriesItsIcon() throws {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        let icon = try XCTUnwrap(NSImage(named: "AppIcon"), "no AppIcon in the asset catalog")
        XCTAssertGreaterThanOrEqual(icon.size.width, 16)
    }

    /// C-ARCH-01: the app declares the archive type and that it handles it (Resources/ARCHIVE.md).
    func test_C_ARCH_01_theAppDeclaresTheArchiveType() throws {
        let exported = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations")
                as? [[String: Any]])
        let archive = try XCTUnwrap(
            exported.first { $0["UTTypeIdentifier"] as? String == "dev.cutaway.archive" })
        XCTAssertEqual(archive["UTTypeConformsTo"] as? [String], ["public.data"])
        let tags = try XCTUnwrap(archive["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], ["cutaway"])

        let documents = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let document = try XCTUnwrap(documents.first {
            ($0["LSItemContentTypes"] as? [String])?.contains("dev.cutaway.archive") == true
        })
        XCTAssertEqual(document["CFBundleTypeRole"] as? String, "Editor")
        XCTAssertEqual(document["LSHandlerRank"] as? String, "Owner")

        XCTAssertEqual(UTType(filenameExtension: "cutaway")?.identifier, "dev.cutaway.archive")
    }
}
