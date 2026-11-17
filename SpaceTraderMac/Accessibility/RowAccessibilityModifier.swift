// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// A11Y-007: gives a compound row (a container of its own controls) its label, value and custom actions, so VoiceOver
/// users need not enter the cells. Apply after `.accessibilityElement(children: .contain)`.
struct RowAccessibilityModifier: ViewModifier {
    let row: RowAccessibility
    let perform: (RowAction.Kind) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(Text(verbatim: row.label))
            .accessibilityValue(Text(verbatim: row.value))
            .accessibilityActions {
                ForEach(row.actions) { action in
                    Button(action.name) { perform(action.kind) }
                }
            }
    }
}

/// A leading-aligned `LazyVStack` (spacing 6) that is a labelled accessibility container (A11Y-029).
struct AccessibleLazyVStack<Content: View>: View {
    let label: LocalizedStringResource
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 6, content: content)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label))
    }
}

/// A `LazyVGrid` that is a labelled accessibility container (A11Y-029: an unlabelled lazy grid is reported as an element
/// without a description).
struct AccessibleLazyVGrid<Content: View>: View {
    let label: LocalizedStringResource
    let columns: [GridItem]
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(label: LocalizedStringResource, columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: alignment, spacing: spacing, content: content)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label))
    }
}
