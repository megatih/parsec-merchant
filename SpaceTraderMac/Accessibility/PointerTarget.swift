// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// UI-PTR-002: the minimum pointer and touch target.
nonisolated enum PointerTarget {
    /// Points per axis (HIG, Touch on Mac: "make tap targets bigger, not the controls themselves").
    static let minimum: CGFloat = 36
}

private struct PointerTargetModifier: ViewModifier {
    let minimum: CGFloat

    func body(content: Content) -> some View {
        content
            // A real frame, not only a hit shape: XCUITest and assistive tools measure the accessibility frame.
            .frame(minWidth: minimum, minHeight: minimum)
            .contentShape(Rectangle())
    }
}

/// UI-PTR-003: hover feedback of a tappable card or row. It never changes layout and reveals nothing.
private struct HoverHighlightModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.accentColor.opacity(hovering && isEnabled ? HoverHighlight.opacity : 0))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onHover { hovering = $0 }
    }
}

nonisolated enum HoverHighlight {
    /// The tint of a hovered card or row.
    static let opacity = 0.12
}

extension View {
    /// UI-PTR-002: gives a custom interactive element a real frame of at least `minimum` points on each axis; the visible
    /// chrome keeps its size inside it. Put it inside a button's label, so the whole frame presses the button.
    func pointerTarget(minimum: CGFloat = PointerTarget.minimum) -> some View {
        modifier(PointerTargetModifier(minimum: minimum))
    }

    /// UI-PTR-003: the card or row reacts to the pointer before the click.
    func hoverHighlight(cornerRadius: CGFloat = 8, isEnabled: Bool = true) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius, isEnabled: isEnabled))
    }
}

/// UI-PTR-015: the step of a money slider: the range in at most 100 steps, rounded up to 1, 10, 100, 1,000… credits, so a
/// drag reaches every useful value. The text field beside the slider still takes any amount.
nonisolated enum BankSlider {
    static func step(limit: Int) -> Int {
        var step = 1
        while limit / step > 100 { step *= 10 }
        return step
    }
}

/// UI-PTR-014: the quantity chips of a sheet's stepper: 1, 5 and All.
nonisolated enum SheetChip: Int, CaseIterable, Sendable {
    case one, five, all

    func quantity(in range: ClosedRange<Int>) -> Int {
        switch self {
        case .one: min(max(1, range.lowerBound), range.upperBound)
        case .five: min(max(5, range.lowerBound), range.upperBound)
        case .all: range.upperBound
        }
    }

    var idSuffix: String {
        switch self {
        case .one: "1"
        case .five: "5"
        case .all: "all"
        }
    }
}

/// UI-PTR-014: quantity chips beside a stepper; a tap sets the stepper's value.
struct QuantityChips: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// The identifier prefix; chips are `<prefix>.chip.<1|5|all>`.
    let idPrefix: String
    var isEnabled = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SheetChip.allCases, id: \.self) { chip in
                Button {
                    value = chip.quantity(in: range)
                } label: {
                    Text(Self.title(chip)).monospacedDigit().pointerTarget()
                }
                .buttonStyle(.bordered)
                .disabled(!isEnabled)
                .help(Text(Self.help(chip)))
                .accessibilityLabel(Text(Self.help(chip)))
                .accessibilityIdentifier(AXID.quantityChip(idPrefix, chip))
            }
        }
    }

    static func title(_ chip: SheetChip) -> String {
        switch chip {
        case .one: String(localized: "1")
        case .five: String(localized: "5")
        case .all: String(localized: "All")
        }
    }

    static func help(_ chip: SheetChip) -> String {
        switch chip {
        case .one: String(localized: "Set the quantity to 1")
        case .five: String(localized: "Set the quantity to 5")
        case .all: String(localized: "Set the quantity to the most possible")
        }
    }
}

extension AXID {
    nonisolated static func quantityChip(_ prefix: String, _ chip: SheetChip) -> String { "\(prefix).chip.\(chip.idSuffix)" }
}
