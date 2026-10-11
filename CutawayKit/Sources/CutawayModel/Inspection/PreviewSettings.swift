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

/// How an inspection starts (C-PREF-02): the mode, the 3D camera's spacing and the two
/// switches. Without settings, the values of v0.1.
public struct InspectionStart: Equatable, Sendable {
    public var previewMode: PreviewMode = .twoD
    public var layerSpacing = Camera.standard3D.layerSpacing
    public var showsHiddenLayers = false
    public var showsBorders = true

    public init() {}

    public init(
        previewMode: PreviewMode, layerSpacing: Double, showsHiddenLayers: Bool,
        showsBorders: Bool
    ) {
        self.previewMode = previewMode
        self.layerSpacing = layerSpacing
        self.showsHiddenLayers = showsHiddenLayers
        self.showsBorders = showsBorders
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
    var showsBorders: Bool
    var searchText: String
    /// Where Reset View goes: the earlier inspection's start, not the settings' (C-PREF-02).
    var start: InspectionStart
}
