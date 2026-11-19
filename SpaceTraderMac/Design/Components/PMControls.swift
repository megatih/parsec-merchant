// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// UI-DS-030: the looks of a game-area button.
nonisolated enum PMButtonKind: CaseIterable, Sendable {
    /// Brass fill, dark text: the one main action of a panel.
    case primary
    /// Raised fill.
    case standard
    /// Text only, a hairline on hover.
    case quiet
    /// A loss-coloured outline, for destructive actions.
    case danger
}

/// UI-DS-030: the style behind `PMButton`: normal, hover, pressed and disabled states inside a 36 pt target.
struct PMButtonStyle: ButtonStyle {
    var kind: PMButtonKind = .standard
    var fillsWidth = false
    /// Table rows: less padding at the sides.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PMButtonBody(configuration: configuration, kind: kind, fillsWidth: fillsWidth, compact: compact)
    }
}

private struct PMButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PMButtonKind
    let fillsWidth: Bool
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.pmScale) private var scale
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PMRadius.control * scale)
        configuration.label
            .pmFont(kind == .primary ? .valueLarge : .body)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, (compact ? 6 : PMSpace.s) * scale)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(minHeight: 28 * scale)
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(stroke, lineWidth: 1) }
            // UI-PTR-002: the visible button keeps its size; the target reaches 36 pt.
            .frame(minWidth: PointerTarget.minimum * scale, minHeight: PointerTarget.minimum * scale)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: PMMotion.hover), value: hovering)
    }

    private var foreground: Color {
        guard isEnabled else { return PMColor.textDisabled }
        switch kind {
        case .primary: return PMColor.space
        case .danger: return PMColor.loss
        case .standard, .quiet: return PMColor.textPrimary
        }
    }

    private var fill: Color {
        guard isEnabled else { return kind == .quiet ? .clear : PMColor.panelInset }
        let pressed = configuration.isPressed
        switch kind {
        case .primary: return PMColor.accent.opacity(pressed ? 0.75 : (hovering ? 0.9 : 1))
        case .standard: return pressed ? PMColor.hairline : (hovering ? PMColor.hairline.opacity(0.8) : PMColor.panelRaised)
        case .quiet, .danger: return pressed ? PMColor.panelRaised : (hovering ? PMColor.panelRaised.opacity(0.7) : .clear)
        }
    }

    private var stroke: Color {
        guard isEnabled else { return PMColor.hairline }
        switch kind {
        case .primary: return PMColor.accent
        case .standard: return PMColor.strongLine
        case .quiet: return hovering ? PMColor.hairline : .clear
        case .danger: return PMColor.loss
        }
    }
}

/// UI-DS-030, UI-DS-031: a game-area button. A disabled button always says why: the reason is its help tag, so the
/// initializer takes it (nil = enabled).
struct PMButton: View {
    let title: LocalizedStringResource
    var systemImage: String?
    var kind: PMButtonKind = .standard
    var key: String?
    var fillsWidth = false
    var compact = false
    /// The help tag of the enabled button.
    var help: LocalizedStringResource?
    /// Why the button cannot act; nil when it can.
    var disabledReason: String?
    let identifier: String
    let action: () -> Void
    @Environment(\.pmScale) private var scale

    var body: some View {
        Button(action: action) {
            HStack(spacing: PMSpace.xs * scale) {
                if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
                Text(title)
                if let key { PMKeyCap(key: key) }
            }
        }
        .buttonStyle(PMButtonStyle(kind: kind, fillsWidth: fillsWidth, compact: compact))
        .probed(identifier)
        .disabled(disabledReason != nil)
        .help(disabledReason.map { Text(verbatim: $0) } ?? Text(help ?? title))
    }
}

/// UI-DS-030: a numeric field on the inset fill.
struct PMField: View {
    @Binding var text: String
    var prompt: LocalizedStringResource
    var label: LocalizedStringResource
    var invalid = false
    let identifier: String
    @Environment(\.pmScale) private var scale
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $text, prompt: Text(prompt)) { Text(label) }
            .textFieldStyle(.plain)
            .pmFont(.value)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(PMColor.textPrimary)
            .padding(.horizontal, PMSpace.xs * scale)
            .frame(minHeight: 28 * scale)
            .background(PMColor.panelInset, in: RoundedRectangle(cornerRadius: PMRadius.control * scale))
            .overlay {
                RoundedRectangle(cornerRadius: PMRadius.control * scale)
                    .strokeBorder(invalid ? PMColor.loss : (focused ? PMColor.accent : PMColor.hairline), lineWidth: focused || invalid ? 2 : 1)
            }
            .focused($focused)
            // UI-PTR-002: the visible box keeps its size; the target reaches 36 pt.
            .frame(minHeight: PointerTarget.minimum * scale)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(label))
            .probed(identifier)
    }
}

/// UI-DS-030: a fixed-size notice button: a symbol, a short label and an optional tag. With nothing to show it keeps
/// its place in an "empty" appearance, disabled, and its help tag says why.
struct PMNotice: View {
    let symbol: String
    let title: LocalizedStringResource
    var tag: String?
    var tone: PMTone = .neutral
    /// Why there is nothing here; nil when the notice is active.
    var emptyReason: String?
    var help: String?
    let identifier: String
    let action: () -> Void
    @Environment(\.pmScale) private var scale

    var body: some View {
        Button(action: action) {
            HStack(spacing: PMSpace.xs * scale) {
                Image(systemName: symbol).foregroundStyle(emptyReason == nil ? tone.color : PMColor.textDisabled).accessibilityHidden(true)
                Text(title)
                if let tag { Text(verbatim: tag).pmFont(.value).foregroundStyle(tone.color) }
            }
        }
        .buttonStyle(PMButtonStyle(kind: emptyReason == nil ? .standard : .quiet, fillsWidth: true))
        .probed(identifier)
        .disabled(emptyReason != nil)
        .help(Text(verbatim: emptyReason ?? help ?? ""))
    }
}

/// UI-DS-030: the one tab control of the game area.
struct PMSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: LocalizedStringResource, identifier: String)]
    @Binding var selection: Value
    let identifier: String
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i], selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .pmFont(.body)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? PMColor.space : PMColor.textPrimary)
                        .padding(.horizontal, PMSpace.m * scale)
                        .frame(minHeight: 28 * scale)
                        .background(selected ? PMColor.accent : PMColor.panelRaised)
                        .frame(minHeight: PointerTarget.minimum * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .probed(option.identifier)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PMRadius.control * scale))
        .accessibilityElement(children: .contain)
        .probed(identifier)
    }
}

/// UI-DS-030: a 36 pt table row with hover and selection. A selected row has the raised fill and an accent bar, so
/// selection never depends on colour alone.
struct PMRow<Content: View>: View {
    var selected = false
    let identifier: String
    @ViewBuilder var content: () -> Content
    @Environment(\.pmScale) private var scale
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        content()
            .padding(.leading, PMSpace.s * scale)
            .frame(maxWidth: .infinity, minHeight: PointerTarget.minimum * scale, alignment: .leading)
            .background(selected ? PMColor.panelRaised : (hovering && isEnabled ? PMColor.panelRaised.opacity(0.5) : .clear))
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(PMColor.accent).frame(width: 3 * scale) }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(PMColor.hairline).frame(height: 1) }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .probed(identifier)
    }
}
