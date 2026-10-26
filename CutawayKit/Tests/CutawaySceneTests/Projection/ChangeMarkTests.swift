import CutawayScene
import XCTest

/// What a refresh changed, marked on a list already projected (C-REND-12): the new and the
/// changed layers' items say so, nothing else in the list moves, and the fade is one strength
/// for every mark.
final class ChangeMarkTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)

    private func projected(camera: Camera) throws -> DrawList {
        let layout = SceneLayout(layers: try SceneFixtures.hierarchyLayers(), expanded: SceneFixtures.allIDs)
        return layout.project(
            camera: camera, viewport: viewport, selected: 3, hovered: 5, marks: [.layer(4)])
    }

    func test_C_REND_12_theNewAndTheChangedItemsAreMarkedAndNoOthers() throws {
        for camera in [Camera.flat, .standard3D] {
            let list = try projected(camera: camera)
            let marked = list.markingChanges(added: [4, 42], changed: [3, 8], strength: 0.75)
            for item in marked.items {
                let expected: ChangeMark? = switch item.layerID {
                case 4: .added
                case 3, 8: .changed
                default: nil
                }
                XCTAssertEqual(item.change, expected, "layer \(item.layerID), \(camera)")
            }
            XCTAssertEqual(marked.changeStrength, 0.75)
        }
    }

    func test_C_REND_12_markingChangesTouchesNothingElse() throws {
        for camera in [Camera.flat, .standard3D] {
            let list = try projected(camera: camera)
            var marked = list.markingChanges(added: [4], changed: [3], strength: 1)
            // Taking the marks off again gives the list as it was projected.
            XCTAssertNotEqual(marked, list)
            marked = marked.markingChanges(added: [], changed: [], strength: 0)
            XCTAssertEqual(marked, list, "\(camera)")
        }
    }

    func test_C_REND_12_aProjectionMarksNothing() throws {
        let list = try projected(camera: .standard3D)
        XCTAssertTrue(list.items.allSatisfy { $0.change == nil })
        XCTAssertEqual(list.changeStrength, 0)
    }
}
