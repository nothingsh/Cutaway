import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-SCALE-02: taking in the screenshots of 10,000 layers chunk by chunk costs what each
/// chunk's layers cost, not what the layers held before them cost. The time is printed.
final class ScaleImageTakingTests: XCTestCase {
    @MainActor
    func test_C_SCALE_02_takingTenThousandLayersScreenshotsChunkByChunkStaysCheap() {
        let scene = ScaleScene.synthetic
        let hierarchy = scene.hierarchy()
        let details = scene.details()
        let model = InspectionStore(
            session: Session(
                channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")))
        model.apply(hierarchy)
        let bitmap = Bitmap(
            pixelWidth: 1, pixelHeight: 1, bytesPerRow: 4, scale: 1, pixels: Data(count: 4))
        let ids = hierarchy.nodes.map(\.id)
        let chunks = stride(from: 0, to: ids.count, by: 8).map { start in
            ids[start..<min(start + 8, ids.count)].compactMap { details[$0] }.map {
                ImageDecompression.DecompressedDetail(
                    detail: $0, solo: $0.solo == nil ? nil : bitmap,
                    group: $0.group == nil ? nil : bitmap)
            }
        }
        var signals = 0
        let subscription = model.imagesChanged.sink { _ in signals += 1 }

        let start = ContinuousClock.now
        for chunk in chunks { model.take(chunk) }
        let elapsed = ContinuousClock.now - start
        subscription.cancel()

        print(
            "C-SCALE-02 taking the screenshots of \(ids.count) layers in \(chunks.count) chunks: "
                + ScaleScene.milliseconds(elapsed))
        XCTAssertEqual(model.images.count, ids.count)
        XCTAssertEqual(signals, chunks.count, "each chunk says once what it changed")
    }
}
