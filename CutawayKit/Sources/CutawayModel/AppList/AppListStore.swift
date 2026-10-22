import Combine
import CutawayTransport
import CutawayWire
import Foundation

/// The apps that can be listed, and which of them is being inspected.
@MainActor
public final class AppListStore: ObservableObject {
    /// Simulators first, by port; then devices, by serial number and port.
    @Published public private(set) var entries: [AppEntry] = []
    /// The app whose inspection is open, if any.
    @Published public private(set) var inspectedApp: AppLocation?
    /// Whether the open inspection was opened by the user's choice, rather than found again
    /// on its own (C-WIN-04). In place before `inspectedApp` publishes.
    public private(set) var inspectionOpenedByChoice = false
    /// The app whose inspection was lost, while its window waits for it to come back
    /// (C-WIN-04). Nil when nothing waits.
    @Published public private(set) var awaitingReconnection: AppIdentity?
    /// What the lost inspection showed, for the one that takes its place.
    private var settingsToRestore: InspectionSettings?

    private var sessions: [AppLocation: Session] = [:]
    /// The request for each app's icon over its current connection; an inspection's first
    /// hierarchy waits for it, so that the requests go out in one order.
    private var iconLoads: [AppLocation: Task<Void, Never>] = [:]
    /// Decompresses an app's icon. Only ever called away from the main thread (C-DET-09):
    /// an icon may be as large as a screenshot. Tests replace it.
    var decodeIcon: @Sendable (EncodedImage) throws -> Bitmap = { try $0.decoded() }
    /// The inspection state of each app that has been inspected over its current connection.
    private var inspections: [AppLocation: InspectionStore] = [:]
    private var consumer: Task<Void, Never>?
    /// What every inspection puts in its requests as `max_texture_dimension` (C-REND-05);
    /// archives opened offline ask theirs for the same.
    public let maxTextureDimension: UInt32
    /// How a new inspection starts: the settings' (C-PREF-02). An inspection that takes a
    /// lost one's place starts as that one did instead.
    public var inspectionStart: @MainActor () -> InspectionStart = { InspectionStart() }
    /// The interface's words for what an inspection must name (C-LOC-01). The interface sets
    /// it once, with `inspectionStart`.
    public var inspectionText = InspectionText()

    public init(maxTextureDimension: UInt32 = 0) {
        self.maxTextureDimension = maxTextureDimension
    }

    deinit {
        consumer?.cancel()
    }

    /// Applies every event of `events` as it arrives. Replaces an earlier stream.
    public func follow(_ events: AsyncStream<DiscoveryEvent>) {
        consumer?.cancel()
        consumer = Task { [weak self] in
            for await event in events {
                self?.apply(event)
            }
        }
    }

    public func apply(_ event: DiscoveryEvent) {
        switch event {
        case .found(let location, let info, let session):
            sessions[location] = session
            // A new connection: layer IDs of the old one mean nothing on it (P-HIER-03). An
            // inspection of the old one has lost its app (C-WIN-03).
            inspections[location]?.connectionLost(waiting: awaitingReconnection != nil)
            inspections[location] = nil
            if inspectedApp == location { inspectedApp = nil }
            upsert(AppEntry(id: location, info: info, status: .ready(.active), icon: nil))
            iconLoads[location] = loadIcon(from: session, at: location)
            // The app whose window waits for it is back (C-WIN-04).
            if let awaited = awaitingReconnection, AppIdentity(info) == awaited {
                inspect(location)
            }

        case .stateChanged(let location, let state):
            guard var entry = entries.first(where: { $0.id == location }), entry.isInspectable
            else { return }
            entry.status = .ready(state)
            upsert(entry)
            inspections[location]?.appStateDidChange(state)

        case .incompatible(let location, let info, let local, let remote):
            // Before the inspection goes: its window waits for the app to come back.
            if inspectedApp == location { awaitReconnection(of: location) }
            sessions[location] = nil
            iconLoads[location] = nil
            // A view may still hold the inspection; closed, it asks for nothing more. An
            // archive it was saving failed for the connection, not for the closing.
            inspections[location]?.connectionLost(waiting: awaitingReconnection != nil)
            inspections[location]?.leave()
            inspections[location] = nil
            if inspectedApp == location { inspectedApp = nil }
            upsert(AppEntry(
                id: location, info: info, status: .incompatible(local: local, remote: remote),
                icon: nil))

        case .lost(let location):
            if inspectedApp == location { awaitReconnection(of: location) }
            sessions[location] = nil
            iconLoads[location] = nil
            // A view may still hold the inspection; closed, it asks for nothing more. An
            // archive it was saving failed for the connection, not for the closing.
            inspections[location]?.connectionLost(waiting: awaitingReconnection != nil)
            inspections[location]?.leave()
            inspections[location] = nil
            if inspectedApp == location { inspectedApp = nil }
            if let index = entries.firstIndex(where: { $0.id == location }) {
                entries.remove(at: index)
            }
        }
    }

