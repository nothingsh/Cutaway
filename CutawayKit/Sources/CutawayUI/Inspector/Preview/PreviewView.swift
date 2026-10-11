import AppKit
import CutawayRender
import CutawayScene
import Metal
import MetalKit

/// The preview's canvas. It draws the draw list it is given with Metal, and only when that
/// list or its own size changes (C-REND-04): the view is paused and draws when it needs
/// display. Pointer events are turned into layers with the list that is on screen.
public final class PreviewView: MTKView {
    /// The accessibility identifier.
    public static let identifier = "preview"

    /// Frames committed so far. Public for the app tests, as are `isInTransition`,
    /// `isDrawingPending` and what `PreviewView+Inspection.swift` holds.
    public private(set) var frameCount = 0
    /// Whether the list shown is a frame of a transition to another mode or another expansion
    /// (C-PREV-11, C-PREV-12).
    public internal(set) var isInTransition = false
    /// Whether the list last shown is still to be drawn: its frame comes with a later display
    /// pass. A test that counts frames from a change waits for this first, or it counts the
    /// frame of the change as one drawn after it.
    public var isDrawingPending: Bool { drawnShowing != showings }
    /// Lists shown so far, and how many of them had been shown when a frame was last drawn.
    private var showings = 0
    private var drawnShowing = 0
    /// What is on screen, in points from the top left.
    private(set) var drawList = DrawList.empty
    /// Holds the measured distances' values over the drawing (C-PREV-10); Metal draws no
    /// text. The pointer goes through it to the preview.
    private let distanceOverlay = PassThroughView(frame: .zero).configure {
        $0.autoresizingMask = [.width, .height]
    }

    /// The values shown, in the order of the measurement's distances.
    var distanceLabels: [DistanceLabelView] {
        distanceOverlay.subviews.compactMap { $0 as? DistanceLabelView }
    }

    let textures: TextureCache
    /// Draws the list; `PreviewView+Inspection.swift` draws it offscreen too.
    let renderer: Renderer
    /// How the list is drawn; a change draws it again (C-PREV-09).
    var style: RenderStyle {
        didSet {
            clearColor = style.clearColor
            needsDisplay = true
            for label in distanceLabels { label.color = measureColor }
        }
    }

    /// Whether the colours follow the appearance: `RenderStyle.preview` for
    /// the light or dark one, keeping the borders switch.
    private let followsAppearance: Bool
    private var trackingArea: NSTrackingArea?
    /// Where the pointer last was over the view, as the draw list counts; nil when it is not
    /// over the view.
    private var pointer: ScenePoint?
    /// The layer last reported under the pointer.
    private var reportedHover: UInt64?
    /// Whether ⌥ is held, as the last event that told said.
    private var optionHeld = false
    /// Whether the layer under the pointer is measured against the selected one: ⌥ held over
    /// the view with no button down, since a drag with ⌥ pans (C-PREV-10, C-PREV-06).
    private(set) var isMeasuring = false
    /// Tells the view about ⌥ when the keyboard focus is elsewhere in the window.
    private let flagsMonitor = EventMonitor()

    /// Where the button went down, as the draw list counts; nil while it is up.
    private var pressedAt: ScenePoint?
    /// Where the drag was last reported; nil until the pointer moved far enough to drag.
    private var draggedTo: ScenePoint?
    /// How far the pointer may move with the button down and still click (C-PREV-04).
    static let dragThreshold = 3.0

    var onHover: ((UInt64?) -> Void)?
    var onClick: ((UInt64?) -> Void)?
    /// The second click of a double click, after its `onClick`, on the layer under it.
    var onDoubleClick: ((UInt64) -> Void)?
    var onResize: ((CGSize) -> Void)?
    /// The context menu for the layer under a right click or a ⌃ click, or for none; nil for
    /// no menu (C-PREV-15).
    var onContextMenu: ((UInt64?) -> NSMenu?)?
    /// Measuring starts or stops.
    var onMeasuringChange: ((Bool) -> Void)?
    /// A drag of (dx, dy) points since the last one, y down; `pans` when ⌥ is held.
    var onDrag: ((_ dx: Double, _ dy: Double, _ pans: Bool) -> Void)?
    /// A scroll of (dx, dy) points, y down: the content follows the fingers.
    var onPan: ((_ dx: Double, _ dy: Double) -> Void)?
    /// A zoom by `factor` about a point, as the draw list counts.
    var onZoom: ((_ factor: Double, _ point: ScenePoint) -> Void)?
    /// Points per line, for a wheel that scrolls by lines.
    static let pointsPerLine = 10.0

