import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// The app's icon is decompressed away from the main thread, as screenshots are (C-DET-09):
/// the protocol lets it be as large as one.
final class AppListIconTests: XCTestCase {
    func test_C_DET_09_theIconIsDecompressedAwayFromTheMainThread() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "app-icon"))
        let discovery = Discovery(configuration: DiscoveryConfiguration(
            client: ClientInfo(name: "Cutaway", version: "0.1.0"), simulatorPorts: [server.port],
            devicePorts: [], usbmuxdSocketPath: nil, scanInterval: .milliseconds(50)))
        let tracker = PixelTracker()
        let model = await AppListStore()
        await MainActor.run { model.decodeIcon = tracker.decode }
        await model.follow(discovery.events)
        await discovery.start()

        let loaded = await Wait.until { await model.entries.first?.icon != nil }
        XCTAssertTrue(loaded)
        XCTAssertEqual(tracker.callCount, 1)
        XCTAssertEqual(tracker.mainThreadCallCount, 0, "the icon was decompressed on the main thread")
        let icon = await model.entries.first?.icon
        XCTAssertEqual(icon?.pixelWidth, 2)

        await discovery.stop()
        await server.stop()
    }
}
