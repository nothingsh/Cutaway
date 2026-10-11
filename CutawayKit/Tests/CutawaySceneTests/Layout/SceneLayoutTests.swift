import CutawayScene
import XCTest

/// The layout: corners, visibility, images and opacity (C-SCENE-01, 03, 06) and levels
/// (C-SCENE-02).
final class SceneLayoutTests: XCTestCase {
    private func fixtureLayout(
        expanded: Set<UInt64> = SceneFixtures.allIDs, textures: [UInt64: LayerTextures] = [:],
        focus: UInt64? = nil, showsHidden: Bool = false
    ) throws -> SceneLayout {
        SceneLayout(
            layers: try SceneFixtures.hierarchyLayers(textures: textures), expanded: expanded,
            focus: focus, showsHidden: showsHidden)
    }

    // MARK: - C-SCENE-01: where the layers are

    func test_C_SCENE_01_cornersMatchTheReferenceCoordinates() throws {
        let layout = try fixtureLayout()
        // The reference corners, worked out apart from the code: top left, top right, bottom
        // left, bottom right.
        let reference: [UInt64: [(Double, Double)]] = [
            3: [(96.5, 108), (296.5, 108), (96.5, 132), (296.5, 132)],
            4: [
                (111.5961894323342, 147.05771365940052), (371.4038105676658, 297.0577136594005),
                (21.5961894323342, 302.9422863405995), (281.4038105676658, 452.9422863405995),
            ],
            5: [
                (118.91669750802296, 174.37822173508928), (153.55771365940052, 194.37822173508928),
                (98.91669750802296, 209.01923788646684), (133.55771365940052, 229.01923788646684),
            ],
            7: [(146.5, 530), (246.5, 530), (146.5, 570), (246.5, 570)],
            8: [(10, 10), (70, 10), (10, 40), (70, 40)],
        ]
        for (id, corners) in reference {
            let quad = try XCTUnwrap(layout.quad(of: id), "layer \(id)")
            let actual = [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight]
            for (index, (point, expected)) in zip(actual, corners).enumerated() {
                XCTAssertEqual(point.x, expected.0, accuracy: 1e-6, "layer \(id) corner \(index)")
                XCTAssertEqual(point.y, expected.1, accuracy: 1e-6, "layer \(id) corner \(index)")
            }
        }
    }

    func test_C_SCENE_01_cornersDoNotDependOnWhatIsExpanded() throws {
        let expanded = try fixtureLayout()
        let collapsed = try fixtureLayout(expanded: [])
        for id: UInt64 in 1...9 {
            XCTAssertEqual(expanded.quad(of: id), collapsed.quad(of: id), "layer \(id)")
        }
    }