    init(renderer: Renderer, style: RenderStyle = .standard, followsAppearance: Bool = false) {
        self.renderer = renderer
        self.style = style
        self.followsAppearance = followsAppearance
        textures = TextureCache(device: renderer.device)
        super.init(frame: .zero, device: renderer.device)
        colorPixelFormat = Renderer.pixelFormat
        // The images are sRGB (P-IMG-01); without this a wide-gamut display shows them more
        // saturated than they are.
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        depthStencilPixelFormat = .invalid
        sampleCount = Renderer.sampleCount
        clearColor = style.clearColor
        isPaused = true
        enableSetNeedsDisplay = true
        setAccessibilityIdentifier(Self.identifier)
        distanceOverlay.frame = bounds
        addSubview(distanceOverlay)
        followAppearance()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows a list and the values of the distances it measures. Nothing is drawn again when
    /// it is the list already shown. A new projection can put another layer under a pointer
    /// that has not moved: that one is hovered.
    func show(_ list: DrawList) {
        guard list != drawList else { return }
        if list.measurement?.labels != drawList.measurement?.labels {
            placeDistanceLabels(list.measurement?.labels ?? [])
        }
        drawList = list
        showings += 1
        needsDisplay = true
        if let pointer { reportHover(drawList.layer(at: pointer)) }
    }

    override public func draw(_ dirtyRect: NSRect) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable else {
            return
        }
        do {
            try renderer.commit(
                drawList, textures: textures, style: style, to: pass, presenting: drawable)
            frameCount += 1
            drawnShowing = showings
        } catch {
            // Nothing to show for this frame; the next change asks again.
        }
    }

