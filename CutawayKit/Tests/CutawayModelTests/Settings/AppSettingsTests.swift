import Combine
import CutawayModel
import CutawayScene
import Foundation
import XCTest

/// C-PREF-01: the settings are kept in the user defaults, read back, restored and read
/// forgivingly.
@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults()

    override func setUp() async throws {
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func settings() -> AppSettings {
        AppSettings(defaults: defaults)
    }

    private static let keys = [
        AppSettings.Key.newInspectionMode, AppSettings.Key.layerSpacing,
        AppSettings.Key.showsHiddenLayers, AppSettings.Key.showsBorders,
    ]

    func test_C_PREF_01_eachChangeIsKeptAndReadBack() {
        let settings = settings()
        settings.newInspectionMode = .threeD
        settings.layerSpacing = 80
        settings.showsHiddenLayers = true
        settings.showsBorders = false
        for key in Self.keys {
            XCTAssertNotNil(defaults.object(forKey: key), key)
        }

        let again = self.settings()
        XCTAssertEqual(again.newInspectionMode, .threeD)
        XCTAssertEqual(again.layerSpacing, 80)
        XCTAssertTrue(again.showsHiddenLayers)
        XCTAssertFalse(again.showsBorders)
        XCTAssertFalse(again.isShowingPreviewDefaults)
    }

    func test_C_PREF_01_theSpacingIsKeptInWholePointsWithinItsRange() {
        let settings = settings()
        settings.layerSpacing = 12.6
        XCTAssertEqual(settings.layerSpacing, 13)
        settings.layerSpacing = 250
        XCTAssertEqual(settings.layerSpacing, 200)
        settings.layerSpacing = -3
        XCTAssertEqual(settings.layerSpacing, 0)
        XCTAssertEqual(self.settings().layerSpacing, 0)
    }

    func test_C_PREF_01_restoringDefaultsRemovesEveryKey() {
        let settings = settings()
        settings.newInspectionMode = .threeD
        settings.layerSpacing = 80
        settings.showsHiddenLayers = true
        settings.showsBorders = false
        settings.restorePreviewDefaults()

        XCTAssertEqual(settings.newInspectionMode, .twoD)
        XCTAssertEqual(settings.layerSpacing, 50)
        XCTAssertFalse(settings.showsHiddenLayers)
        XCTAssertTrue(settings.showsBorders)
        XCTAssertTrue(settings.isShowingPreviewDefaults)
        for key in Self.keys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(self.settings().inspectionStart, InspectionStart())
    }

    func test_C_PREF_01_valuesOfTheWrongTypeOrOutOfRangeReadAsTheDefaults() {
        let wrong: [[String: Any]] = [
            [
                AppSettings.Key.newInspectionMode: "4d", AppSettings.Key.layerSpacing: "far",
                AppSettings.Key.showsHiddenLayers: "yes", AppSettings.Key.showsBorders: [1],
            ],
            [
                AppSettings.Key.newInspectionMode: 3, AppSettings.Key.layerSpacing: -1.0,
                AppSettings.Key.showsHiddenLayers: 2.5, AppSettings.Key.showsBorders: "off",
            ],
            [AppSettings.Key.layerSpacing: 201.0],
            [AppSettings.Key.layerSpacing: Double.nan],
            [AppSettings.Key.layerSpacing: true],
        ]
        for values in wrong {
            for (key, value) in values {
                defaults.set(value, forKey: key)
            }
            let settings = settings()
            XCTAssertEqual(settings.newInspectionMode, .twoD, "\(values)")
            XCTAssertEqual(settings.layerSpacing, 50, "\(values)")
            XCTAssertFalse(settings.showsHiddenLayers, "\(values)")
            XCTAssertTrue(settings.showsBorders, "\(values)")
            // What is kept is left as it is.
            for (key, _) in values {
                XCTAssertNotNil(defaults.object(forKey: key), key)
            }
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    func test_C_PREF_01_isShowingPreviewDefaultsComparesTheValues() {
        let settings = settings()
        var published: [Bool] = []
        let watching = settings.$isShowingPreviewDefaults.dropFirst().sink { published.append($0) }
        settings.showsBorders = false
        settings.showsBorders = true
        XCTAssertTrue(settings.isShowingPreviewDefaults)
        XCTAssertEqual(published, [false, true])
        watching.cancel()
    }

    func test_C_PREF_02_theStartOfANewInspection() {
        let settings = settings()
        settings.newInspectionMode = .threeD
        settings.layerSpacing = 80
        settings.showsHiddenLayers = true
        settings.showsBorders = false

        let start = settings.inspectionStart
        XCTAssertEqual(start.previewMode, .threeD)
        XCTAssertEqual(start.layerSpacing, 80)
        XCTAssertTrue(start.showsHiddenLayers)
        XCTAssertFalse(start.showsBorders)
        XCTAssertEqual(start.cameras.twoD, Camera.flat)
        var threeD = Camera.standard3D
        threeD.layerSpacing = 80
        XCTAssertEqual(start.cameras.threeD, threeD)
    }
}