    /// Opens the inspection of an app and asks the app for its layers. Does nothing for an
    /// app that is not listed or that is not compatible. `byChoice` when the user chose the
    /// app, rather than it being found again (C-WIN-04).
    public func inspect(_ location: AppLocation, byChoice: Bool = false) {
        guard entries.contains(where: { $0.id == location && $0.isInspectable }),
              let session = sessions[location]
        else { return }
        // The state of an earlier visit over this connection is kept and merged with what
        // arrives now (C-HIER-02). It must exist before the inspected app is published: the
        // window asks for it then.
        if let current = inspectedApp, current != location { inspections[current]?.leave() }
        // The app a window waits for, chosen by hand or found again: what its inspection
        // showed carries over. Any other app ends the wait.
        let entry = entries.first { $0.id == location }
        let returning = awaitingReconnection != nil
            && entry?.info.flatMap(AppIdentity.init) == awaitingReconnection
        let restore = returning ? settingsToRestore : nil
        stopAwaitingReconnection()
        let inspection: InspectionStore
        if let existing = inspections[location] {
            inspection = existing
        } else {
            inspection = InspectionStore(
                session: session, maxTextureDimension: maxTextureDimension,
                start: restore?.start ?? inspectionStart(), text: inspectionText)
            if let restore { inspection.adopt(restore) }
        }
        inspections[location] = inspection
        inspection.enter(after: iconLoads[location])
        inspectionOpenedByChoice = byChoice
        inspectedApp = location
    }

    /// The inspection state of an app, once it has been inspected over its current
    /// connection. It uses the same connection as the list (C-CONN-09).
    public func inspection(at location: AppLocation) -> InspectionStore? {
        inspections[location]
    }

    /// Closes the inspection, and stops waiting for a lost app to come back: its window is
    /// closed (C-WIN-04).
    public func leaveInspection() {
        stopAwaitingReconnection()
        if let location = inspectedApp { inspections[location]?.leave() }
        inspectedApp = nil
    }

    /// Remembers the inspected app and what its inspection showed, for when it comes back
    /// (C-WIN-04). An app without a bundle identifier cannot be recognised and is not waited
    /// for.
    private func awaitReconnection(of location: AppLocation) {
        guard let info = entries.first(where: { $0.id == location })?.info,
              let identity = AppIdentity(info)
        else { return }
        settingsToRestore = inspections[location]?.settings
        awaitingReconnection = identity
    }

    private func stopAwaitingReconnection() {
        settingsToRestore = nil
        if awaitingReconnection != nil { awaitingReconnection = nil }
    }

    /// The connection to a listed app. The list and the inspection share it (C-CONN-09).
    public func session(at location: AppLocation) -> Session? {
        sessions[location]
    }

    private func upsert(_ entry: AppEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            // Assigning an equal value would still publish, and the list would flicker for
            // nothing (C-LIST-02).
            guard entries[index] != entry else { return }
            entries[index] = entry
        } else {
            let index = entries.firstIndex { $0.id > entry.id } ?? entries.endIndex
            entries.insert(entry, at: index)
        }
    }

    /// The icon's request, which an inspection's first hierarchy waits for. For tests.
    func iconLoad(at location: AppLocation) -> Task<Void, Never>? {
        iconLoads[location]
    }

    @discardableResult
    private func loadIcon(from session: Session, at location: AppLocation) -> Task<Void, Never> {
        Task { [weak self, decodeIcon] in
            // Decompressed away from the main thread; only the result comes back to it.
            guard let image = try? await session.appIcon(),
                  let icon = await ImageDecompression.decompress([0: image], using: decodeIcon)[0]
            else { return }
            self?.setIcon(icon, at: location, from: session)
        }
    }

    private func setIcon(_ icon: Bitmap, at location: AppLocation, from session: Session) {
        // The app may be gone by now, and another one may have taken its place.
        guard sessions[location] === session,
              var entry = entries.first(where: { $0.id == location })
        else { return }
        entry.icon = icon
        upsert(entry)
    }
}
