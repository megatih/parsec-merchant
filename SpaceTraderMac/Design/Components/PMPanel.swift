// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// UI-DS-030: a bordered panel with an optional header and trailing accessory. Every screen is built from panels.
struct PMPanel<Accessory: View, Content: View>: View {
    var title: LocalizedStringResource?
    var identifier: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content
    @Environment(\.pmScale) private var scale
    @Environment(\.accessibilityPreferences) private var prefs

    init(_ title: LocalizedStringResource? = nil, identifier: String, @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.identifier = identifier
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PMSpace.s * scale) {
            if let title {
                HStack(spacing: PMSpace.s * scale) {
                    Text(title).pmFont(.panelTitle).foregroundStyle(PMColor.label(increaseContrast: prefs.increaseContrast))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    accessory()
                }
            }
            content()
        }
        .pmPadding(.all, PMSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PMColor.panel, in: RoundedRectangle(cornerRadius: PMRadius.panel * scale))
        .overlay {
            RoundedRectangle(cornerRadius: PMRadius.panel * scale)
                .strokeBorder(PMColor.border(increaseContrast: prefs.increaseContrast),
                    lineWidth: PMColor.borderWidth(increaseContrast: prefs.increaseContrast))
        }
        .accessibilityElement(children: .contain)
        .probed(identifier)
    }
}

extension PMPanel where Accessory == EmptyView {
    init(_ title: LocalizedStringResource? = nil, identifier: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, identifier: identifier, accessory: { EmptyView() }, content: content)
    }
}

/// UI-DS-030: a small rounded label showing a key ("B", "⇧S", "⌘J").
struct PMKeyCap: View {
    let key: String
    @Environment(\.pmScale) private var scale

    var body: some View {
        Text(verbatim: key)
            .pmFont(.caption)
            .foregroundStyle(PMColor.textSecondary)
            .padding(.horizontal, 4 * scale)
            .padding(.vertical, 1 * scale)
            .background(PMColor.panelRaised, in: RoundedRectangle(cornerRadius: PMRadius.control * scale))
            .overlay { RoundedRectangle(cornerRadius: PMRadius.control * scale).strokeBorder(PMColor.hairline) }
            .accessibilityHidden(true)
    }
}

/// UI-DS-030: a label and a value, with an optional tone. A tone always brings its symbol (UI-DS-012).
struct PMStat: View {
    let label: LocalizedStringResource
    let value: String
    var tone: PMTone = .neutral
    var large = false
    var identifier: String
    var help: LocalizedStringResource?
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(spacing: PMSpace.xs * scale) {
            Text(label).pmFont(.body).foregroundStyle(PMColor.textSecondary)
            if let symbol = tone.symbol {
                Image(systemName: symbol).pmFont(.caption).foregroundStyle(tone.color).accessibilityHidden(true)
            }
            Text(verbatim: value).pmFont(large ? .valueLarge : .value).foregroundStyle(tone.color)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityAddTraits(.isStaticText)  // A11Y-029: a labelled value needs a role
        .help(help.map { Text($0) } ?? Text(label))
        .probed(identifier)
    }
}

/// UI-DS-030: a horizontal bar with its value as text. The tone is the caller's; the text carries the value.
struct PMGauge: View {
    let label: LocalizedStringResource
    /// 0…1.
    let fraction: Double
    let valueText: String
    var tone: PMTone = .neutral
    var identifier: String
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(spacing: PMSpace.s * scale) {
            Text(label).pmFont(.body).foregroundStyle(PMColor.textSecondary).fixedSize()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: PMRadius.control * scale).fill(PMColor.panelInset)
                    RoundedRectangle(cornerRadius: PMRadius.control * scale)
                        .fill(tone == .neutral ? PMColor.info : tone.color)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
            }
            .frame(minWidth: 40 * scale, maxWidth: .infinity)
            .frame(height: 8 * scale)
            if let symbol = tone.symbol, tone != .neutral {
                Image(systemName: symbol).pmFont(.caption).foregroundStyle(tone.color).accessibilityHidden(true)
            }
            Text(verbatim: valueText).pmFont(.value).foregroundStyle(PMColor.textPrimary).fixedSize()
        }
        // A11Y-004: a progress element with the value in words (a labelled bar has no role).
        .accessibilityRepresentation {
            ProgressView(value: max(0, min(1, fraction))) { Text(label) }.accessibilityValue(Text(verbatim: valueText))
        }
        .probed(identifier)
    }
}

/// UI-DS-030: a capsule with a symbol and a word.
struct PMBadge: View {
    let text: LocalizedStringResource
    let symbol: String
    var color: Color = PMColor.info
    var identifier: String
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(spacing: PMSpace.xs * scale) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text)
        }
        .pmFont(.caption)
        .foregroundStyle(color)
        .padding(.horizontal, PMSpace.s * scale)
        .padding(.vertical, 2 * scale)
        .overlay { Capsule().strokeBorder(color) }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .probed(identifier)
    }
}

/// UI-DS-030: an empty state: a symbol, one sentence and an optional action.
struct PMEmptyState<Action: View>: View {
    let symbol: String
    let message: LocalizedStringResource
    var identifier: String
    @ViewBuilder var action: () -> Action
    @Environment(\.pmScale) private var scale

    var body: some View {
        VStack(spacing: PMSpace.s * scale) {
            Image(systemName: symbol).font(.system(size: 28 * scale)).foregroundStyle(PMColor.textDisabled).accessibilityHidden(true)
            Text(message).pmFont(.body).foregroundStyle(PMColor.textSecondary).multilineTextAlignment(.center)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .probed(identifier)
    }
}

extension PMEmptyState where Action == EmptyView {
    init(symbol: String, message: LocalizedStringResource, identifier: String) {
        self.init(symbol: symbol, message: message, identifier: identifier) { EmptyView() }
    }
}
