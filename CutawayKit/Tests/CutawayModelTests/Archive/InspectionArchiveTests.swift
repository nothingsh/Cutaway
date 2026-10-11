import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-ARCH-02 and C-ARCH-03: saving an archive from an inspection.
@MainActor
final class InspectionArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InspectionArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var destination: URL { directory.appendingPathComponent("Demo.cutaway") }

    private func eventually(
        within timeout: Duration = .seconds(3), _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// An open inspection of the fixtures' app, its tree loaded and layer 3 selected with its
    /// attributes in.
    private func openInspection(
        _ responder: MockResponder
    ) async throws -> (MockServer, Session, InspectionStore) {
        let server = try await ArchiveCaptureTests.server(responder)
        let session = try await ArchiveCaptureTests.session(to: server)
        let model = InspectionStore(session: session)
        model.enter()
        let loaded = await eventually { model.loadState == .loaded }
        XCTAssertTrue(loaded)
        model.select(3)
        let editable = await eventually { model.attributes.canEdit }
        XCTAssertTrue(editable)
        return (server, session, model)
    }

    private func heldResponder(_ gate: MockGate) throws -> MockResponder {
        var responder = try MockResponder.demo()
        responder.holdBeforeDetails = (MockResponder.isArchiveBatch, gate)
        return responder
    }

    private func archiveBatchArrived(_ server: MockServer) async -> Bool {
        await server.receivedFrames.contains {
            guard case .getLayerDetails(let request) = $0.body else { return false }
            return MockResponder.isArchiveBatch(request)
        }
    }

    private func hierarchyRequests(_ server: MockServer) async -> Int {
        await server.receivedFrames.filter {
            if case .getHierarchy = $0.body { return true }
            return false
        }.count
    }

    // MARK: - C-ARCH-02

    func test_C_ARCH_02_anInspectionSavesAnArchive() async throws {
        let (server, session, model) = try await openInspection(try MockResponder.demo())

        model.saveArchive(to: destination, cutawayVersion: "0.1.0")
        XCTAssertTrue(model.isSavingArchive)
        let saved = await eventually { model.archiveSave == .saved(self.destination) }
        XCTAssertTrue(saved, "ended as \(model.archiveSave)")
        XCTAssertFalse(model.isSavingArchive)
        let decoder = try ArchiveDecoder(try Data(contentsOf: destination))
        XCTAssertEqual(decoder.hierarchy.nodes.count, 9)

        model.dismissArchiveSave()
        XCTAssertEqual(model.archiveSave, .idle)
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_whileSavingRefreshAndEditingAreOff() async throws {
        let gate = MockGate()
        let (server, session, model) = try await openInspection(try heldResponder(gate))

        model.saveArchive(to: destination, cutawayVersion: "0.1.0")
        let held = await eventually { await self.archiveBatchArrived(server) }
        XCTAssertTrue(held)
        guard case .saving(let completed, let total) = model.archiveSave else {
            XCTFail("not saving: \(model.archiveSave)")
            return
        }
        XCTAssertEqual(completed, 0)
        XCTAssertEqual(total, 9)
        XCTAssertFalse(model.attributes.canEdit)

        // Refreshing does nothing; browsing still works.
        let before = await hierarchyRequests(server)
        model.refresh()
        model.refreshSubtree(of: 4)
        model.select(4)
        XCTAssertEqual(model.selectedLayerID, 4)
        model.setPreviewMode(.threeD)
        let camera = model.cameras.threeD
        model.rotate(byDragOf: 30, 0)
        XCTAssertNotEqual(model.cameras.threeD, camera)

        // Saving again while saving does nothing.
        model.saveArchive(to: directory.appendingPathComponent("Other.cutaway"), cutawayVersion: "0.1.0")

        await gate.open()
        let saved = await eventually { model.archiveSave == .saved(self.destination) }
        XCTAssertTrue(saved, "ended as \(model.archiveSave)")
        let after = await hierarchyRequests(server)
        // The capture had asked for its hierarchy before the batch it waits on; no refresh.
        XCTAssertEqual(after, before)
        let editable = await eventually { model.attributes.canEdit }
        XCTAssertTrue(editable)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Other.cutaway").path))

        model.refresh()
        let refreshed = await eventually { await self.hierarchyRequests(server) == after + 1 }
        XCTAssertTrue(refreshed)
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_aFailedSaveSaysWhy() async throws {
        var responder = try MockResponder.demo()
        responder.failDetails = (MockResponder.isArchiveBatch, .appNotActive)
        let (server, session, model) = try await openInspection(responder)

        model.saveArchive(to: destination, cutawayVersion: "0.1.0")
        let failed = await eventually { model.archiveSave == .failed(.appNotActive) }
        XCTAssertTrue(failed, "ended as \(model.archiveSave)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let editable = await eventually { model.attributes.canEdit }
        XCTAssertTrue(editable)

        model.dismissArchiveSave()
        XCTAssertEqual(model.archiveSave, .idle)
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_leavingTheInspectionCancelsTheSave() async throws {
        let gate = MockGate()
        let (server, session, model) = try await openInspection(try heldResponder(gate))

        model.saveArchive(to: destination, cutawayVersion: "0.1.0")
        let held = await eventually { await self.archiveBatchArrived(server) }
        XCTAssertTrue(held)
        model.leave()
        let ended = await eventually { model.archiveSave == .idle }
        XCTAssertTrue(ended, "ended as \(model.archiveSave)")
        await gate.open()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        await session.close()
        await server.stop()
    }

    func test_C_ARCH_02_losingTheConnectionFailsTheSave() async throws {
        let gate = MockGate()
        let (server, session, model) = try await openInspection(try heldResponder(gate))

        model.saveArchive(to: destination, cutawayVersion: "0.1.0")
        let held = await eventually { await self.archiveBatchArrived(server) }
        XCTAssertTrue(held)
        // What the app list does when the app goes (C-WIN-03).
        model.connectionLost()
        model.leave()
        let failed = await eventually { model.archiveSave == .failed(.disconnected) }
        XCTAssertTrue(failed, "ended as \(model.archiveSave)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        await gate.open()
        await session.close()
        await server.stop()
    }

    // MARK: - C-ARCH-03

    func test_C_ARCH_03_theStateIsTheInspectionsAtTheMomentOfSaving() async throws {
        let gate = MockGate()
        let (server, session, model) = try await openInspection(try heldResponder(gate))
        model.setExpanded([1, 2, 4], true)
        model.setExpanded([6], false)
        model.select(4)
        model.focus(on: 2)
        model.setPreviewMode(.threeD)
        model.rotate(byDragOf: 40, 10)
        model.setLayerSpacing(90)
        model.setShowsHiddenLayers(true)
        model.setShowsBorders(false)
        let expected = ArchiveState(
            expanded: model.expandedLayerIDs, selected: 4, focused: 2, previewMode: .threeD,
            cameras: model.cameras, showsHiddenLayers: true, showsBorders: false)
        XCTAssertEqual(model.archiveState, expected)

        model.saveArchive(to: destination, cutawayVersion: "0.1.0")
        let held = await eventually { await self.archiveBatchArrived(server) }
        XCTAssertTrue(held)
        // Changes made while saving are not in the archive.
        model.select(3)
        model.setPreviewMode(.twoD)
        await gate.open()
        let saved = await eventually { model.archiveSave == .saved(self.destination) }
        XCTAssertTrue(saved, "ended as \(model.archiveSave)")

        let decoder = try ArchiveDecoder(try Data(contentsOf: destination))
        XCTAssertEqual(ArchiveState(decoding: decoder.state), expected)
        await session.close()
        await server.stop()
    }
}
