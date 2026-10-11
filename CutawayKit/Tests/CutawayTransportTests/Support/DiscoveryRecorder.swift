import CutawayTransport
import CutawayWire

/// Consumes a discovery's events and keeps them for assertions.
actor DiscoveryRecorder {
    /// A discovery event without its session, so that events can be compared.
    enum Seen: Equatable {
        case found(AppLocation, AppInfo)
        case stateChanged(AppLocation, AppState)
        case incompatible(AppLocation, AppInfo?, local: Version, remote: Version)
        case lost(AppLocation)
    }

    private(set) var seen: [Seen] = []
    private var sessions: [AppLocation: Session] = [:]

    init(_ discovery: Discovery) {
        let events = discovery.events
        Task { [weak self] in
            for await event in events {
                await self?.record(event)
            }
        }
    }

    func session(at location: AppLocation) -> Session? {
        sessions[location]
    }

    private func record(_ event: DiscoveryEvent) {
        switch event {
        case .found(let location, let app, let session):
            sessions[location] = session
            seen.append(.found(location, app))
        case .stateChanged(let location, let state):
            seen.append(.stateChanged(location, state))
        case .incompatible(let location, let app, let local, let remote):
            seen.append(.incompatible(location, app, local: local, remote: remote))
        case .lost(let location):
            seen.append(.lost(location))
        }
    }
}