    override public func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        // The point remembered is no longer where the pointer is over the new projection; the
        // next move hits again.
        if resized, pointer != nil {
            pointer = nil
            reportHover(nil)
            updateMeasuring()
        }
        onResize?(newSize)
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        followAppearance()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        followAppearance()
    }

    /// Takes the colours of the current appearance; a change draws again.
    private func followAppearance() {
        guard followsAppearance else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let wanted = RenderStyle.preview(dark: dark, drawsBorders: style.drawsBorders)
        if wanted != style { style = wanted }
    }

    /// The measuring colour, which the distances' values are written on.
    private var measureColor: NSColor { style.measure.nsColor }

    /// One label for each distance: below the middle of a line across, right of the middle
    /// of a line down, 4 points away.
    private func placeDistanceLabels(_ distances: [DrawDistanceLabel]) {
        let shown = distanceLabels
        for label in shown.dropFirst(distances.count) { label.removeFromSuperview() }
        for (index, distance) in distances.enumerated() {
            let label: DistanceLabelView
            if index < shown.count {
                label = shown[index]
            } else {
                label = DistanceLabelView()
                distanceOverlay.addSubview(label)
            }
            label.color = measureColor
            label.text = PreviewPaneText.distanceText(distance.value)
            let size = label.frame.size, middle = distance.middle
            switch distance.axis {
            case .horizontal:
                label.setFrameOrigin(NSPoint(x: middle.x - size.width / 2, y: middle.y + 4))
            case .vertical:
                label.setFrameOrigin(NSPoint(x: middle.x + 4, y: middle.y - size.height / 2))
            }
        }
    }

    /// On a screen of another pixel density the drawable changes but the draw list, which
    /// is in points, does not: draw again for the new pixels.
    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    // MARK: - The pointer

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Where an event is, as the draw list counts: points from the top left.
    private func listPoint(_ event: NSEvent) -> ScenePoint {
        listPoint(convert(event.locationInWindow, from: nil))
    }

    /// A point of this view as the draw list counts it.
    private func listPoint(_ point: NSPoint) -> ScenePoint {
        ScenePoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }

    override public func mouseMoved(with event: NSEvent) {
        let point = listPoint(event)
        pointer = point
        reportHover(drawList.layer(at: point))
        modifiersChanged(event.modifierFlags)
    }

    override public func flagsChanged(with event: NSEvent) {
        modifiersChanged(event.modifierFlags)
        super.flagsChanged(with: event)
    }

    /// The modifier keys now held: ⌥ measures (C-PREV-10).
    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        optionHeld = flags.contains(.option)
        updateMeasuring()
    }

    /// Measures while ⌥ is held over the view and no button is down; tells when that changes.
    /// A drag can end with the pointer outside the view, where nothing is measured.
    private func updateMeasuring() {
        let over = pointer.map {
            (0...bounds.width).contains($0.x) && (0...bounds.height).contains($0.y)
        } ?? false
        let measuring = optionHeld && over && pressedAt == nil
        guard measuring != isMeasuring else { return }
        isMeasuring = measuring
        onMeasuringChange?(measuring)
    }

    override public func mouseExited(with event: NSEvent) {
        forgetPointer()
    }

    /// The first click in a window that is not key selects a layer too, as it does in the
    /// list.
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// A hover does not outlive the view's place in a window, nor the window being key.
    /// While in a window, the view hears about ⌥ wherever the keyboard focus is: the key
    /// goes to the first responder, which is seldom the preview.
    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        if let old = window {
            center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: old)
        }
        flagsMonitor.token = nil
        if let newWindow {
            center.addObserver(
                self, selector: #selector(windowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification, object: newWindow)
            flagsMonitor.token = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
                [weak self] event in
                MainActor.assumeIsolated {
                    if event.window === self?.window { self?.modifiersChanged(event.modifierFlags) }
                }
                return event
            }
        }
        forgetPointer()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        forgetPointer()
    }

    /// Tells about the layer under the pointer, unless it is the one told about last.
    private func reportHover(_ id: UInt64?) {
        guard id != reportedHover else { return }
        reportedHover = id
        onHover?(id)
    }

    /// Forgets the pointer, and a press under way: a drag cut short is not a click.
    private func forgetPointer() {
        pointer = nil
        pressedAt = nil
        draggedTo = nil
        reportHover(nil)
        updateMeasuring()
    }

    override public func mouseDown(with event: NSEvent) {
        // A ⌃ click is a right click: it opens the menu and starts no press.
        if event.modifierFlags.contains(.control) {
            if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
            return
        }
        pressedAt = listPoint(event)
        draggedTo = nil
        updateMeasuring()
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let pressedAt else { return }
        let point = listPoint(event)
        // The hover follows the pointer through a drag: a projection the drag causes is hit
        // tested where the pointer is now.
        pointer = point
        defer { reportHover(drawList.layer(at: point)) }
        if draggedTo == nil {
            guard hypot(point.x - pressedAt.x, point.y - pressedAt.y) > Self.dragThreshold
            else { return }
        }
        let from = draggedTo ?? pressedAt
        draggedTo = point
        onDrag?(point.x - from.x, point.y - from.y, event.modifierFlags.contains(.option))
    }

    override public func scrollWheel(with event: NSEvent) {
        let scale = event.hasPreciseScrollingDeltas ? 1 : Self.pointsPerLine
        scroll(
            dx: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale,
            command: event.modifierFlags.contains(.command),
            at: convert(event.locationInWindow, from: nil))
    }

    /// With ⌘ a zoom about the pointer, otherwise a pan (C-PREV-05, C-PREV-06).
    func scroll(dx: Double, dy: Double, command: Bool, at point: NSPoint) {
        if command {
            onZoom?(pow(1.01, dy), listPoint(point))
        } else {
            onPan?(dx, dy)
        }
    }

    override public func magnify(with event: NSEvent) {
        magnify(by: event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    /// A pinch: a zoom about the pointer (C-PREV-05).
    func magnify(by magnification: Double, at point: NSPoint) {
        onZoom?(1 + magnification, listPoint(point))
    }

    override public func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?(drawList.layer(at: listPoint(event)))
    }

    /// A click selects where the button comes up; a drag selects nothing (C-PREV-04). The
    /// second click of a double click goes on to expand or collapse that layer (C-PREV-13).
    override public func mouseUp(with event: NSEvent) {
        defer {
            pressedAt = nil
            draggedTo = nil
            modifiersChanged(event.modifierFlags)
        }
        guard pressedAt != nil, draggedTo == nil else { return }
        let layer = drawList.layer(at: listPoint(event))
        onClick?(layer)
        if event.clickCount == 2, let layer { onDoubleClick?(layer) }
    }
}

/// An event monitor that is removed when replaced or when its owner goes away.
private final class EventMonitor {
    var token: Any? {
        willSet { if let token { NSEvent.removeMonitor(token) } }
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}

/// A flipped view that holds what is drawn over the preview and lets the pointer through.
private final class PassThroughView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
