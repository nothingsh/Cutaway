import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-PREF-02: the settings decide how a new inspection starts, and nothing else: windows
/// already open, and a reconnected inspection, keep what they show.
final class InspectionStartTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")
    private static let first = AppLocation.simulator(port: 48160)
    private static let other = AppLocation.simulator(port: 48161)
    private static let later = AppLocation.simulator(port: 48163)

    private static var otherApp: AppInfo {
        var info = demo
        info.name = "Other"
        info.bundleID = "dev.cutaway.other"
        return info
    }

    private static let threeDAt80 = InspectionStart(
        previewMode: .threeD, layerSpacing: 80, showsHiddenLayers: true, borders: BorderOptions(style: .off))

    /// The settings the store reads a new inspection's start from.
    @MainActor
    private final class Settings {
        var start: InspectionStart

        init(start: InspectionStart) {
            self.start = start
        }
    }

    private func session() -> Session {
        Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
    }

    @MainActor
    private func listing() -> AppListStore {
        let model = AppListStore()
        model.apply(.found(Self.first, Self.demo, session()))
        model.apply(.found(Self.other, Self.otherApp, session()))
        return model
    }

    @MainActor
    func test_C_PREF_02_aNewInspectionStartsAsTheSettingsSay() throws {
        let model = listing()
        model.inspect(Self.other)
        let earlier = try XCTUnwrap(model.inspection(at: Self.other))

        // A reference, so that the change at the end reaches the closure.
        let settings = Settings(start: Self.threeDAt80)
        model.inspectionStart = { settings.start }
        model.inspect(Self.first)
        let inspection = try XCTUnwrap(model.inspection(at: Self.first))
        inspection.apply(try Fixtures.hierarchy())

        XCTAssertEqual(inspection.previewMode, .threeD)
        XCTAssertEqual(inspection.cameras.threeD.layerSpacing, 80)
        XCTAssertEqual(inspection.cameras.twoD, Camera.flat)
        XCTAssertTrue(inspection.showsHiddenLayers)
        XCTAssertFalse(inspection.borders.showsBorders)
        XCTAssertEqual(inspection.start, Self.threeDAt80)

        // The one opened before is as it was.
        XCTAssertEqual(earlier.previewMode, .twoD)
        XCTAssertEqual(earlier.cameras.threeD.layerSpacing, 50)
        XCTAssertFalse(earlier.showsHiddenLayers)
        XCTAssertTrue(earlier.borders.showsBorders)

        // Settings changed later reach neither.
        settings.start = InspectionStart()
        model.inspect(Self.first)
        XCTAssertEqual(model.inspection(at: Self.first)?.previewMode, .threeD)
    }

    @MainActor
    func test_C_PREF_02_resetGoesBackToHowTheInspectionStarted() throws {
        let inspection = InspectionStore(
            session: session(), start: Self.threeDAt80)
        inspection.apply(try Fixtures.hierarchy())
        inspection.setLayerSpacing(120)
        inspection.rotate(byDragOf: 40, 10)
        inspection.resetCamera()
        XCTAssertEqual(inspection.cameras.threeD, Self.threeDAt80.cameras.threeD)

        inspection.setPreviewMode(.twoD)
        inspection.pan(by: 10, 10)
        inspection.resetCamera()
        XCTAssertEqual(inspection.cameras.twoD, Camera.flat)
    }

    @MainActor
    func test_C_PREF_02_aReconnectedInspectionDoesNotReadTheSettings() throws {
        let model = listing()
        model.inspect(Self.first)
        let old = try XCTUnwrap(model.inspection(at: Self.first))
        XCTAssertEqual(old.previewMode, .twoD)

        model.inspectionStart = { Self.threeDAt80 }
        model.apply(.lost(Self.first))
        model.apply(.found(Self.later, Self.demo, session()))
        let new = try XCTUnwrap(model.inspection(at: Self.later))
        XCTAssertEqual(new.previewMode, .twoD)
        XCTAssertEqual(new.cameras.threeD.layerSpacing, 50)
        XCTAssertFalse(new.showsHiddenLayers)
        XCTAssertTrue(new.borders.showsBorders)

        // Its Reset View is the old inspection's.
        XCTAssertEqual(new.start, InspectionStart())
        new.setPreviewMode(.threeD)
        new.setLayerSpacing(90)
        new.resetCamera()
        XCTAssertEqual(new.cameras.threeD.layerSpacing, 50)
    }
}
