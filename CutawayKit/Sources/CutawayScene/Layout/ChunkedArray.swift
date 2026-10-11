/// An array held in chunks of 64 elements. A copy changed in a few places copies the chunks
/// it changes and the list of chunks, not every element: a layout with new images for a few
/// layers costs what those layers cost (C-SCALE-02).
struct ChunkedArray<Element: Sendable>: Sendable {
    private static var shift: Int { 6 }
    private static var mask: Int { (1 << shift) - 1 }

    private var chunks: [[Element]]
    let count: Int

    init(_ elements: [Element]) {
        let size = 1 << Self.shift
        chunks = stride(from: 0, to: elements.count, by: size).map {
            Array(elements[$0..<min($0 + size, elements.count)])
        }
        count = elements.count
    }

    subscript(index: Int) -> Element {
        get { chunks[index >> Self.shift][index & Self.mask] }
        set { chunks[index >> Self.shift][index & Self.mask] = newValue }
    }

    /// How many elements and chunk references were copied to make this from `other`: the
    /// elements of each chunk not shared with it, and the list of chunks when that is not
    /// shared. For tests.
    func copiedElements(since other: Self) -> Int {
        guard !Self.sameStorage(chunks, other.chunks) else { return 0 }
        var copied = chunks.count
        for (mine, theirs) in zip(chunks, other.chunks) where !Self.sameStorage(mine, theirs) {
            copied += mine.count
        }
        return copied
    }

    private static func sameStorage<T>(_ a: [T], _ b: [T]) -> Bool {
        a.withUnsafeBufferPointer { a in
            b.withUnsafeBufferPointer { b in a.baseAddress == b.baseAddress }
        }
    }
}
