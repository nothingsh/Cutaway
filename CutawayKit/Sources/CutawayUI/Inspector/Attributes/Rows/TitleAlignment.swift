import AppKit

/// How a title stands beside its value (C-ATTR-12), as in the design: centred against a value
/// one field tall, and beside a taller value at its top, moved down so that its first line is
/// centred on the value's first line. The value says whether it is taller than a field
/// (`AttributeEditorView.isTall`), and when that changes (a text grows, a matrix opens).
@MainActor
enum TitleAlignment {
    /// How far the title's first line is below the top of a field it is centred on.
    static let firstLineInset = (AttributeEditorView.fieldHeight
        - WrappingTitleField.lineHeight(of: Theme.Font.caption)) / 2

    /// Aligns a line's title column with its value.
    static func apply(_ line: NSStackView, title: NSStackView, isTall: Bool) {
        let alignment: NSLayoutConstraint.Attribute = isTall ? .top : .centerY
        let inset = isTall ? firstLineInset : 0
        guard line.alignment != alignment || title.edgeInsets.top != inset else { return }
        line.alignment = alignment
        title.edgeInsets.top = inset
    }
}
