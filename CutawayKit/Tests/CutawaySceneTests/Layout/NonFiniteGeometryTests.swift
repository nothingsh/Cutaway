import CutawayScene
import XCTest

/// C-SCENE-11: a layer whose geometry is not a finite number, or whose corners come out too
/// large for the drawing layer's `Float`, cannot be placed. It and its sublayers are not drawn,
/// hit, measured, marked or framed; the other layers are drawn as if they were not there.
final class NonFiniteGeometryTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)
    /// Layer 4 of the `hierarchy` fixture and the layer inside it. Layer 5 is hidden in the
    /// fixture, so every layout here shows hidden layers: otherwise it would not be drawn
    /// anyway.
    private let poisoned: UInt64 = 4
    private let inside: Set<UInt64> = [4, 5]

    /// One way of spoiling a layer's geometry.
    private struct Spoil {
        var name: String
        var change: (inout SceneLayer) -> Void
    }

    /// Every number a layer is placed with. Key paths are not `Sendable`; the list is never
    /// changed.
    private nonisolated(unsafe) static let fields:
        [(String, WritableKeyPath<SceneLayer, Double>)] = [
            ("bounds.x", \.bounds.origin.x), ("bounds.y", \.bounds.origin.y),
            ("bounds.width", \.bounds.size.width), ("bounds.height", \.bounds.size.height),
            ("position.x", \.position.x), ("position.y", \.position.y),
            ("anchorPoint.x", \.anchorPoint.x), ("anchorPoint.y", \.anchorPoint.y),
            ("m11", \.transform.m11), ("m12", \.transform.m12), ("m13", \.transform.m13),
            ("m14", \.transform.m14), ("m21", \.transform.m21), ("m22", \.transform.m22),
            ("m23", \.transform.m23), ("m24", \.transform.m24), ("m31", \.transform.m31),
            ("m32", \.transform.m32), ("m33", \.transform.m33), ("m34", \.transform.m34),
            ("m41", \.transform.m41), ("m42", \.transform.m42), ("m43", \.transform.m43),
            ("m44", \.transform.m44),
        ]

    private var spoils: [Spoil] {
        var spoils: [Spoil] = []
        for (label, value) in [("NaN", Double.nan), ("+inf", .infinity), ("-inf", -.infinity)] {
            // The parts of the transform the projection does not use count as well: any of
            // them not being finite says the layer is broken.
            for (name, field) in Self.fields {
                spoils.append(Spoil(name: "\(name) \(label)") { $0[keyPath: field] = value })
            }
        }
        // Finite numbers whose corners overflow a Double, and corners beyond a Float.
        spoils.append(Spoil(name: "scale 1e308") {
            $0.transform.m11 = 1e308; $0.transform.m22 = 1e308
        })
        spoils.append(Spoil(name: "scale 1e37") {
            $0.transform.m11 = 1e37; $0.transform.m22 = 1e37
        })
        return spoils
    }

    private func layers(spoiledBy spoil: Spoil) throws -> [SceneLayer] {
        try SceneFixtures.hierarchyLayers().map { layer in
            var layer = layer
            if layer.id == poisoned { spoil.change(&layer) }
            return layer
        }
    }

    private func isFinite(_ list: DrawList) -> Bool {
        list.items.allSatisfy { item in
            item.corners.allSatisfy { [$0.x, $0.y, $0.z, $0.w].allSatisfy(\.isFinite) }
                && item.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        }
    }

    func test_C_SCENE_11_aLayerThatCannotBePlacedIsNotDrawnNorAreItsSublayers() throws {
        // Unspoiled, both are drawn: what follows is not the fixture hiding them.
        let unspoiled = SceneLayout(
            layers: try SceneFixtures.hierarchyLayers(), expanded: SceneFixtures.allIDs,
            showsHidden: true)
        let drawnUnspoiled = Set(
            unspoiled.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
                .items.map(\.layerID))
        XCTAssertTrue(inside.isSubset(of: drawnUnspoiled))
        for spoil in spoils {
            let layout = SceneLayout(
                layers: try layers(spoiledBy: spoil), expanded: SceneFixtures.allIDs,
                showsHidden: true)
            for camera in [Camera.flat, .standard3D] {
                let drawn = Set(
                    layout.project(camera: camera, viewport: viewport, selected: nil, hovered: nil)
                        .items.map(\.layerID))
                XCTAssertTrue(drawn.isDisjoint(with: inside), "\(spoil.name): drew \(drawn)")
                XCTAssertFalse(drawn.isEmpty, spoil.name)
            }
            XCTAssertFalse(
                layout.neededTextures.contains { inside.contains($0.layerID) }, spoil.name)
        }
    }

    func test_C_SCENE_11_theOtherLayersAreDrawnAsIfItWereNotThere() throws {
        let without = SceneLayout(
            layers: try SceneFixtures.hierarchyLayers().filter { !inside.contains($0.id) },
            expanded: SceneFixtures.allIDs, showsHidden: true)
        for spoil in spoils {
            let layout = SceneLayout(
                layers: try layers(spoiledBy: spoil), expanded: SceneFixtures.allIDs,
                showsHidden: true)
            XCTAssertEqual(layout.contentBox, without.contentBox, spoil.name)
            for camera in [Camera.flat, .standard3D] {
                XCTAssertEqual(
                    layout.project(camera: camera, viewport: viewport, selected: 3, hovered: 2),
                    without.project(camera: camera, viewport: viewport, selected: 3, hovered: 2),
                    spoil.name)
            }
            for id in SceneFixtures.allIDs.subtracting(inside) {
                XCTAssertEqual(
                    layout.level(of: id), without.level(of: id), "\(spoil.name), layer \(id)")
            }
        }
    }

    func test_C_SCENE_11_itCannotBeHitMeasuredOrMarked() throws {
        for spoil in spoils {
            let layout = SceneLayout(
                layers: try layers(spoiledBy: spoil), expanded: SceneFixtures.allIDs,
                showsHidden: true)
            XCTAssertNil(layout.quad(of: poisoned), spoil.name)
            XCTAssertNil(layout.quad(of: 5), spoil.name)
            XCTAssertNil(
                layout.quad(of: SceneRect(x: 0, y: 0, width: 10, height: 10), in: poisoned),
                spoil.name)
            XCTAssertNil(layout.measurement(from: 3, to: poisoned), spoil.name)
            XCTAssertNil(layout.measurement(from: poisoned, to: 3), spoil.name)

            let list = layout.project(
                camera: .flat, viewport: viewport, selected: poisoned, hovered: 5,
                marks: [.layer(poisoned), .area(SceneRect(x: 0, y: 0, width: 4, height: 4), in: 5),
                        .layer(3)],
                measuring: 3)
            XCTAssertEqual(list.marks.map(\.mark), [.layer(3)], spoil.name)
            XCTAssertNil(list.measurement, spoil.name)
            // Nothing is hit where the layer would be: every point of the viewport is checked
            // on a coarse grid, and a hit is never one of the two.
            for x in stride(from: 0.0, through: viewport.width, by: 30) {
                for y in stride(from: 0.0, through: viewport.height, by: 30) {
                    for camera in [Camera.flat, .standard3D] {
                        let hit = layout.hitTest(
                            point: ScenePoint(x: x, y: y), camera: camera, viewport: viewport)
                        XCTAssertFalse(
                            hit.map(inside.contains) ?? false, "\(spoil.name) at \(x), \(y)")
                    }
                }
            }
        }
    }

    func test_C_SCENE_11_theCameraIsFittedToTheRestWithFiniteParameters() throws {
        for spoil in spoils {
            let layers = try layers(spoiledBy: spoil)
            let layout = SceneLayout(
                layers: layers, expanded: SceneFixtures.allIDs, showsHidden: true)
            let box = try XCTUnwrap(layout.contentBox, spoil.name)
            XCTAssertTrue(
                [box.origin.x, box.origin.y, box.size.width, box.size.height]
                    .allSatisfy(\.isFinite),
                spoil.name)
            var turned = Camera.standard3D
            turned.yaw = 0.4
            turned.pitch = -0.3
            for camera in [Camera.flat, .standard3D, turned] {
                let list = layout.project(
                    camera: camera, viewport: viewport, selected: 3, hovered: nil)
                XCTAssertTrue(isFinite(list), spoil.name)
            }
            // Focused on the layer that cannot be placed: nothing to frame, nothing drawn.
            let focused = SceneLayout(
                layers: layers, expanded: SceneFixtures.allIDs, focus: poisoned,
                showsHidden: true)
            XCTAssertNil(focused.contentBox, spoil.name)
            XCTAssertEqual(
                focused.project(
                    camera: .standard3D, viewport: viewport, selected: poisoned, hovered: nil),
                .empty, spoil.name)
        }
    }

    func test_C_SCENE_11_aValueUnusedByTheProjectionStillCounts() throws {
        var layers = try SceneFixtures.hierarchyLayers()
        let index = try XCTUnwrap(layers.firstIndex { $0.id == poisoned })
        layers[index].transform.m34 = .nan
        let layout = SceneLayout(layers: layers, expanded: SceneFixtures.allIDs, showsHidden: true)
        XCTAssertNil(layout.quad(of: poisoned))
        XCTAssertNil(layout.quad(of: 5), "a sublayer of a layer that cannot be placed")
        let drawn = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
            .items.map(\.layerID)
        XCTAssertFalse(drawn.contains(poisoned))
        XCTAssertFalse(drawn.contains(5))
    }
}
