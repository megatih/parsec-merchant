// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// UI-NAV-002: one button of the dock bar: a symbol, a label and a key cap on one line. The current page is marked by
/// an accent underline and a filled symbol, never by colour alone.
struct PMDockButton: View {
    let title: LocalizedStringResource
    let symbol: String
    var key: String?
    var current = false
    /// A count badge (mercenaries for hire, urgent quests) or a mark; nil for none.
    var badge: String?
    var badgeLabel: LocalizedStringResource?
    var badgeIdentifier: String?
    /// Why the page cannot be opened now; nil when it can.
    var disabledReason: String?
    var help: LocalizedStringResource?
    let identifier: String
    let action: () -> Void
    @Environment(\.pmScale) private var scale
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3 * scale) {
                Image(systemName: symbol)
                    .symbolVariant(current ? .fill : .none)
                    .foregroundStyle(disabledReason != nil ? PMColor.textDisabled : (current ? PMColor.accent : PMColor.textSecondary))
                    .accessibilityHidden(true)
                Text(title)
                    .fontWeight(current ? .semibold : .regular)
                    .foregroundStyle(disabledReason != nil ? PMColor.textDisabled : PMColor.textPrimary)
                if let badge {
                    Text(verbatim: badge)
                        .pmFont(.caption)
                        .foregroundStyle(PMColor.space)
                        .padding(.horizontal, 5 * scale)
                        .background(PMColor.caution, in: Capsule())
                        .accessibilityLabel(badgeLabel.map { Text($0) } ?? Text(verbatim: badge))
                        .probed(badgeIdentifier ?? "\(identifier).badge")
                }
                if let key {
                    Text(verbatim: key).pmFont(.caption).foregroundStyle(PMColor.textSecondary).accessibilityHidden(true)
                }
            }
            .pmFont(.dock)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 3 * scale)
            .frame(maxWidth: .infinity, minHeight: PointerTarget.minimum * scale)
            .background(hovering && disabledReason == nil ? PMColor.panelRaised : .clear, in: RoundedRectangle(cornerRadius: PMRadius.control * scale))
            .overlay(alignment: .bottom) {
                if current { Rectangle().fill(PMColor.accent).frame(height: 2 * scale) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .probed(identifier)
        .disabled(disabledReason != nil)
        .help(disabledReason.map { Text(verbatim: $0) } ?? Text(help ?? title))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// UI-PG-001: the frame of a secondary page: a title row with Back to the Bridge and optional actions, then the content.
struct PMPage<Actions: View, Content: View>: View {
    let title: LocalizedStringResource
    let identifier: String
    var onBack: (() -> Void)?
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content
    @Environment(\.pmScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: PMSpace.s * scale) {
            HStack(spacing: PMSpace.m * scale) {
                if let onBack {
                    PMButton(title: "Bridge", systemImage: "chevron.left", kind: .quiet, help: "Return to the Bridge (Esc)",
                             identifier: "\(identifier).back", action: onBack)
                }
                Text(title).pmFont(.title).foregroundStyle(PMColor.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                actions()
            }
            .frame(minHeight: 44 * scale)
            content()
                .frame(maxWidth: 1400 * scale, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity)
        }
        .pmPadding(.horizontal, PMSpace.m)
        .pmPadding(.bottom, PMSpace.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .probed(identifier)
    }
}

extension PMPage where Actions == EmptyView {
    init(title: LocalizedStringResource, identifier: String, onBack: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, identifier: identifier, onBack: onBack, actions: { EmptyView() }, content: content)
    }
}
