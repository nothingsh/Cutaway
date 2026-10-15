import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-HIER-11: the icons as drawn — every glyph is there, and a square is filled for the app's
/// own class and outlined for the system's.
final class LayerIconImageTests: XCTestCase {
    @MainActor
    func test_C_HIER_11_aGlyphIsTintedOnceForEachColour() throws {
        let white = try XCTUnwrap(LayerIconImage.tintedGlyph(.button, .white))
        XCTAssertTrue(white === LayerIconImage.tintedGlyph(.button, .white))
        XCTAssertFalse(white === LayerIconImage.tintedGlyph(.button, .category(.control)))
        // The squares that share a glyph and a colour share the tinted glyph.
        XCTAssertEqual(
            LayerIconImage.tint(of: LayerIcon(.control, .button, isAppClass: true), isSelected: false),
            LayerIconImage.tint(of: LayerIcon(.text, .label, isAppClass: true), isSelected: true))
    }
}