    func test_C_SCENE_01_aLayerWhoseParentIsNotBeforeItIsARoot() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, parent: 7, x: 10, y: 20, width: 30, height: 40),
                SceneFixtures.layer(7, x: 100, y: 100, width: 10, height: 10),
            ],
            expanded: [1, 7])
        XCTAssertEqual(layout.quad(of: 1)?.topLeft, ScenePoint(x: 10, y: 20))
        XCTAssertTrue(layout.isDisplayed(1))
        XCTAssertNil(layout.quad(of: 99))
    }

    // MARK: - C-SCENE-03: visibility and which image

    func test_C_SCENE_03_aHiddenLayerIsNotDisplayed() throws {
        let layout = try fixtureLayout()
        XCTAssertFalse(layout.isDisplayed(5))
        XCTAssertNil(layout.texture(of: 5))
        for id: UInt64 in [1, 2, 3, 4, 6, 7, 8, 9] {
            XCTAssertTrue(layout.isDisplayed(id), "layer \(id)")
        }
    }

    func test_C_SCENE_03_theDescendantsOfAHiddenLayerAreNotDisplayed() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 50, height: 50, hidden: true),
                SceneFixtures.layer(3, parent: 2, x: 0, y: 0, width: 10, height: 10),
            ],
            expanded: [1, 2, 3])
        XCTAssertTrue(layout.isDisplayed(1))
        XCTAssertFalse(layout.isDisplayed(2))
        XCTAssertFalse(layout.isDisplayed(3))
        XCTAssertNil(layout.level(of: 3))
    }

    func test_C_SCENE_03_aCollapsedNodeUsesItsGroupAndHidesItsSubtree() throws {
        let textures: [UInt64: LayerTextures] = [
            6: LayerTextures(solo: SceneFixtures.solo(6), group: SceneFixtures.group(6)),
            7: LayerTextures(group: SceneFixtures.group(7)),
        ]
        var expanded = SceneFixtures.allIDs
        expanded.remove(6)
        let layout = try fixtureLayout(expanded: expanded, textures: textures)

        XCTAssertTrue(layout.isDisplayed(6))
        XCTAssertEqual(layout.texture(of: 6), SceneFixtures.group(6))
        XCTAssertFalse(layout.isDisplayed(7))
        XCTAssertNil(layout.texture(of: 7))
    }

    func test_C_SCENE_03_anExpandedNodeUsesItsSolo() throws {
        let textures: [UInt64: LayerTextures] = [
            4: LayerTextures(solo: SceneFixtures.solo(4), group: SceneFixtures.group(4)),
        ]
        let layout = try fixtureLayout(textures: textures)
        XCTAssertEqual(layout.texture(of: 4), SceneFixtures.solo(4))
    }

    func test_C_SCENE_03_anExpandedLeafWithoutSoloUsesItsGroup() throws {
        // Layer 3 has no sublayers; the server may leave its solo out (P-DET-04).
        let layout = try fixtureLayout(textures: [3: LayerTextures(group: SceneFixtures.group(3))])
        XCTAssertEqual(layout.texture(of: 3), SceneFixtures.group(3))
    }

    func test_C_SCENE_03_anExpandedNodeWithSublayersAndWithoutSoloHasNoImage() throws {
        // Layer 4's only sublayer, 5, is hidden; 4 still has a sublayer.
        let layout = try fixtureLayout(textures: [4: LayerTextures(group: SceneFixtures.group(4))])
        XCTAssertTrue(layout.isDisplayed(4))
        XCTAssertNil(layout.texture(of: 4))
    }

    func test_C_SCENE_03_aCollapsedNodeWithoutGroupHasNoImage() throws {
        var expanded = SceneFixtures.allIDs
        expanded.remove(4)
        let layout = try fixtureLayout(
            expanded: expanded, textures: [4: LayerTextures(solo: SceneFixtures.solo(4))])
        XCTAssertNil(layout.texture(of: 4))
    }

    // MARK: - C-SCENE-06: opacity

    func test_C_SCENE_06_opacityIsMultipliedDownTheTree() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100, opacity: 0.5),
                SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 50, height: 50, opacity: 0.5),
                SceneFixtures.layer(3, parent: 2, x: 0, y: 0, width: 10, height: 10),
            ],
            expanded: [1, 2, 3])
        XCTAssertEqual(layout.opacity(of: 1), 0.5)
        XCTAssertEqual(layout.opacity(of: 2), 0.25)
        XCTAssertEqual(layout.opacity(of: 3), 0.25)
    }

    func test_C_SCENE_06_aNaNOpacityIsTakenAsOne() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100, opacity: .nan),
                SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 50, height: 50, opacity: 0.5),
            ],
            expanded: [1, 2])
        XCTAssertEqual(layout.opacity(of: 1), 1)
        XCTAssertEqual(layout.opacity(of: 2), 0.5)
    }

    func test_C_SCENE_06_twoNegativeOpacitiesDoNotMakeAVisibleLayer() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100, opacity: -1),
                SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 50, height: 50, opacity: -1),
                SceneFixtures.layer(3, parent: 2, x: 0, y: 0, width: 10, height: 10, opacity: 2),
            ],
            expanded: [1, 2, 3])
        XCTAssertEqual(layout.opacity(of: 1), 0)
        XCTAssertEqual(layout.opacity(of: 2), 0)
        XCTAssertEqual(layout.opacity(of: 3), 0)
    }

    func test_C_SCENE_06_theFixturesVisibleLayersAreOpaque() throws {
        let layout = try fixtureLayout()
        for id: UInt64 in [1, 2, 3, 4, 6, 7, 8, 9] {
            XCTAssertEqual(layout.opacity(of: id), 1, "layer \(id)")
        }
    }

    // MARK: - C-SCENE-02: levels

    func test_C_SCENE_02_theFixturesLevels() throws {
        let layout = try fixtureLayout()
        let expected: [UInt64: Int] = [1: 0, 2: 1, 3: 2, 4: 2, 6: 2, 7: 3, 8: 2, 9: 0]
        for (id, level) in expected {
            XCTAssertEqual(layout.level(of: id), level, "layer \(id)")
        }
        XCTAssertNil(layout.level(of: 5), "a hidden layer has no level")
    }

    func test_C_SCENE_02_layersThatOnlyShareAnEdgeOrACornerDoNotOverlap() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, x: 100, y: 0, width: 100, height: 100),
                SceneFixtures.layer(3, x: 100, y: 100, width: 100, height: 100),
            ],
            expanded: [1, 2, 3])
        XCTAssertEqual(layout.level(of: 1), 0)
        XCTAssertEqual(layout.level(of: 2), 0)
        XCTAssertEqual(layout.level(of: 3), 0)
    }

    func test_C_SCENE_02_overlappingBoundingBoxesAreNotEnough() {
        // A square turned by 45° whose left corner is at (99.3, 170): its bounding box
        // reaches into the first square's, its shape does not.
        var turned = SceneFixtures.layer(2, x: 170, y: 170, width: 100, height: 100)
        turned.anchorPoint = ScenePoint(x: 0.5, y: 0.5)
        turned.transform = SceneFixtures.rotation(degrees: 45)
        let layout = SceneLayout(
            layers: [SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100), turned],
            expanded: [1, 2])
        XCTAssertEqual(layout.level(of: 2), 0)
    }

    func test_C_SCENE_02_aMirroredLayerOverlapsLikeAnyOther() {
        var mirrored = SceneFixtures.layer(2, x: 50, y: 50, width: 100, height: 100)
        mirrored.transform.m11 = -1  // flipped left to right: its corners go round the other way
        let layout = SceneLayout(
            layers: [SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100), mirrored],
            expanded: [1, 2])
        XCTAssertEqual(layout.level(of: 2), 1)
    }

    func test_C_SCENE_02_aLayerWithoutAreaOverlapsNothing() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, x: 10, y: 10, width: 0, height: 50),
                SceneFixtures.layer(3, x: 10, y: 10, width: 50, height: 50),
            ],
            expanded: [1, 2, 3])
        XCTAssertEqual(layout.level(of: 2), 0)
        XCTAssertEqual(layout.level(of: 3), 1)
    }

    func test_C_SCENE_02_hiddenLayersDoNotRaiseTheLevel() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, x: 0, y: 0, width: 100, height: 100, hidden: true),
                SceneFixtures.layer(3, x: 0, y: 0, width: 100, height: 100),
            ],
            expanded: [1, 2, 3])
        XCTAssertEqual(layout.level(of: 3), 1)
    }

    func test_C_SCENE_02_onlyLayersDrawnBeforeCount() {
        // Layer 2 is drawn after 1 and overlaps it; 1 stays at 0.
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, x: 50, y: 50, width: 100, height: 100),
            ],
            expanded: [1, 2])
        XCTAssertEqual(layout.level(of: 1), 0)
        XCTAssertEqual(layout.level(of: 2), 1)
    }

    func test_C_SCENE_02_theLevelIsOneAboveTheHighestOverlappingLayer() {
        // 3 overlaps 1 (level 0) and 2 (level 1); 4 overlaps only 1.
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 300, height: 100),
                SceneFixtures.layer(2, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(3, x: 50, y: 0, width: 100, height: 100),
                SceneFixtures.layer(4, x: 200, y: 0, width: 100, height: 100),
            ],
            expanded: [1, 2, 3, 4])
        XCTAssertEqual(layout.level(of: 3), 2)
        XCTAssertEqual(layout.level(of: 4), 1)
    }

    func test_C_SCENE_02_rowsOfAListScrolledFarDownOnlyTouch() {
        // A table scrolled far down: rows that share an edge, at coordinates where rounding
        // leaves slivers of a few billionths of a square point between them.
        for (offset, height, degrees) in [
            (50_000.0, 44.3, 0.0), (200_000, 131.0 / 3, 0), (50_000, 44.3, 29),
        ] {
            var layers = [
                SceneLayer(
                    id: 1, parentID: 0, bounds: SceneRect(x: 0, y: offset, width: 393, height: 852),
                    position: ScenePoint(x: 196.5, y: 426),
                    transform: SceneFixtures.rotation(degrees: degrees)),
            ]
            for row in 0..<20 {
                layers.append(
                    SceneLayer(
                        id: UInt64(2 + row), parentID: 1,
                        bounds: SceneRect(x: 0, y: 0, width: 393, height: height),
                        position: ScenePoint(
                            x: 196.5, y: offset + Double(row) * height + height / 2)))
            }
            let layout = SceneLayout(layers: layers, expanded: Set(layers.map(\.id)))
            for row in 0..<20 {
                XCTAssertEqual(
                    layout.level(of: UInt64(2 + row)), 1,
                    "row \(row), scrolled to \(offset), turned \(degrees)°")
            }
        }
    }

    func test_C_SCENE_02_layersInsideACollapsedNodeTakeItsLevel() throws {
        var expanded = SceneFixtures.allIDs
        expanded.remove(2)
        let layout = try fixtureLayout(expanded: expanded)
        XCTAssertEqual(layout.level(of: 1), 0)
        XCTAssertEqual(layout.level(of: 2), 1)
        for id: UInt64 in [3, 4, 6, 7, 8, 9] {
            XCTAssertFalse(layout.isDisplayed(id), "layer \(id)")
            XCTAssertEqual(layout.level(of: id), 1, "layer \(id)")
        }
        XCTAssertNil(layout.level(of: 5))
    }

    func test_C_SCENE_04_theContentBoxHoldsTheDisplayedLayers() throws {
        XCTAssertEqual(try fixtureLayout().contentBox, SceneRect(x: 0, y: 0, width: 393, height: 852))
        XCTAssertNil(SceneLayout(layers: [], expanded: []).contentBox)
    }

    func test_C_SCENE_04_aLayerWithoutAreaDoesNotWidenTheContentBox() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, x: 1000, y: 0, width: 0, height: 50),
            ],
            expanded: [1, 2])
        XCTAssertEqual(layout.contentBox, SceneRect(x: 0, y: 0, width: 100, height: 100))
    }

    // MARK: - C-DET-01: what the display needs

    func test_C_DET_01_eachDrawnLayerNeedsTheKindItIsDrawnWith() throws {
        // Expanded nodes with sublayers are drawn with their solo, leaves with their group.
        // 5 is hidden and 9 has no area: they are not drawn, so they need nothing.
        let layout = try fixtureLayout()
        XCTAssertEqual(layout.neededTextures, [
            TextureNeed(layerID: 1, kind: .solo), TextureNeed(layerID: 2, kind: .solo),
            TextureNeed(layerID: 3, kind: .group), TextureNeed(layerID: 4, kind: .solo),
            TextureNeed(layerID: 6, kind: .solo), TextureNeed(layerID: 7, kind: .group),
            TextureNeed(layerID: 8, kind: .group),
        ])
    }

    func test_C_DET_01_aCollapsedNodeNeedsItsGroupAndItsSubtreeNothing() throws {
        let layout = try fixtureLayout(expanded: SceneFixtures.allIDs.subtracting([2]))
        XCTAssertEqual(layout.neededTextures, [
            TextureNeed(layerID: 1, kind: .solo), TextureNeed(layerID: 2, kind: .group),
        ])
    }

    func test_C_DET_01_swappingTexturesDrawsWhatALayoutBuiltWithThemDraws() throws {
        let textures: [UInt64: LayerTextures] = [
            3: LayerTextures(group: SceneFixtures.group(3)),
            4: LayerTextures(solo: SceneFixtures.solo(4), group: SceneFixtures.group(4)),
            6: LayerTextures(group: SceneFixtures.group(6)),
        ]
        let viewport = Viewport(width: 480, height: 900)
        for expanded in [SceneFixtures.allIDs, SceneFixtures.allIDs.subtracting([4, 6])] {
            let direct = try fixtureLayout(expanded: expanded, textures: textures)
            let swapped = try fixtureLayout(expanded: expanded).replacingTextures(textures)
            for id in UInt64(1)...9 {
                XCTAssertEqual(swapped.texture(of: id), direct.texture(of: id), "layer \(id)")
            }
            for camera in [Camera.flat, Camera.standard3D] {
                XCTAssertEqual(
                    swapped.project(camera: camera, viewport: viewport, selected: 3, hovered: 4),
                    direct.project(camera: camera, viewport: viewport, selected: 3, hovered: 4))
            }
            XCTAssertEqual(swapped.neededTextures, direct.neededTextures)
        }

        // Swapping in nothing takes every image away.
        let bare = try fixtureLayout(textures: textures).replacingTextures([:])
        for id in UInt64(1)...9 {
            XCTAssertNil(bare.texture(of: id), "layer \(id)")
        }
    }

    func test_C_SCENE_03_anExpandedLeafUsesItsGroupEvenWithASolo() throws {
        // P-DET-04: a leaf's solo and group are the same picture. The group is the kind asked
        // for, so it is the one kept fresh; an older solo must not cover it.
        let layout = try fixtureLayout(textures: [
            3: LayerTextures(solo: SceneFixtures.solo(3), group: SceneFixtures.group(3)),
        ])
        XCTAssertEqual(layout.texture(of: 3), SceneFixtures.group(3))
    }

    // MARK: - C-HIER-05: a focused subtree

    func test_C_HIER_05_onlyTheSubtreeIsDisplayed() throws {
        let layout = try fixtureLayout(focus: 6)
        XCTAssertEqual(
            [1, 2, 3, 4, 5, 6, 7, 8, 9].filter { layout.isDisplayed($0) }, [6, 7] as [UInt64])
        XCTAssertNil(layout.level(of: 3), "a layer outside the focus has no level")
        XCTAssertEqual(layout.neededTextures, [
            TextureNeed(layerID: 6, kind: .solo), TextureNeed(layerID: 7, kind: .group),
        ])
    }

    func test_C_HIER_05_aFocusedSubtreeKeepsItsPlaceInTheWindow() throws {
        let whole = try fixtureLayout()
        for (focus, id) in [(6, 7), (4, 4), (2, 3)] as [(UInt64, UInt64)] {
            XCTAssertEqual(
                try fixtureLayout(focus: focus).quad(of: id), whole.quad(of: id),
                "layer \(id) focused on \(focus)")
        }
    }

    func test_C_HIER_05_levelsStartAgainInTheSubtree() throws {
        let layout = try fixtureLayout(focus: 6)
        XCTAssertEqual(layout.level(of: 6), 0)
        XCTAssertEqual(layout.level(of: 7), 1)
    }

    func test_C_HIER_05_theContentBoxHoldsTheSubtree() throws {
        XCTAssertEqual(
            try fixtureLayout(focus: 6).contentBox,
            SceneRect(x: 46.5, y: 500, width: 300, height: 200))
    }

    func test_C_HIER_05_onlyTheSubtreeIsDrawnAndHit() throws {
        let layout = try fixtureLayout(focus: 6)
        let viewport = Viewport(width: 400, height: 300)
        let list = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(list.items.map(\.layerID), [6, 7])
        // Layer 6 fills the viewport at 1.2 times, centred: window point (x, y) is at
        // (200 + (x − 196.5) × 1.2, 150 + (y − 600) × 1.2).
        let hit = { layout.hitTest(point: $0, camera: .flat, viewport: viewport) }
        XCTAssertEqual(hit(ScenePoint(x: 200, y: 90)), 7, "the middle of layer 7")
        XCTAssertEqual(hit(ScenePoint(x: 200, y: 200)), 6)
        // Left of layer 6, where the window and layer 2 would be.
        XCTAssertNil(hit(ScenePoint(x: 10, y: 150)))
    }

    func test_C_HIER_05_theRootOfTheFocusIsNotInsideItsCollapsedParent() throws {
        var expanded = SceneFixtures.allIDs
        expanded.remove(2)
        let layout = try fixtureLayout(expanded: expanded, focus: 6)
        XCTAssertTrue(layout.isDisplayed(6))
        XCTAssertTrue(layout.isDisplayed(7))
    }

    func test_C_HIER_05_aCollapsedRootOfTheFocusIsDrawnWithItsGroup() throws {
        let textures: [UInt64: LayerTextures] = [
            6: LayerTextures(solo: SceneFixtures.solo(6), group: SceneFixtures.group(6)),
        ]
        var expanded = SceneFixtures.allIDs
        expanded.remove(6)
        let layout = try fixtureLayout(expanded: expanded, textures: textures, focus: 6)
        XCTAssertEqual(layout.texture(of: 6), SceneFixtures.group(6))
        XCTAssertFalse(layout.isDisplayed(7))
        XCTAssertEqual(layout.level(of: 7), 0, "inside the collapsed root, on its level")
    }

    func test_C_HIER_05_aHiddenAncestorStillHidesTheSubtree() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 50, height: 50, hidden: true),
                SceneFixtures.layer(3, parent: 2, x: 0, y: 0, width: 10, height: 10),
            ],
            expanded: [1, 2, 3], focus: 3)
        XCTAssertFalse(layout.isDisplayed(3))
        XCTAssertNil(layout.contentBox)
    }

    func test_C_HIER_05_theFocusKeepsTheOpacityOfItsAncestors() {
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100, opacity: 0.5),
                SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 50, height: 50),
            ],
            expanded: [1, 2], focus: 2)
        XCTAssertEqual(layout.opacity(of: 2), 0.5)
    }

    func test_C_HIER_05_aFocusThatIsNotThereIsNoFocus() throws {
        let layout = try fixtureLayout(focus: 42)
        XCTAssertEqual(layout.neededTextures, try fixtureLayout().neededTextures)
    }

    // MARK: - C-PREV-08: layers that cannot be seen

    func test_C_PREV_08_aHiddenLayerIsDisplayedAsAGhost() throws {
        let layout = try fixtureLayout(showsHidden: true)
        XCTAssertTrue(layout.isDisplayed(5))
        XCTAssertTrue(layout.isGhost(5))
        XCTAssertFalse(layout.isGhost(4))
        XCTAssertNotNil(layout.level(of: 5))
        XCTAssertTrue(layout.neededTextures.contains(TextureNeed(layerID: 5, kind: .group)))
    }

    func test_C_PREV_08_withoutTheSwitchNothingChanges() throws {
        let off = try fixtureLayout()
        XCTAssertFalse(off.isDisplayed(5))
        XCTAssertFalse(off.isGhost(5))
        XCTAssertFalse(off.neededTextures.contains { $0.layerID == 5 })
    }

    func test_C_PREV_08_aGhostIsDrawnAsIfItWereShown() {
        // 2 is transparent, 3 inside it has 0.5 of its own, 4 is hidden inside a parent of
        // 0.8: drawn at what each would be if it were shown.
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
                SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 80, height: 80, opacity: 0),
                SceneFixtures.layer(3, parent: 2, x: 0, y: 0, width: 40, height: 40, opacity: 0.5),
                SceneFixtures.layer(
                    5, parent: 1, x: 50, y: 50, width: 40, height: 40, opacity: 0.8),
                SceneFixtures.layer(4, parent: 5, x: 0, y: 0, width: 20, height: 20, hidden: true),
            ],
            expanded: [1, 2, 3, 4, 5], showsHidden: true)
        let list = layout.project(
            camera: .flat, viewport: Viewport(width: 200, height: 200), selected: nil, hovered: nil)
        func item(_ id: UInt64) -> DrawItem? { list.items.first { $0.layerID == id } }
        XCTAssertEqual(item(1)?.isGhost, false)
        XCTAssertEqual(item(2)?.isGhost, true)
        XCTAssertEqual(item(2)?.opacity, 1)
        XCTAssertEqual(item(3)?.isGhost, true)
        XCTAssertEqual(item(3)?.opacity, 0.5)
        XCTAssertEqual(item(4)?.isGhost, true)
        XCTAssertEqual(item(4)?.opacity ?? 0, 0.8, accuracy: 1e-12)
        XCTAssertEqual(item(5)?.isGhost, false)
        XCTAssertEqual(layout.opacity(of: 3), 0, "the opacity it really has is unchanged")
    }

    func test_C_PREV_08_aGhostCanBeHit() throws {
        let layout = try fixtureLayout(showsHidden: true)
        let viewport = Viewport(width: 480, height: 900)
        let list = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        let center = try XCTUnwrap(list.items.first { $0.layerID == 5 }).center
        XCTAssertEqual(list.layer(at: center), 5)
    }
}
