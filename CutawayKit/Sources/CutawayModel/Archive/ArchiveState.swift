import CutawayScene
import Foundation

/// What the inspection showed when an archive was saved, kept in the archive's interface
/// state section and taken over when it is opened (C-ARCH-03, Resources/ARCHIVE.md).
///
/// Reading is forgiving one key at a time: a key that is missing, of the wrong type or out of
/// range takes its default and leaves the others alone. The scene's types stay out of the
/// format: cameras are written field by field.
public struct ArchiveState: Equatable, Sendable {
    /// The expanded layers; nil when the archive does not say, and the tree opens as a new
    /// inspection's does (C-HIER-09).
    public var expanded: Set<UInt64>?
    public var selected: UInt64?
    public var focused: UInt64?
    public var previewMode: PreviewMode = .twoD
    public var cameras = PreviewCameras()
    public var showsHiddenLayers = false
    public var borders = BorderOptions()
    /// Whether every end of the selected layer's constraints is marked (C-PREV-18).
    public var showsConstraintEnds = false

    /// The state of an inspection that was just opened.
    public init() {}

    /// The state of an inspection that was just opened as `start` says (C-PREF-02).
    public init(start: InspectionStart) {
        previewMode = start.previewMode
        cameras = start.cameras
        showsHiddenLayers = start.showsHiddenLayers
        borders = start.borders
        showsConstraintEnds = start.showsConstraintEnds
    }

    public init(
        expanded: Set<UInt64>?, selected: UInt64?, focused: UInt64?, previewMode: PreviewMode,
        cameras: PreviewCameras, showsHiddenLayers: Bool, borders: BorderOptions,
        showsConstraintEnds: Bool = false
    ) {
        self.expanded = expanded
        self.selected = selected
        self.focused = focused
        self.previewMode = previewMode
        self.cameras = cameras
        self.showsHiddenLayers = showsHiddenLayers
        self.borders = borders
        self.showsConstraintEnds = showsConstraintEnds
    }

    /// Reads the section. What it lacks is taken from `start`, the settings when the archive
    /// is opened (C-PREF-02); anything that is not a JSON object gives `start` whole.
    public init(decoding data: Data, start: InspectionStart = InspectionStart()) {
        let decoder = JSONDecoder()
        decoder.userInfo[StateJSON.startKey] = start
        self = (try? decoder.decode(StateJSON.self, from: data))?.state ?? Self(start: start)
    }

    /// The section's bytes: UTF-8 JSON with sorted keys.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Integers, finite doubles, booleans and strings always encode.
        return (try? encoder.encode(StateJSON(self))) ?? Data("{}".utf8)
    }
}

private struct StateJSON: Codable {
    // The key is a constant: its initializer can fail only for an empty string.
    // swiftlint:disable:next force_unwrapping
    static let startKey = CodingUserInfoKey(rawValue: "start")!

    var state: ArchiveState

    init(_ state: ArchiveState) {
        self.state = state
    }

    enum Key: String, CodingKey {
        case expanded, selected, focused, mode, cameras, showsHiddenLayers, showsBorders
        case borderStyle, onlyAppClasses, showsConstraintEnds
    }

    enum CameraKey: String, CodingKey {
        case twoD, threeD
    }

