import CutawayModel
import CutawayScene
import Foundation
import XCTest

/// C-ARCH-03: the interface state an archive keeps (Resources/ARCHIVE.md, "Interface state").
final class ArchiveStateTests: XCTestCase {
    private func sample() -> ArchiveState {
        var cameras = PreviewCameras()
        cameras.twoD.zoom = 2
        cameras.twoD.pan = ScenePoint(x: -12.5, y: 30)
        cameras.threeD.yaw = 0.4
        cameras.threeD.pitch = -0.2
        cameras.threeD.zoom = 1.4
        cameras.threeD.layerSpacing = 80
        return ArchiveState(
            expanded: [1, 2, UInt64.max], selected: 3, focused: 2, previewMode: .threeD,
            cameras: cameras, showsHiddenLayers: true, showsBorders: false)
    }

    private func decoded(_ json: String) -> ArchiveState {
        ArchiveState(decoding: Data(json.utf8))
    }

    func test_C_ARCH_03_theStateRoundTrips() {
        let state = sample()
        XCTAssertEqual(ArchiveState(decoding: state.encoded()), state)
        XCTAssertEqual(ArchiveState(decoding: ArchiveState().encoded()), ArchiveState())
    }

    func test_C_ARCH_03_theDefaultsAreAFreshInspections() {
        let state = ArchiveState()
        XCTAssertEqual(state.expanded, [])
        XCTAssertNil(state.selected)
        XCTAssertNil(state.focused)
        XCTAssertEqual(state.previewMode, .twoD)
        XCTAssertEqual(state.cameras, PreviewCameras())
        XCTAssertFalse(state.showsHiddenLayers)
        XCTAssertTrue(state.showsBorders)
    }

    func test_C_ARCH_03_missingOrWrongKeysFallBackOneByOne() {
        let state = decoded("""
        {"expanded": "all", "selected": 3, "focused": -1, "mode": "4d",
         "cameras": {"twoD": {"zoom": "big", "panX": 5}, "threeD": 7},
         "showsHiddenLayers": 1, "showsBorders": false}
        """)
        var expected = ArchiveState()
        expected.selected = 3
        expected.cameras.twoD.pan = ScenePoint(x: 5, y: 0)
        expected.showsBorders = false
        XCTAssertEqual(state, expected)

        let partial = decoded(#"{"mode": "3d"}"#)
        var mode = ArchiveState()
        mode.previewMode = .threeD
        XCTAssertEqual(partial, mode)
    }

    func test_C_ARCH_03_somethingElseThanAnObjectGivesTheDefaults() {
        XCTAssertEqual(ArchiveState(decoding: Data()), ArchiveState())
        XCTAssertEqual(decoded("[1, 2]"), ArchiveState())
        XCTAssertEqual(decoded("not json"), ArchiveState())
        XCTAssertEqual(decoded("null"), ArchiveState())
    }

    func test_C_ARCH_03_unknownKeysAreIgnored() {
        let state = decoded(#"{"selected": 4, "searchText": "label", "future": {"a": 1}}"#)
        var expected = ArchiveState()
        expected.selected = 4
        XCTAssertEqual(state, expected)
    }

    func test_C_ARCH_03_theEncodingIsTheDocumentedJSON() throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: sample().encoded()) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["expanded", "selected", "focused", "mode", "cameras", "showsHiddenLayers",
             "showsBorders"])
        XCTAssertEqual(object["mode"] as? String, "3d")
        let cameras = try XCTUnwrap(object["cameras"] as? [String: [String: Double]])
        XCTAssertEqual(
            Set(try XCTUnwrap(cameras["threeD"]).keys),
            ["yaw", "pitch", "zoom", "panX", "panY", "layerSpacing"])
        XCTAssertEqual(cameras["threeD"]?["layerSpacing"], 80)

        let empty = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ArchiveState().encoded()) as? [String: Any])
        XCTAssertTrue(empty["selected"] is NSNull)
    }

    // MARK: - What the archive lacks comes from the settings (C-PREF-02)

    private static let start = InspectionStart(
        previewMode: .threeD, layerSpacing: 80, showsHiddenLayers: true, showsBorders: false)

    func test_C_PREF_02_whatTheStateLacksComesFromTheSettings() {
        let none = ArchiveState(decoding: Data(#"{"selected": 4}"#.utf8), start: Self.start)
        var expected = ArchiveState(start: Self.start)
        expected.selected = 4
        XCTAssertEqual(none, expected)
        XCTAssertEqual(none.previewMode, .threeD)
        XCTAssertEqual(none.cameras.threeD.layerSpacing, 80)
        XCTAssertTrue(none.showsHiddenLayers)
        XCTAssertFalse(none.showsBorders)

        // A 3D camera without its spacing takes the settings' spacing, and keeps the rest.
        let noSpacing = ArchiveState(
            decoding: Data(#"{"mode": "2d", "cameras": {"threeD": {"yaw": 0.4}}}"#.utf8),
            start: Self.start)
        XCTAssertEqual(noSpacing.previewMode, .twoD)
        XCTAssertEqual(noSpacing.cameras.threeD.layerSpacing, 80)
        XCTAssertEqual(noSpacing.cameras.threeD.yaw, 0.4)
        XCTAssertEqual(noSpacing.cameras.twoD, Camera.flat)

        XCTAssertEqual(ArchiveState(decoding: Data(), start: Self.start), ArchiveState(start: Self.start))
    }

    func test_C_PREF_02_whatTheStateHasWinsOverTheSettings() {
        let state = sample()
        var other = state
        other.previewMode = .twoD
        other.cameras.threeD.layerSpacing = 20
        other.showsHiddenLayers = false
        other.showsBorders = true
        XCTAssertEqual(ArchiveState(decoding: other.encoded(), start: Self.start), other)
    }
}
