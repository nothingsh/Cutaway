import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// An answer that comes after the inspection is gone does nothing. The helpers that ask for
/// the hierarchy, the screenshots and the changes may still be running then: a task holds
/// them while it delivers the answer, and the inspection may be let go of on another thread
/// meanwhile (C-DET-02).
final class InspectionLifetimeTests: XCTestCase {
    /// The fixtures' app without a connection (`MockResponder.demo()`), which holds back what
    /// it is told to until the test lets it go.
    private actor GatedSource: InspectionSource {
        nonisolated var isLive: Bool { true }
        var negotiatedVersion: Version? { ProtocolVersion.current }
        private let responder: MockResponder
        private let holdsHierarchy: Bool
        private var hierarchyWaits: [CheckedContinuation<Void, Never>] = []
        private var detailsWait: (GetLayerDetails, AsyncThrowingStream<[LayerDetail], any Error>.Continuation)?
        private var changeWaits: [CheckedContinuation<Void, Never>] = []

        init(holdsHierarchy: Bool = false) throws {
            responder = try MockResponder.demo()
            self.holdsHierarchy = holdsHierarchy
        }

        var isHoldingHierarchy: Bool { !hierarchyWaits.isEmpty }
        var isHoldingDetails: Bool { detailsWait != nil }
        var isHoldingChange: Bool { !changeWaits.isEmpty }

        func hierarchy() async throws -> Hierarchy {
            if holdsHierarchy {
                await withCheckedContinuation { hierarchyWaits.append($0) }
            }
            return responder.hierarchy
        }

        func subtree(of rootID: UInt64) async throws -> Hierarchy {
            throw RequestError.unsupported
        }

        func layerDetails(_ request: GetLayerDetails) async -> LayerDetailsStream {
            let (chunks, continuation) = AsyncThrowingStream.makeStream(of: [LayerDetail].self)
            // Only the first batch is held; later ones are not asked for meanwhile.
            if detailsWait == nil {
                detailsWait = (request, continuation)
            } else {
                continuation.yield(responder.answer(request))
                continuation.finish()
            }
            return LayerDetailsStream(chunks: chunks, cancelAction: {})
        }

        func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult {
            await withCheckedContinuation { changeWaits.append($0) }
            throw RequestError.invalidAttributeValue(message: nil)
        }

        func releaseHierarchy() {
            hierarchyWaits.forEach { $0.resume() }
            hierarchyWaits.removeAll()
        }

        func releaseDetails() {
            guard let (request, continuation) = detailsWait else { return }
            continuation.yield(responder.answer(request))
            continuation.finish()
        }

        func releaseChange() {
            changeWaits.forEach { $0.resume() }
            changeWaits.removeAll()
        }
    }

    /// Lets the main actor take what the released answer brings.
    @MainActor
    private func settle() async throws {
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(20))
            await Task.yield()
        }
    }

    @MainActor
    func test_C_DET_02_aBatchThatEndsAfterTheInspectionIsGoneDoesNothing() async throws {
        let source = try GatedSource()
        var model: InspectionStore? = InspectionStore(source: source, newLayers: .expanded)
        model?.enter()
        let held = await Wait.until(within: .seconds(3)) { await source.isHoldingDetails }
        XCTAssertTrue(held)
        let fetcher = try XCTUnwrap(model?.fetcher)
        weak let gone = model
        model = nil
        XCTAssertNil(gone, "nothing else keeps the inspection")

        await source.releaseDetails()
        try await settle()
        XCTAssertEqual(fetcher.batchesStarted, 1, "no batch is asked for after it")
    }

    @MainActor
    func test_C_DET_02_aHierarchyThatComesAfterTheInspectionIsGoneDoesNothing() async throws {
        let source = try GatedSource(holdsHierarchy: true)
        var model: InspectionStore? = InspectionStore(source: source, newLayers: .expanded)
        model?.enter()
        let held = await Wait.until { await source.isHoldingHierarchy }
        XCTAssertTrue(held)
        let loader = try XCTUnwrap(model?.loader)
        weak let gone = model
        model = nil
        XCTAssertNil(gone, "nothing else keeps the inspection")

        await source.releaseHierarchy()
        try await settle()
        XCTAssertFalse(loader.isLoading)
    }

    @MainActor
    func test_C_DET_02_aChangeAnsweredAfterTheAttributesAreGoneDoesNothing() async throws {
        let source = try GatedSource()
        var store: AttributesStore? = AttributesStore(source: source)
        store?.setEditingSupported(true)
        let key = AttributeKey(layerID: 3, attributeID: "alpha")
        store?.setRegardlessOfSelection(key, to: .double(0.5), continuous: false)
        let held = await Wait.until { await source.isHoldingChange }
        XCTAssertTrue(held)
        let editor = try XCTUnwrap(store?.editor)
        weak let gone = store
        store = nil
        XCTAssertNil(gone, "nothing else keeps the attributes")

        await source.releaseChange()
        try await settle()
        XCTAssertFalse(editor.isChanging(layer: 3))
    }
}
