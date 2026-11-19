// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// A Bridge region: the panel fill and border around content that manages its own padding. The Bridge's budget is
/// tight, so its panels use 8 pt padding and put their title on the first content line.
struct BridgePanel<Content: View>: View {
    let identifier: String
    @ViewBuilder var content: () -> Content
    @Environment(\.pmScale) private var scale
    @Environment(\.accessibilityPreferences) private var prefs

    var body: some View {
        content()
            .padding(PMSpace.s * scale)
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

/// A panel's title, in the panel-title style.
struct BridgeTitle: View {
    let title: LocalizedStringResource
    @Environment(\.accessibilityPreferences) private var prefs

    var body: some View {
        Text(title)
            .pmFont(.panelTitle)
            .foregroundStyle(PMColor.label(increaseContrast: prefs.increaseContrast))
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

/// One fact line: a label and its value, laid out at their natural size so nothing can truncate (UI-BRG-032).
struct BridgeFact<Value: View>: View {
    let label: LocalizedStringResource
    let labelWidth: CGFloat
    let identifier: String
    @ViewBuilder var value: () -> Value
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(spacing: PMSpace.s * scale) {
            Text(label).pmFont(.body).foregroundStyle(PMColor.textSecondary).fixedSize()
                .frame(width: labelWidth * scale, alignment: .leading)
            value().pmFont(.body).foregroundStyle(PMColor.textPrimary).fixedSize()
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)  // A11Y-029: a labelled value needs a role
        .probed(identifier)
    }
}

/// Police or pirate activity as seven pips and a word (never the pips alone).
struct BridgeActivity: View {
    let activity: Activity
    @Environment(\.pmScale) private var scale

    var body: some View {
        let filled = SystemCardModel.dots(activity)
        HStack(spacing: PMSpace.xs * scale) {
            HStack(spacing: 2 * scale) {
                ForEach(0..<SystemCardModel.maxActivityDots, id: \.self) { i in
                    Circle()
                        .fill(i < filled ? PMColor.textPrimary : Color.clear)
                        .overlay { Circle().strokeBorder(i < filled ? PMColor.textPrimary : PMColor.strongLine) }
                        .frame(width: 6 * scale, height: 6 * scale)
                }
            }
            .accessibilityHidden(true)
            Text(SystemText.activity(activity))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SystemText.activity(activity)))
        .accessibilityAddTraits(.isStaticText)
    }
}

/// A notice button of the System Information region: content-sized, with a symbol, a word and an optional tag. With
/// nothing to show it stays in place, disabled, and its help tag says why.
struct BridgeNotice: View {
    let symbol: String
    let title: LocalizedStringResource
    var tone: PMTone = .neutral
    /// Why there is nothing here; nil when the notice is active.
    var emptyReason: LocalizedStringResource?
    var help: String
    let identifier: String
    let action: () -> Void
    @Environment(\.pmScale) private var scale

    var body: some View {
        Button(action: action) {
            HStack(spacing: PMSpace.xs * scale) {
                Image(systemName: symbol).foregroundStyle(emptyReason == nil ? tone.color : PMColor.textDisabled).accessibilityHidden(true)
                Text(title)
            }
        }
        .buttonStyle(PMButtonStyle(kind: emptyReason == nil ? .standard : .quiet))
        .fixedSize()
        .probed(identifier)
        .disabled(emptyReason != nil)
        .help(emptyReason.map { Text($0) } ?? Text(verbatim: help))
    }
}

/// Signed numbers with their arrow: "▲12", "▼9", "0". Colour is never the only sign.
enum BridgeNumbers {
    static func signed(_ n: Int) -> String {
        n > 0 ? "▲\(n.formatted())" : n < 0 ? "▼\(abs(n).formatted())" : "0"
    }

    static func tone(_ n: Int) -> Color {
        n > 0 ? PMColor.profit : n < 0 ? PMColor.loss : PMColor.textSecondary
    }
}