    enum FieldKey: String, CodingKey {
        case yaw, pitch, zoom, panX, panY, layerSpacing
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let start = decoder.userInfo[Self.startKey] as? InspectionStart ?? InspectionStart()
        var state = ArchiveState(start: start)
        if let expanded = try? container.decode([UInt64].self, forKey: .expanded) {
            state.expanded = Set(expanded)
        }
        state.selected = try? container.decode(UInt64.self, forKey: .selected)
        state.focused = try? container.decode(UInt64.self, forKey: .focused)
        switch try? container.decode(String.self, forKey: .mode) {
        case "2d": state.previewMode = .twoD
        case "3d": state.previewMode = .threeD
        default: break
        }
        if let cameras = try? container.nestedContainer(keyedBy: CameraKey.self, forKey: .cameras) {
            state.cameras.twoD = Self.camera(in: cameras, at: .twoD, default: start.cameras.twoD)
            state.cameras.threeD = Self.camera(
                in: cameras, at: .threeD, default: start.cameras.threeD)
        }
        if let shows = try? container.decode(Bool.self, forKey: .showsHiddenLayers) {
            state.showsHiddenLayers = shows
        }
        // The style, or for an archive of an earlier version the switch it had (C-PREV-17).
        if let raw = try? container.decode(String.self, forKey: .borderStyle),
           let style = BorderStyle(rawValue: raw)
        {
            state.borders.style = style
        } else if let shows = try? container.decode(Bool.self, forKey: .showsBorders) {
            // Such an archive has no "only the app's classes": the settings' stays (C-PREF-02).
            state.borders = BorderOptions(showsBorders: shows)
            state.borders.onlyAppClasses = start.borders.onlyAppClasses
        }
        if let only = try? container.decode(Bool.self, forKey: .onlyAppClasses) {
            state.borders.onlyAppClasses = only
        }
        if let shows = try? container.decode(Bool.self, forKey: .showsConstraintEnds) {
            state.showsConstraintEnds = shows
        }
        self.state = state
    }

    /// One mode's camera, each field falling back to that mode's default. The projection
    /// follows the mode and is not stored.
    private static func camera(
        in cameras: KeyedDecodingContainer<CameraKey>, at key: CameraKey, default start: Camera
    ) -> Camera {
        guard let fields = try? cameras.nestedContainer(keyedBy: FieldKey.self, forKey: key)
        else { return start }
        func value(_ field: FieldKey, _ fallback: Double) -> Double {
            guard let number = try? fields.decode(Double.self, forKey: field), number.isFinite
            else { return fallback }
            return number
        }
        var camera = start
        camera.yaw = value(.yaw, start.yaw)
        camera.pitch = value(.pitch, start.pitch)
        camera.zoom = value(.zoom, start.zoom)
        camera.pan = ScenePoint(x: value(.panX, start.pan.x), y: value(.panY, start.pan.y))
        camera.layerSpacing = value(.layerSpacing, start.layerSpacing)
        return camera
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encodeIfPresent(state.expanded?.sorted(), forKey: .expanded)
        try container.encode(state.selected, forKey: .selected)
        try container.encode(state.focused, forKey: .focused)
        try container.encode(state.previewMode == .twoD ? "2d" : "3d", forKey: .mode)
        var cameras = container.nestedContainer(keyedBy: CameraKey.self, forKey: .cameras)
        try Self.encode(state.cameras.twoD, in: &cameras, at: .twoD)
        try Self.encode(state.cameras.threeD, in: &cameras, at: .threeD)
        try container.encode(state.showsHiddenLayers, forKey: .showsHiddenLayers)
        try container.encode(state.borders.style.rawValue, forKey: .borderStyle)
        try container.encode(state.borders.onlyAppClasses, forKey: .onlyAppClasses)
        try container.encode(state.showsConstraintEnds, forKey: .showsConstraintEnds)
        // For earlier versions, which know only the switch.
        try container.encode(state.borders.showsBorders, forKey: .showsBorders)
    }

    private static func encode(
        _ camera: Camera, in cameras: inout KeyedEncodingContainer<CameraKey>, at key: CameraKey
    ) throws {
        var fields = cameras.nestedContainer(keyedBy: FieldKey.self, forKey: key)
        try fields.encode(camera.yaw, forKey: .yaw)
        try fields.encode(camera.pitch, forKey: .pitch)
        try fields.encode(camera.zoom, forKey: .zoom)
        try fields.encode(camera.pan.x, forKey: .panX)
        try fields.encode(camera.pan.y, forKey: .panY)
        try fields.encode(camera.layerSpacing, forKey: .layerSpacing)
    }
}
