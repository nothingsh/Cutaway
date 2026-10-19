import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-SRC-06: the LLDB commands for a layer, from its addresses (protocol 1.1, P-HIER-14).
final class LLDBCommandsTests: XCTestCase {
    private func node(_ id: UInt64) throws -> LayerNode {
        try XCTUnwrap(try Fixtures.hierarchy().nodes.first { $0.id == id })
    }

    func test_C_SRC_06_theCommandsForNode3AreExactlyTheseCharacters() throws {
        let commands = LLDBCommands(try node(3))
        XCTAssertEqual(commands.printObject, "expr -l objc -O -- (id)0x103806e00")
        XCTAssertEqual(
            commands.breakOnFrameChanges,
            """
            breakpoint set -n "-[CALayer setPosition:]" -c '(void *)$arg1 == (void *)0x600003b4c080'
            breakpoint set -n "-[CALayer setBounds:]" -c '(void *)$arg1 == (void *)0x600003b4c080'
            """)
        XCTAssertTrue(commands.isAvailable)
    }

    func test_C_SRC_06_aLayerWithoutAViewIsPrintedByItsLayer() throws {
        let node5 = try node(5)
        XCTAssertNil(node5.viewAddress)
        let layer = try XCTUnwrap(node5.layerAddress)
        let commands = LLDBCommands(node5)
        XCTAssertEqual(commands.printObject, "expr -l objc -O -- (id)0x" + String(layer, radix: 16))
        XCTAssertNotNil(commands.breakOnFrameChanges)
    }

    func test_C_SRC_06_withoutAddressesThereIsNothingToCopy() throws {
        let bare = Fixtures.withoutProtocol11(try Fixtures.hierarchy()).nodes.first { $0.id == 3 }
        let commands = LLDBCommands(try XCTUnwrap(bare))
        XCTAssertNil(commands.printObject)
        XCTAssertNil(commands.breakOnFrameChanges)
        XCTAssertFalse(commands.isAvailable)

        // A view's address alone prints the view, but there is no layer to watch.
        var viewOnly = try node(3)
        viewOnly.layerAddress = nil
        XCTAssertEqual(LLDBCommands(viewOnly).printObject, "expr -l objc -O -- (id)0x103806e00")
        XCTAssertNil(LLDBCommands(viewOnly).breakOnFrameChanges)
    }
}
