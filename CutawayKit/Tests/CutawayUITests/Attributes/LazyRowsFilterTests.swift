import AppKit
import CutawayWire
import XCTest

@testable import CutawayUI

/// The filter over a part built page by page (C-ATTR-14, C-SCALE-03): a compound row made to
/// know what it says is built in its own item's place, never in another's, and is let go of
/// once the filter no longer lists its item.
@MainActor
final class LazyRowsFilterTests: XCTestCase {
    /// A row that remembers the item it was made for and matches by its title.
    private final class MadeRow: NSView, AttributeListRow {
        let item: AttributeClusters.Item
        let title: String
        var attributeCount: Int { LazyRowsView.attributeCount(of: item) }

        init(_ item: AttributeClusters.Item) {
            self.item = item
            title = item.attributes.first?.title ?? ""
            super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func matches(_ filter: String) -> Bool { title.localizedCaseInsensitiveContains(filter) }
        func highlight(_ filter: String?) {}
    }

    private final class Weak {
        weak var row: MadeRow?

        init(_ row: MadeRow) {
            self.row = row
        }
    }

    private static func single(_ title: String) -> AttributeClusters.Item {
        .single(Attribute(id: title, title: title, value: .double(1), editable: false, valueKind: .double))
    }

    private static func cluster(_ title: String) -> AttributeClusters.Item {
        var row = AttributeClusters.Row(kind: .border, members: [:])
        row.add(Attribute(id: title, title: title, value: .double(1), editable: false, valueKind: .double), as: "width")
        return .cluster(row)
    }

    /// More than a page: a compound row "Keep A" second, "Keep B" fourth, the rest dropped by
    /// the filter "keep", which moves B to where A was.
    private static let items: [AttributeClusters.Item] =
        [single("Drop 0"), cluster("Keep A"), single("Drop 2"), cluster("Keep B")]
            + (4..<(LazyRowsView.pageSize + 5)).map { single("Drop \($0)") }

    private var made: [Weak] = []

    private func makeLazy() -> (LazyRowsView, NSView) {
        let lazy = LazyRowsView(items: Self.items) { [weak self] item in
            let row = MadeRow(item)
            self?.made.append(Weak(row))
            return row
        }
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 4_000))
        lazy.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(lazy)
        NSLayoutConstraint.activate([
            lazy.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            lazy.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            lazy.topAnchor.constraint(equalTo: document.topAnchor),
        ])
        return (lazy, document)
    }

    private func arrangeAll(_ lazy: LazyRowsView, in document: NSView) {
        document.layoutSubtreeIfNeeded()
        let everywhere = document.bounds.insetBy(dx: -10_000, dy: -10_000)
        _ = lazy.arrange(near: everywhere, keep: everywhere, in: document) { _ in false }
    }

    func test_C_ATTR_14_aCompoundRowMadeForTheFilterIsBuiltInItsOwnPlace() throws {
        let (lazy, document) = makeLazy()
        lazy.apply(filter: "keep")
        XCTAssertEqual(lazy.items, [Self.items[1], Self.items[3]])
        arrangeAll(lazy, in: document)

        let built = lazy.built
        XCTAssertEqual(built.count, 2)
        for (item, row) in built {
            let made = try XCTUnwrap(row as? MadeRow)
            XCTAssertEqual(made.item, item, "the row of \(made.title) in the place of another item")
        }
        // Each compound row made once: the one made for the filter is the one built.
        let clusters = made.compactMap(\.row).filter { if case .cluster = $0.item { true } else { false } }
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(Set(clusters.map(\.title)), ["Keep A", "Keep B"])
    }

    func test_C_ATTR_14_rowsMadeForAFilterAreLetGoOfWhenItsItemsAreNoLongerListed() {
        let (lazy, _) = makeLazy()
        autoreleasepool {
            lazy.apply(filter: "keep a")
            XCTAssertEqual(lazy.items, [Self.items[1]])
        }
        // B's row said it does not match: nothing will build it.
        XCTAssertEqual(made.compactMap(\.row).map(\.title), ["Keep A"])

        autoreleasepool {
            lazy.apply(filter: "drop 0")
            XCTAssertEqual(lazy.items, [Self.items[0]])
        }
        XCTAssertEqual(made.compactMap(\.row).map(\.title), [], "no compound row listed: none kept")
    }
}
