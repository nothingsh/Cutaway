import AppKit
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-WIRE-09, one step further for attributes: whatever values a mutated chunk that still
/// decodes carries, they are written and shown without a crash.
@MainActor
final class DecodedAttributeMutationTests: XCTestCase {
    private let settings = FuzzSettings.current(defaultIterations: 300)

    func test_C_WIRE_09_mutatedAttributesThatDecodeAreFormattedWithoutCrashing() throws {
        var shown = 0
        for file in ["02-s2c-chunk-0.bin", "03-s2c-chunk-1.bin"] {
            let payload = try Fixtures.data(scenario: "layer-details", file: file)
            // Making views is slow: every 4th of the truncations and byte changes, which still
            // reaches each attribute's bytes, and all the random mutations.
            let mutations = Mutation.all(
                of: payload, randomCount: settings.iterations, seed: settings.seed
            ).enumerated().filter { index, mutation in
                if case .random = mutation { return true }
                return index % 4 == 0
            }.map(\.element)
            for mutation in mutations {
                guard let frame = try? FrameCodec.decode(mutation.applied(to: payload)),
                      case .layerDetailsChunk(let chunk) = frame.body
                else { continue }
                for attribute in chunk.details.flatMap(\.attributeGroups).flatMap(\.attributes) {
                    _ = AttributeText.text(of: attribute.value)
                    // Making the view formats every part of the value; laying it out is
                    // left to the panel's own tests, which would make this run too long.
                    _ = AttributeValueView(value: attribute.value)
                    shown += 1
                }
            }
        }
        XCTAssertGreaterThan(shown, 500, "attributes of mutated chunks that decoded")
    }
}
