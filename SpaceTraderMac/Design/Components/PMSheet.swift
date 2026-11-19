// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// UI-ENC-205, UI-PG-070: the body of a sheet in the console palette: a title, the content, and one row of buttons at
/// the trailing edge. The system draws the sheet's frame.
struct PMSheet<Content: View, Buttons: View>: View {
    let title: Text
    var width: CGFloat = 460
    let identifier: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: PMSpace.m) {
            title.pmFont(.title).foregroundStyle(PMColor.textPrimary).accessibilityAddTraits(.isHeader)
            content()
            HStack(spacing: PMSpace.s) {
                Spacer(minLength: 0)
                buttons()
            }
        }
        .padding(PMSpace.xl)
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The console palette for everything a sheet shows: dark controls on the panel fill, and `PMButtonStyle` for buttons
/// that name no style of their own. Applied where sheets are hosted, because a sheet does not inherit the window's styles.
struct PMSheetChrome: ViewModifier {
    @AppStorage(AppSettingsKey.textSize) private var textSize = TextSizeSetting.standard.rawValue

    func body(content: Content) -> some View {
        content
            // UI-DS-004: sheets follow the Text Size setting.
            .environment(\.pmScale, GameShellView.textFloor(textSize))
            .environment(\.textScale, GameShellView.textFloor(textSize))
            .buttonStyle(PMButtonStyle())
            .foregroundStyle(PMColor.textPrimary)
            .tint(PMColor.accent)
            .environment(\.colorScheme, .dark)
            .presentationBackground(PMColor.panel)
    }
}

extension View {
    func pmSheetChrome() -> some View { modifier(PMSheetChrome()) }

    /// The button Return presses: the primary look and the default-action key.
    func pmDefaultAction() -> some View {
        buttonStyle(PMButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
    }
}

/// A whole-number quantity typed into a `PMField`, kept inside `range`. The same control as the Cargo region's
/// Quantity field (UI-ENC-205).
struct PMQuantityField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: LocalizedStringResource
    let identifier: String
    @State private var text = ""

    var body: some View {
        // The prompt is the current quantity (a number, not a phrase to translate).
        let prompt = LocalizedStringResource(String.LocalizationValue(value.formatted()))
        let invalid = !text.isEmpty && Self.parse(text, in: range) == nil
        return PMField(text: $text, prompt: prompt, label: label, invalid: invalid, identifier: identifier)
            .frame(width: 56)
            .accessibilityValue(Text(verbatim: AccessibilityText.units(value)))
            .onChange(of: text) { _, new in
                if let parsed = Self.parse(new, in: range) { value = parsed }
            }
            .onChange(of: value) { _, new in
                if Self.parse(text, in: range) != new { text = "" }
            }
    }

    /// The typed number when it is whole and inside the range; nil otherwise.
    static func parse(_ text: String, in range: ClosedRange<Int>) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(n) else { return nil }
        return n
    }
}

/// A check box in the console palette: a button with a box symbol and its label. Its value reads "On" or "Off".
struct PMCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: PMSpace.xs) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? PMColor.accent : PMColor.textSecondary)
                    .accessibilityHidden(true)
                configuration.label
            }
        }
        .buttonStyle(PMButtonStyle(kind: .quiet, compact: true))
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
