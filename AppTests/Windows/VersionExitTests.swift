import AppKit
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: the app's version and build are well formed, and the About
/// panel, the archive's manifest and the handshake's `ClientInfo` carry the same version
/// (C-DIST-01). The archive's is checked in `ArchiveSaveExitTests`.
final class VersionExitTests: XCTestCase {
    private static var bundleVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func test_C_DIST_01_theAppsVersionAndBuildAreWellFormed() throws {
        let version = try XCTUnwrap(Self.bundleVersion)
        let build = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        XCTAssertTrue(AppVersion.isValid(version: version), version)
        XCTAssertTrue(AppVersion.isValid(build: build), build)
        XCTAssertEqual(AppVersion.current, AppVersion(bundle: .main))
        XCTAssertEqual(AppVersion.current.version, version)
        XCTAssertEqual(AppVersion.current.build, build)
    }

    @MainActor
    func test_C_DIST_01_theAboutPanelShowsTheAppsVersion() {
        let options = AboutPanel.options(info: Bundle.main.infoDictionary ?? [:], icon: nil)
        XCTAssertEqual(options[.applicationVersion] as? String, Self.bundleVersion)
        XCTAssertEqual(
            options[.version] as? String,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    @MainActor
    func test_C_DIST_01_theHandshakeCarriesTheAppsVersion() async throws {
        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        let version = try XCTUnwrap(Self.bundleVersion)
        XCTAssertEqual(delegate.clientInfo, ClientInfo(name: "Cutaway", version: version))

        let server = try await AppWindows.startMockServer(try .fixtures("handshake", "app-icon"))
        addTeardownBlock {
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        let deadline = Date().addingTimeInterval(5)
        var hello: Hello?
        while hello == nil, Date() < deadline {
            hello = await server.receivedFrames.lazy.compactMap {
                if case .hello(let hello) = $0.body { hello } else { nil }
            }.first
            if hello == nil { try await Task.sleep(for: .milliseconds(50)) }
        }
        let received = try XCTUnwrap(hello, "the app did not say hello")
        XCTAssertEqual(received.client?.version, version)
    }
}
