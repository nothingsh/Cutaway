import AppKit
import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Metal
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// Rounds of every operation over 5,000 app-shaped layers leave nothing behind (C-SCALE-02).
/// The app list and the windows are real; discovery is not: the test tells the app list that
/// the app went and came back, as discovery would, with a new connection to the same
/// MockServer. `CUTAWAY_SOAK_ROUNDS` sets the number of rounds (`scripts/soak.sh`); without it
/// there are 10, within 100 seconds: a round takes about 3.4 seconds because each reconnection
/// fetches all 5,000 screenshots again, in serial batches of eight.
final class SoakTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(
            TestRunner.isCI,
            "ten rounds take minutes and more textures than a virtual GPU holds; "
                + TestRunner.timedOnTheDevelopersMac)
    }

    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")
    private static let info = AppInfo(
        name: "Soak", bundleID: "dev.cutaway.soak", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")
    private static let scene = SyntheticScene(
        layerCount: 5_000, shape: .app(AppShape()), imagePixels: .fixed(width: 32, height: 32),
        attributes: true, constraints: false)
    private static let defaultRounds = 10

    /// The rounds asked for in the environment, or the default.
    private static var rounds: Int {
        ProcessInfo.processInfo.environment["CUTAWAY_SOAK_ROUNDS"].flatMap(Int.init)
            ?? defaultRounds
    }

    /// An object that must be gone once it is no longer the current one.
    private final class Watched {
        let name: String
        weak var object: AnyObject?

        init(_ name: String, _ object: AnyObject) {
            self.name = name
            self.object = object
        }
    }

    /// The app list, the windows and the connection of one soak.
    @MainActor
    private final class Soak {
        let server: MockServer
        let apps: AppListStore
        let coordinator: WindowCoordinator
        let location: AppLocation
        private(set) var session: Session
        private var watched: [Watched] = []

        init(server: MockServer, session: Session) {
            self.server = server
            self.session = session
            apps = AppListStore(maxTextureDimension: 4096)
            coordinator = WindowCoordinator(store: apps, discoversDevices: false)
            location = .simulator(port: server.port)
        }

        var inspector: InspectorWindowController? { coordinator.inspector }

        func current() throws -> (InspectorWindowController, InspectionStore) {
            let inspector = try XCTUnwrap(coordinator.inspector, "no inspector window")
            return (inspector, inspector.store)
        }

        /// Notes the session, the inspection, the window and its preview of now, as of `when`.
        func watchCurrent(_ when: String) {
            watch("session of \(when)", session)
            if let inspector = coordinator.inspector {
                // Closed windows must go at once, not when AppKit's closing animation is over
                // (see `ClosingWindow.closeAtOnce`).
                ClosingWindow.closeAtOnce(inspector.window)
                if let window = inspector.window { watch("window of \(when)", window) }
                watch("inspector window controller of \(when)", inspector)
                watch("inspection of \(when)", inspector.store)
                watch(
                    "preview controller of \(when)", inspector.splitController.previewController)
            }
        }

        private func watch(_ name: String, _ object: AnyObject) {
            guard !watched.contains(where: { $0.object === object }) else { return }
            watched.append(Watched(name, object))
        }

        /// The watched objects still alive, other than the current ones.
        func leftovers() -> [String] {
            var current: [AnyObject] = [session]
            if let inspector = coordinator.inspector {
                current += [
                    inspector, inspector.store, inspector.splitController.previewController,
                ]
                if let window = inspector.window { current.append(window) }
            }
            return watched.compactMap { watched in
                guard let object = watched.object,
                      !current.contains(where: { $0 === object })
                else { return nil }
                return watched.name
            }
        }

        /// A new connection to the server, past the handshake.
        func connect() async throws -> Session {
            let channel = try await ConnectionChannel.connect(
                host: "127.0.0.1", port: server.port, timeout: .seconds(2))
            let session = Session(
                channel: channel, client: SoakTests.client, requestTimeout: .seconds(30))
            _ = try await session.handshake()
            return session
        }

        /// The app is lost, its connection closed, and found again over a new one, as
        /// discovery reports it (C-WIN-04).
        func reconnect() async throws {
            let old = session
            apps.apply(.lost(location))
            await old.close()
            session = try await connect()
            apps.apply(.found(location, SoakTests.info, session))
        }
    }

    /// Waits, turning the main actor over, until `condition` holds; fails naming `what`.
    @MainActor
    private func until(
        _ what: String, within limit: Duration = .seconds(30), _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + limit
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("timed out waiting: \(what)")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Prints a line of the report at once, also when the output goes into a pipe.
    private static func report(_ line: String) {
        print("C-SCALE-02 \(line)")
        fflush(stdout)
    }

    /// Whether the session has nothing on its way.
    private static func isQuiet(_ session: Session) async -> Bool {
        let requests = await session.pendingRequestCount
        let streams = await session.openStreamCount
        return requests == 0 && streams == 0
    }

    /// Waits until the inspection is loaded and asks for nothing more: the tree is in, every
    /// screenshot asked for has come, the attributes are in, and the session is quiet.
    @MainActor
    private func settle(_ soak: Soak, _ what: String) async throws {
        let (inspector, model) = try soak.current()
        try await until("\(what): loaded") {
            model.loadState == .loaded && !model.isLoading && model.queuedSubtrees.isEmpty
                && !model.reloadAgain && model.changedLayers.isEmpty
        }
        try await until("\(what): screenshots") {
            model.detailProgress.completed == model.detailProgress.total
        }
        try await until("\(what): attributes") {
            if case .loading = model.attributes.state { return false }
            return model.attributes.edits.isEmpty
        }
        let preview = inspector.splitController.previewController
        await preview.texturesSettled()
        try await until("\(what): still") { !preview.isInTransition }
        let deadline = ContinuousClock.now + .seconds(30)
        while await !Self.isQuiet(soak.session) {
            guard ContinuousClock.now < deadline else {
                XCTFail("\(what): the session is not quiet")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        // Something may have been asked for while the session was being looked at.
        try await until("\(what): screenshots, again") {
            !model.isLoading && model.detailProgress.completed == model.detailProgress.total
        }
        // Images that came meanwhile may wait for their showing.
        await preview.texturesSettled()
    }

    /// The value of an attribute of the selected layer, as the panel has it.
    @MainActor
    private static func value(_ id: String, in model: InspectionStore) -> AttributeValue?? {
        guard case .loaded(let groups, _) = model.attributes.state else { return nil }
        for group in groups {
            if let attribute = group.attributes.first(where: { $0.id == id }) {
                return .some(attribute.value)
            }
        }
        return nil
    }

    /// The folders of the temporary files the process has open that become `destination`
    /// once complete: what the system gave the archive's capture (`ArchiveCapture`).
    private static func temporaryFolders(becoming destination: URL) -> Set<String> {
        let name = destination.lastPathComponent
        let final = destination.resolvingSymlinksInPath().path
        return Set(
            OpenFiles.paths()
                .filter { $0.hasSuffix("/" + name) && $0 != final }
                .map { ($0 as NSString).deletingLastPathComponent })
    }

    // MARK: - C-SCALE-02

    @MainActor
    func test_C_SCALE_02_roundsOfEveryOperationLeaveNothingBehind() async throws {
        let rounds = Self.rounds
        let server = try await MockServer.start(
            script: MockScript(
                steps: try MockScript.fixtures("handshake").steps
                    + [.respond(Self.scene.responder())]),
            records: false)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoakTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Where the captures wrote before their archives took their places.
        var temporaryFolders = Set<String>()

        let soak = Soak(server: server, session: try await Self.connectFirst(to: server))
        addTeardownBlock { @MainActor in
            soak.inspector?.close()
            soak.coordinator.launcher.close()
            await soak.session.close()
            await server.stop()
            try? FileManager.default.removeItem(at: folder)
        }
        soak.coordinator.start()
        soak.apps.apply(.found(soak.location, Self.info, soak.session))
        try await until("the app is listed") {
            soak.apps.entries.contains { $0.id == soak.location && $0.isInspectable }
        }
        soak.apps.inspect(soak.location)
        try await until("the window opens") { soak.inspector != nil }
        try await settle(soak, "entering")
        soak.watchCurrent("entering")

        // Not kept: the first inspection must be let go of like the others.
        let (cells, layers) = try {
            let tree = try soak.current().1.tree
            return (tree.ids.filter { tree.node($0)?.viewClassName == "UITableViewCell" }, tree.ids)
        }()
        XCTAssertEqual(layers.count, 5_000)
        XCTAssertGreaterThan(cells.count, 10)

        let times = StepTimes()
        var footprints: [Int: UInt64] = [:]
        let start = ContinuousClock.now
        for round in 1...rounds {
            let seen = try await runRound(
                round, of: soak, cells: cells, layers: layers, folder: folder, times: times)
            temporaryFolders.formUnion(seen)
            try await settle(soak, "round \(round) end")
            times.step("settle")
            if round % 10 == 0 || round == rounds, let footprint = ProcessMemory.footprint {
                footprints[round] = footprint
                Self.report("round \(round): \(ProcessMemory.megabytes(footprint))")
            }
        }
        let elapsed = ContinuousClock.now - start
        Self.report("\(rounds) rounds: \(ScaleScene.milliseconds(elapsed))")
        for (name, total) in times.totals {
            Self.report("  \(name): \(ScaleScene.milliseconds(total / rounds)) a round")
        }
        if rounds > 10, let tenth = footprints[10], let last = footprints[rounds] {
            let ratio = Double(last) / Double(tenth)
            Self.report(String(
                format: "footprint after round %d / after round 10: %.3f (%@ 1.1)", rounds,
                ratio, ratio <= 1.1 ? "within" : "over"))
        }

        try await assertNothingIsLeft(by: soak, folder: folder, temporaryFolders: temporaryFolders)
        if ProcessInfo.processInfo.environment["CUTAWAY_SOAK_ROUNDS"] == nil {
            XCTAssertLessThanOrEqual(
                elapsed, .seconds(100), "\(rounds) rounds took \(ScaleScene.milliseconds(elapsed))")
        }
    }

    /// How long each step took over all rounds, printed at the end.
    @MainActor
    private final class StepTimes {
        private(set) var totals: [(String, Duration)] = []
        private var stepStart = ContinuousClock.now

        /// The next step starts now.
        func restart() {
            stepStart = ContinuousClock.now
        }

        /// The step `name` ends now; the next one starts.
        func step(_ name: String) {
            let now = ContinuousClock.now
            if let index = totals.firstIndex(where: { $0.0 == name }) {
                totals[index].1 += now - stepStart
            } else {
                totals.append((name, now - stepStart))
            }
            stepStart = now
        }
    }

    /// One round of every operation; returns the temporary folders the archive's capture used.
    @MainActor
    private func runRound(
        _ round: Int, of soak: Soak, cells: [UInt64], layers: [UInt64], folder: URL,
        times: StepTimes
    ) async throws -> Set<String> {
        let label = "round \(round)"
        var (_, model) = try soak.current()
        times.restart()

        // 1. Refresh.
        model.refresh()
        XCTAssertTrue(model.isLoading, "\(label): the refresh started")
        try await until("\(label): refreshed") { !model.isLoading }

        times.step("refresh")
        // 2. Refresh one cell's subtree.
        try await until("\(label): subtrees can be refreshed") { model.canRefreshSubtrees }
        let cell = cells[(round * 7) % cells.count]
        model.refreshSubtree(of: cell)
        XCTAssertTrue(model.isLoading, "\(label): the subtree was asked for")
        try await until("\(label): subtree refreshed") { !model.isLoading }

        times.step("subtree")
        // 3. Select another layer, and wait for its attributes.
        let selected = layers[(round * 7_919) % layers.count]
        model.select(selected)
        try await until("\(label): attributes") {
            model.attributes.selectedID == selected && model.attributes.canEdit
                && Self.value("layer.opacity", in: model) != nil
        }

        times.step("select")
        // 4. Switch between 2D and 3D.
        model.setPreviewMode(model.previewMode == .twoD ? .threeD : .twoD)

        // 5. Expand to a depth between 3 and 6.
        model.expand(toDepth: 3 + round % 4)

        times.step("mode and expansion")
        // 6. Change the selected layer's opacity. The expansion may have hidden the layer
        // in a collapsed node, which is then the one selected.
        let edited = try XCTUnwrap(model.selectedLayerID, label)
        try await until("\(label): attributes of the layer edited") {
            model.attributes.selectedID == edited && model.attributes.canEdit
                && Self.value("layer.opacity", in: model) != nil
        }
        let opacity = round % 2 == 0 ? 1.0 : 0.5
        let key = AttributeKey(layerID: edited, attributeID: "layer.opacity")
        model.attributes.set(key, to: .double(opacity), continuous: false)
        try await until("\(label): the change") {
            model.attributes.edits[key] == nil
                && Self.value("layer.opacity", in: model) == .some(.double(opacity))
        }

        times.step("edit")
        // 7. Leave, and come back over the same connection.
        soak.inspector?.close()
        try await until("\(label): left") { soak.inspector == nil }
        soak.apps.inspect(soak.location)
        try await until("\(label): back") { soak.inspector != nil }
        soak.watchCurrent("\(label), back")
        try await settle(soak, "\(label) back")

        times.step("leave and enter")
        // 8. Disconnect, and come back over a new connection.
        try await soak.reconnect()
        try await until("\(label): reconnected") {
            soak.inspector.map { $0.store !== model && !$0.isDisconnected } ?? false
        }
        soak.watchCurrent("\(label), reconnected")
        (_, model) = try soak.current()
        try await settle(soak, "\(label) reconnected")

        times.step("reconnect")
        // 9. Save an archive, then delete it.
        let url = folder.appendingPathComponent("round-\(round).cutaway")
        model.saveArchive(to: url, cutawayVersion: "0.1.0")
        var seen = Set<String>()
        try await until("\(label): saved", within: .seconds(60)) {
            seen.formUnion(Self.temporaryFolders(becoming: url))
            if case .saving = model.archiveSave { return false }
            return true
        }
        XCTAssertFalse(seen.isEmpty, "\(label): the capture's temporary file was not seen")
        XCTAssertEqual(model.archiveSave, .saved(url), label)
        try FileManager.default.removeItem(at: url)
        model.dismissArchiveSave()

        times.step("archive")
        return seen
    }

    /// Once the rounds are over: nothing outlived its round, and no archive left a file.
    @MainActor
    private func assertNothingIsLeft(
        by soak: Soak, folder: URL, temporaryFolders: Set<String>
    ) async throws {
        // What is left at the end.
        let (inspector, model) = try soak.current()
        XCTAssertTrue(
            Set(model.images.keys).isSubset(of: Set(model.tree.ids)),
            "screenshots of layers that are not in the tree")
        let preview = try XCTUnwrap(inspector.splitController.previewController.preview)
        XCTAssertFalse(model.layout.drawnTextures.isEmpty)
        XCTAssertTrue(
            preview.textures.keys.isSubset(of: model.layout.drawnTextures),
            "textures other than those of the layers drawn")
        // The GPU of a virtual Mac, as on a CI runner, refuses mipmapped images after a few
        // thousand: there the preview holds fewer than are drawn, and only the rest
        // can be asked of it.
        if MTLCreateSystemDefaultDevice()?.name.contains("Paravirtual") != true {
            XCTAssertEqual(
                preview.textures.keys, model.layout.drawnTextures, "a texture for each layer drawn")
        }
        let requests = await soak.session.pendingRequestCount
        let streams = await soak.session.openStreamCount
        XCTAssertEqual(requests, 0, "pending requests")
        XCTAssertEqual(streams, 0, "open streams")
        let deadline = ContinuousClock.now + .seconds(8)
        while !soak.leftovers().isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(soak.leftovers(), [], "outlived their round")
        XCTAssertEqual(
            temporaryFolders.filter { FileManager.default.fileExists(atPath: $0) }, [],
            "temporary folders of archives were left")
        let archiveFolders = temporaryFolders.union([folder.resolvingSymlinksInPath().path])
        XCTAssertEqual(
            OpenFiles.paths().filter { path in
                archiveFolders.contains { path.hasPrefix($0 + "/") }
            }, [], "archive files were left open")
    }

    private static func connectFirst(to server: MockServer) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: client, requestTimeout: .seconds(30))
        _ = try await session.handshake()
        return session
    }
}
