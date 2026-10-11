import CutawayScene
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-WIRE-09, one step further: a mutation that still decodes carries values nobody checked
/// for sense. The tree refuses what it must (repeated IDs and the like); whatever it takes is
/// laid out and projected without a crash.
final class DecodedMutationTests: XCTestCase {
    private let settings = FuzzSettings.current(defaultIterations: 300)

    func test_C_WIRE_09_mutatedHierarchiesThatDecodeAreLaidOutWithoutCrashing() throws {
        let payload = try Fixtures.data(scenario: "hierarchy", file: "02-s2c-hierarchy.bin")
        let viewport = Viewport(width: 480, height: 900)
        var laidOut = 0
        let mutations = Mutation.all(
            of: payload, randomCount: settings.iterations, seed: settings.seed)
        for mutation in mutations {
            guard let frame = try? FrameCodec.decode(mutation.applied(to: payload)),
                  case .hierarchy(let hierarchy) = frame.body,
                  let tree = try? LayerTree(hierarchy)
            else { continue }
            let layers = tree.sceneLayers(textures: [:])
            let ids = Set(layers.map(\.id))
            for focus in [nil, layers.first?.id] {
                let layout = SceneLayout(
                    layers: layers, expanded: ids, focus: focus, showsHidden: true)
                for camera in [Camera.flat, .standard3D] {
                    let list = layout.project(
                        camera: camera, viewport: viewport, selected: layers.last?.id,
                        hovered: layers.first?.id, measuring: layers.first?.id)
                    for item in list.items {
                        XCTAssertTrue(
                            item.corners.allSatisfy {
                                [$0.x, $0.y, $0.z, $0.w].allSatisfy(\.isFinite)
                            },
                            "\(mutation): layer \(item.layerID) has corners that are not finite")
                    }
                    _ = layout.hitTest(
                        point: ScenePoint(x: 240, y: 450), camera: camera, viewport: viewport)
                }
            }
            laidOut += 1
        }
        XCTAssertGreaterThan(laidOut, 100, "mutated hierarchies that the tree took")
    }
}
