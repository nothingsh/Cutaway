import CutawayScene

extension InspectionStore {
    // MARK: - The camera and what the preview shows

    public func setPreviewMode(_ mode: PreviewMode) {
        if mode != previewMode { previewMode = mode }
    }

    /// The camera of the mode shown. For the app tests.
    public var camera: Camera { cameras[previewMode] }

    /// Turns the 3D view by a drag (C-PREV-04). The 2D view does not turn.
    public func rotate(byDragOf dx: Double, _ dy: Double) {
        guard previewMode == .threeD else { return }
        updateCamera { $0.rotated(byDragOf: dx, dy) }
    }

    /// Moves the view by (dx, dy) viewport points (C-PREV-06).
    public func pan(by dx: Double, _ dy: Double) {
        updateCamera { $0.panned(by: dx, dy) }
    }

    /// Zooms the view, keeping what is under `point` where it is (C-PREV-05).
    public func zoom(by factor: Double, about point: ScenePoint, in viewport: Viewport) {
        updateCamera { $0.zoomed(by: factor, about: point, in: viewport) }
    }

    /// Within `Camera.spacingRange`; the 2D view has no spacing (C-PREV-07).
    public func setLayerSpacing(_ spacing: Double) {
        guard previewMode == .threeD else { return }
        let range = Camera.spacingRange
        let limited = min(max(spacing, range.lowerBound), range.upperBound)
        updateCamera { camera in
            var camera = camera
            camera.layerSpacing = limited
            return camera
        }
    }

    /// Puts the camera of the mode shown back as the inspection started (C-PREV-07,
    /// C-PREF-02).
    public func resetCamera() {
        let camera = start.cameras[previewMode]
        updateCamera { _ in camera }
    }

    /// What this inspection shows that another connection to the app can show too. A focus
    /// does not carry over, and with it goes the zoom and pan fitted to it.
    var settings: InspectionSettings {
        InspectionSettings(
            previewMode: previewMode,
            cameras: focusedLayerID == nil ? cameras : PreviewCameras.fitted(cameras),
            showsHiddenLayers: showsHiddenLayers, showsBorders: showsBorders,
            searchText: searchText, start: start)
    }

    /// Takes over what an inspection of the same app over an earlier connection showed
    /// (C-WIN-04).
    func adopt(_ settings: InspectionSettings) {
        setPreviewMode(settings.previewMode)
        if settings.cameras != cameras { cameras = settings.cameras }
        setShowsHiddenLayers(settings.showsHiddenLayers)
        setShowsBorders(settings.showsBorders)
        setSearchText(settings.searchText)
    }

    /// Publishes only a camera that changed.
    private func updateCamera(_ change: (Camera) -> Camera) {
        let new = change(cameras[previewMode])
        if new != cameras[previewMode] { cameras[previewMode] = new }
    }

    /// Shows or hides the layers that cannot be seen (C-PREV-08). Their screenshots are asked
    /// for while they are shown; turning them off keeps the images already taken.
    public func setShowsHiddenLayers(_ shows: Bool) {
        guard shows != showsHiddenLayers else { return }
        showsHiddenLayers = shows
        rebuildLayout()
        fetchNext()
    }

    /// Outlines the layers or not (C-PREV-09). Only the drawing changes.
    public func setShowsBorders(_ shows: Bool) {
        if shows != showsBorders { showsBorders = shows }
    }
}
