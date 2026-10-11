import XCTest

@testable import CutawayScene

/// The levels found through the per-level grids are those of C-SCENE-02 itself: one above the
/// highest level among the displayed layers drawn before that overlap, or 0. The definition is
/// worked out here by comparing every pair, on scenes made from a seed.
final class LevelSearchTests: XCTestCase {
    /// SplitMix64: the same numbers for the same seed on every machine.
    private struct Numbers {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    /// Layers of all sizes in a tree, some turned, some hidden, some without area, a few
    /// outside the rest; every parent before its children.
    private func scene(seed: UInt64, count: Int) -> [SceneLayer] {
        var numbers = Numbers(state: seed)
        var layers: [SceneLayer] = []
        for index in 0..<count {
            let id = UInt64(index + 1)
            let parent: UInt64 = index == 0 ? 0 : UInt64(1 + numbers.below(index))
            let big = numbers.below(10) == 0
            let width = big ? 200 + numbers.unit() * 400 : numbers.unit() * 60
            let height = numbers.below(15) == 0 ? 0 : (big ? 200 + numbers.unit() * 600 : numbers.unit() * 60)
            let far = numbers.below(50) == 0 ? 5_000.0 : 0
            let angle = numbers.below(5) == 0 ? numbers.unit() * .pi : 0
            var transform = SceneTransform.identity
            transform.m11 = cos(angle)
            transform.m12 = sin(angle)
            transform.m21 = -sin(angle)
            transform.m22 = cos(angle)
            layers.append(SceneLayer(
                id: id, parentID: parent,
                bounds: SceneRect(x: 0, y: 0, width: width, height: height),
                position: ScenePoint(x: numbers.unit() * 400 + far, y: numbers.unit() * 800),
                transform: transform, isHidden: numbers.below(30) == 0))
        }
        return layers
    }

    /// C-SCENE-02 by its words.
    private func definedLevels(_ layout: SceneLayout) -> [UInt64: Int] {
        var levels: [UInt64: Int] = [:]
        var earlier: [Int] = []
        for index in layout.displayed where layout.entries[index].hasArea {
            let outline = layout.entries[index].quad.outline
            let box = layout.entries[index].box
            var level = 0
            // Polygons whose boxes do not touch cannot overlap.
            for other in earlier
                where layout.entries[other].box.overlaps(box)
                && Polygon.overlap(outline, layout.entries[other].quad.outline)
            {
                level = max(level, layout.entries[other].level + 1)
            }
            levels[layout.entries[index].layer.id] = level
            earlier.append(index)
        }
        return levels
    }

    func test_C_SCENE_02_theGridsFindTheLevelsTheDefinitionGives() {
        for seed in UInt64(1)...40 {
            let layers = scene(seed: seed, count: 400)
            let ids = layers.map(\.id)
            // Everything expanded, and every third node collapsed.
            for expanded in [Set(ids), Set(ids.filter { $0 % 3 != 0 })] {
                let layout = SceneLayout(layers: layers, expanded: expanded)
                let defined = definedLevels(layout)
                for (id, level) in defined {
                    XCTAssertEqual(layout.level(of: id), level, "seed \(seed), layer \(id)")
                }
            }
        }
    }
}
