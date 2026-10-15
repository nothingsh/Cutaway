import AppKit
import CutawayModel
import CutawayWire
import DeclarativeAppKit

/// The cases of an enum in an attribute editor: segments or a menu (C-ATTR-05, C-ATTR-22).
extension AttributeEditorView {
    /// The longest name a segment shows (C-ATTR-22).
    static let segmentNameLength = 10

    /// Whether an enum's cases fit a segmented control (C-ATTR-22): two to four short names,
    /// each with its raw value, the current one among them. Only the cases decide, never the
    /// attribute's ID (C-ATTR-03).
    static func fitsSegments(_ value: AttributeValue?) -> Bool {
        guard case .enumeration(let enumeration) = value else { return false }
        return (2...4).contains(enumeration.cases.count)
            && enumeration.cases.allSatisfy { $0.count <= segmentNameLength }
            && enumeration.caseValues.count == enumeration.cases.count
            && enumeration.caseValues.contains(enumeration.value)
    }

    /// The cases the app gave last, kept from a value that has them: one on its way carries its
    /// raw value alone (P-SET-02).
    private func keepCases(of enumeration: EnumValue) {
        if !enumeration.cases.isEmpty, enumeration.caseValues.count == enumeration.cases.count {
            cases = enumeration.cases
            caseValues = enumeration.caseValues
        }
    }

    func enumContent(_ value: AttributeValue?) -> NSView {
        Self.fitsSegments(value) ? segmentedContent() : popUpContent()
    }

    private func segmentedContent() -> NSView {
        let control = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: self,
                                         action: #selector(segmentChosen(_:)))
            .controlSize(.small)
            .font(.systemFont(ofSize: 11))
            .accessibilityIdentifier(Self.segmentedIdentifier)
            .accessibilityLabel(title)
        showValue = { [weak self] value in
            guard let self, case .enumeration(let enumeration) = value else { return }
            self.keepCases(of: enumeration)
            if control.segmentCount != self.cases.count {
                control.segmentCount = self.cases.count
            }
            for (index, name) in self.cases.enumerated() where control.label(forSegment: index) != name {
                control.setLabel(name, forSegment: index)
            }
            control.selectedSegment = self.caseValues.firstIndex(of: enumeration.value) ?? -1
        }
        let badge = makeBadge()
        return HStack(alignment: .center, spacing: 6) {
            control
            badge
            Spacer()
        }
    }

    @objc func segmentChosen(_ sender: NSSegmentedControl) {
        send(caseAt: sender.selectedSegment)
    }

    private func popUpContent() -> NSView {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            .controlSize(.small)
            .font(.systemFont(ofSize: 12))
            .accessibilityIdentifier(Self.popUpIdentifier)
            .accessibilityLabel(title)
            .configure {
                $0.target = self
                $0.action = #selector(caseChosen(_:))
                // In a field's box with a chevron of its own, as in the design.
                $0.isBordered = false
                ($0.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
            }
        showValue = { [weak self] value in
            guard let self, case .enumeration(let enumeration) = value else { return }
            self.keepCases(of: enumeration)
            if popUp.itemTitles != self.cases {
                popUp.removeAllItems()
                popUp.addItems(withTitles: self.cases)
            }
            if let index = self.caseValues.firstIndex(of: enumeration.value) {
                popUp.selectItem(at: index)
            } else {
                // A case the menu does not have (C-ATTR-09): its name, or its raw value, as
                // an item of its own that cannot be chosen again.
                let item = NSMenuItem(
                    title: enumeration.caseName ?? String(enumeration.value), action: nil,
                    keyEquivalent: "")
                item.isEnabled = false
                popUp.menu?.addItem(item)
                popUp.select(item)
            }
        }
        let badge = makeBadge()
        let box = Self.fieldBox()
        box.contentView?.addHStack(alignment: .center, spacing: 4) {
            popUp
            NSImageView()
                .image(Theme.symbol("chevron.up.chevron.down", size: 9, weight: .semibold))
                .contentTintColor(.secondaryLabelColor)
                .configure { $0.setContentHuggingPriority(.required, for: .horizontal) }
        }
        .padding(top: 0, leading: 2, bottom: 0, trailing: 7)
        return box
            .frame(height: Self.fieldHeight)
            .overlay(alignment: .trailing, offset: CGPoint(x: -20, y: 0)) { badge }
    }

    /// Sends the chosen case by its raw value only (P-SET-02).
    @objc func caseChosen(_ sender: NSPopUpButton) {
        send(caseAt: sender.indexOfSelectedItem)
    }

    private func send(caseAt index: Int) {
        guard case .enumeration(let enumeration) = value, caseValues.indices.contains(index)
        else { return }
        let raw = caseValues[index]
        guard raw != enumeration.value else { return }
        activeBadge = nil
        onSet(.enumeration(EnumValue(value: raw, cases: [], caseName: nil)), false)
    }
}
