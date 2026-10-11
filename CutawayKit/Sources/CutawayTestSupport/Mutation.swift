import Foundation

/// SplitMix64: the same seed always gives the same numbers, which the system generator
/// cannot promise. For tests that must fail the same way every time they are run (C-WIRE-09).
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// How much the mutation tests do: a fixed seed by default, so that the checks feed the same
/// inputs every time; `CUTAWAY_FUZZ_SEED` and `CUTAWAY_FUZZ_ITERATIONS` change them for a
/// longer run on one machine.
public struct FuzzSettings: Sendable {
    public var seed: UInt64
    /// Random mutations of each input.
    public var iterations: Int

    public static func current(defaultIterations: Int) -> Self {
        let environment = ProcessInfo.processInfo.environment
        return Self(
            seed: environment["CUTAWAY_FUZZ_SEED"].flatMap { UInt64($0) } ?? 0x4375_7461_7761_7931,
            iterations: environment["CUTAWAY_FUZZ_ITERATIONS"].flatMap { Int($0) }
                ?? defaultIterations)
    }
}

/// One change to a run of bytes, carrying all it takes to make it again: its description
/// goes into a failure message.
public enum Mutation: Equatable, Sendable, CustomStringConvertible {
    /// The first `length` bytes only.
    case truncated(to: Int)
    /// One byte replaced.
    case byte(at: Int, set: UInt8)
    /// Bytes overwritten, inserted or removed, 1 to 16 at a time, in one to four places,
    /// all chosen by a generator seeded with `seed` and `index`.
    case random(seed: UInt64, index: Int)

    public var description: String {
        switch self {
        case .truncated(let length): "truncated to \(length) bytes"
        case .byte(let offset, let value): "byte \(offset) set to \(value)"
        case .random(let seed, let index): "random mutation \(index) of seed \(seed)"
        }
    }

    /// Every truncation, every byte set to 0x00, 0xFF and its complement (where that changes
    /// it), then `randomCount` random mutations.
    public static func all(of bytes: Data, randomCount: Int, seed: UInt64) -> [Self] {
        var mutations = (0..<bytes.count).map { Self.truncated(to: $0) }
        for (offset, value) in bytes.enumerated() {
            // In this order every time: a Set would iterate differently in each process, and
            // a sample taken by position would then differ from run to run.
            var replacements: [UInt8] = []
            for replacement: UInt8 in [0x00, 0xFF, ~value]
                where replacement != value && !replacements.contains(replacement)
            {
                replacements.append(replacement)
            }
            mutations += replacements.map { .byte(at: offset, set: $0) }
        }
        mutations += (0..<randomCount).map { .random(seed: seed, index: $0) }
        return mutations
    }

    /// `bytes` with this mutation made.
    public func applied(to bytes: Data) -> Data {
        var bytes = Data(bytes)
        switch self {
        case .truncated(let length):
            return bytes.prefix(length)
        case .byte(let offset, let value):
            bytes[offset] = value
            return bytes
        case .random(let seed, let index):
            var generator = SeededGenerator(seed: seed ^ UInt64(index) &* 0x2545_F491_4F6C_DD1D)
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                let count = Int.random(in: 1...16, using: &generator)
                let offset = Int.random(in: 0...bytes.count, using: &generator)
                let noise = Data((0..<count).map { _ in
                    UInt8.random(in: 0...255, using: &generator)
                })
                switch Int.random(in: 0..<3, using: &generator) {
                case 0:
                    let end = min(offset + count, bytes.count)
                    bytes.replaceSubrange(offset..<end, with: noise.prefix(end - offset))
                case 1:
                    bytes.insert(contentsOf: noise, at: offset)
                default:
                    bytes.removeSubrange(offset..<min(offset + count, bytes.count))
                }
            }
            return bytes
        }
    }
}

extension SeededGenerator {
    /// Random bytes cut into random pieces: what a stream reader might be handed.
    public mutating func randomPieces(totalLength: Int, longestPiece: Int) -> [Data] {
        var pieces: [Data] = []
        var left = totalLength
        while left > 0 {
            let count = Int.random(in: 1...min(longestPiece, left), using: &self)
            pieces.append(Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &self) }))
            left -= count
        }
        return pieces
    }
}
