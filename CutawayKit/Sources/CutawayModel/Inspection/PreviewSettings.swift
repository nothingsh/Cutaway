import CutawayScene

/// How the preview looks at the layers (C-PREV-02).
public enum PreviewMode: Equatable, Sendable {
    case twoD
    case threeD
}

/// The camera each preview mode keeps (C-PREV-07).
public struct PreviewCameras: Equatable, Sendable {
    public var twoD = Camera.flat
    public var threeD = Camera.standard3D

    public init() {}

    public subscript(mode: PreviewMode) -> Camera {
        get { mode == .twoD ? twoD : threeD }
        set {
            if mode == .twoD { twoD = newValue } else { threeD = newValue }
        }
    }
}

extension PreviewCameras {
    /// The cameras without zoom and pan: they fit what is shown, however it is turned.
    static func fitted(_ cameras: PreviewCameras) -> PreviewCameras {
        var fitted = cameras
        for mode in [PreviewMode.twoD, .threeD] {
            fitted[mode].zoom = 1
            fitted[mode].pan = .zero
        }
        return fitted
    }

    /// A camera within the ranges the controls keep to (C-PREV-04, 05, 07). The 2D view is
    /// never turned and has no spacing.
    static func limited(_ camera: Camera, flat: Bool) -> Camera {
        func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }
        var camera = camera
        camera.projection = flat ? .orthographic : .perspective
        camera.zoom = clamp(camera.zoom, Camera.zoomRange)
        if flat {
            camera.yaw = 0
            camera.pitch = 0
            camera.layerSpacing = 0
        } else {
            camera.pitch = clamp(camera.pitch, Camera.pitchRange)
            camera.layerSpacing = clamp(camera.layerSpacing, Camera.spacingRange)
        }
        return camera
    }
}

/// How the preview outlines the layers that are not highlighted (C-PREV-17).
public enum BorderStyle: String, CaseIterable, Equatable, Sendable {
    /// No borders (C-PREV-09's off).
    case off
    /// One colour for every border.
    case plain
    /// Each layer in the colour of its kind (C-HIER-11).
    case byKind
}

/// The borders' style, whether only the app's own classes are outlined, and the style that
/// ⇧⌘B turns back on (C-PREV-17).
public struct BorderOptions: Equatable, Sendable {
    public var style: BorderStyle {
        didSet { if style != .off { lastShownStyle = style } }
    }

    /// Only layers of the app's own classes are outlined.
    public var onlyAppClasses: Bool
    /// The last style that was not off; what turning the borders on again shows.
    public private(set) var lastShownStyle: BorderStyle

    public init(style: BorderStyle = .byKind, onlyAppClasses: Bool = false) {
        self.style = style
        self.onlyAppClasses = onlyAppClasses
        lastShownStyle = style == .off ? .byKind : style
    }

    /// Off, or back to the last style that was not (⇧⌘B).
    public mutating func toggle() {
        style = style == .off ? lastShownStyle : .off
    }

    /// Whether any layer that is not highlighted is outlined.
    public var showsBorders: Bool { style != .off }

    /// The options a boolean of an earlier version stands for: on is by kind, off is off.
    public init(showsBorders: Bool) {
        self.init(style: showsBorders ? .byKind : .off)
    }
}

/// How an inspection starts (C-PREF-02): the mode, the 3D camera's spacing, whether hidden
/// layers are shown, the borders and whether every constraint end is marked. Without
/// settings, the defaults.
public struct InspectionStart: Equatable, Sendable {
    public var previewMode: PreviewMode = .twoD
    public var layerSpacing = Camera.standard3D.layerSpacing
    public var showsHiddenLayers = false
    public var borders = BorderOptions()
    /// Whether every end of the selected layer's constraints is marked (C-PREV-18).
    public var showsConstraintEnds = false

    public init() {}

    public init(
        previewMode: PreviewMode, layerSpacing: Double, showsHiddenLayers: Bool,
        borders: BorderOptions, showsConstraintEnds: Bool = false
    ) {
        self.previewMode = previewMode
        self.layerSpacing = layerSpacing
        self.showsHiddenLayers = showsHiddenLayers
        self.borders = borders
        self.showsConstraintEnds = showsConstraintEnds
    }

    /// The cameras the inspection starts with, and that Reset View goes back to (C-PREV-07).
    public var cameras: PreviewCameras {
        var cameras = PreviewCameras()
        cameras.threeD.layerSpacing = layerSpacing
        return cameras
    }
}

/// What an inspection shows that does not depend on layer IDs, and so survives a new
/// connection to the same app (C-WIN-04).
struct InspectionSettings: Equatable, Sendable {
    var previewMode: PreviewMode
    var cameras: PreviewCameras
    var showsHiddenLayers: Bool
    var borders: BorderOptions
    var showsConstraintEnds: Bool
    var searchText: String
    /// Where Reset View goes: the earlier inspection's start, not the settings' (C-PREF-02).
    var start: InspectionStart
}
