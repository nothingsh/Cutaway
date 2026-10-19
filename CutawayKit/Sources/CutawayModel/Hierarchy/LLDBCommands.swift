import CutawayWire

/// The LLDB commands to copy for a layer (C-SRC-06), from the addresses the server gave
/// (P-HIER-14): nil where the address a command needs is missing. Addresses are written as
/// the panel writes them (C-ATTR-11).
public struct LLDBCommands: Equatable, Sendable {
    /// Prints the view, or the layer when there is no view.
    public var printObject: String?
    /// Two breakpoints that stop when the layer's position or bounds are set: its frame.
    public var breakOnFrameChanges: String?

    public init(_ node: LayerNode) {
        printObject = (node.viewAddress ?? node.layerAddress).map {
            "expr -l objc -O -- (id)" + Self.address($0)
        }
        breakOnFrameChanges = node.layerAddress.map { address in
            ["setPosition:", "setBounds:"].map { selector in
                "breakpoint set -n \"-[CALayer \(selector)]\" -c '(void *)$arg1 == (void *)\(Self.address(address))'"
            }.joined(separator: "\n")
        }
    }

    /// Whether there is anything to copy.
    public var isAvailable: Bool { printObject != nil || breakOnFrameChanges != nil }

    /// "0x" and lowercase hexadecimal, not padded.
    private static func address(_ address: UInt64) -> String {
        "0x" + String(address, radix: 16)
    }
}
