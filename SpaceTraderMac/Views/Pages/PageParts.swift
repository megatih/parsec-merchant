// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// A secondary page of the game area (UI-PG-001): the page frame with Back to the Bridge, its panels below.
struct GamePage<Actions: View, Content: View>: View {
    @Environment(GameSession.self) private var session
    let section: Section
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        PMPage(title: section.title, identifier: "page.\(section.rawValue)", onBack: { session.selectedSection = .bridge }, actions: actions,
               content: content)
            .accessibilityIdentifier(AXID.SectionRoot.root(section))
    }
}

extension GamePage where Actions == EmptyView {
    init(section: Section, @ViewBuilder content: @escaping () -> Content) {
        self.init(section: section, actions: { EmptyView() }, content: content)
    }
}

/// A label with its value at the trailing edge: the line of every facts panel.
struct PMInfoRow<Value: View>: View {
    let label: LocalizedStringResource
    var identifier: String?
    var help: LocalizedStringResource?
    @ViewBuilder var value: () -> Value
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PMSpace.m * scale) {
            Text(label).pmFont(.body).foregroundStyle(PMColor.textSecondary)
            Spacer(minLength: PMSpace.s * scale)
            value().pmFont(.value).foregroundStyle(PMColor.textPrimary).multilineTextAlignment(.trailing)
        }
        // A11Y-029: a labelled container, so the contrast audit measures the label and the value each in its own colour
        // (a combined element is measured across the gap between them).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
        .help(help.map { Text($0) } ?? Text(label))
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

extension PMInfoRow where Value == Text {
    init(_ label: LocalizedStringResource, value: String, identifier: String? = nil, help: LocalizedStringResource? = nil) {
        self.init(label: label, identifier: identifier, help: help) { Text(verbatim: value) }
    }

    /// A credits value: "1,234 cr.".
    init(_ label: LocalizedStringResource, credits: Int, identifier: String? = nil, help: LocalizedStringResource? = nil) {
        self.init(label: label, identifier: identifier, help: help) { Text("\(credits.formatted()) cr.") }
    }
}

struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier { content.probed(identifier) } else { content }
    }
}

/// A one-line note with its tone's symbol (a blocker, a warning, a hint).
struct PMNote: View {
    let text: LocalizedStringResource
    var tone: PMTone = .caution
    var identifier: String?
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PMSpace.xs * scale) {
            if let symbol = tone.symbol { Image(systemName: symbol).foregroundStyle(tone.color).accessibilityHidden(true) }
            Text(text).foregroundStyle(tone == .neutral ? PMColor.textSecondary : tone.color).fixedSize(horizontal: false, vertical: true)
        }
        .pmFont(.caption)
        .accessibilityElement(children: .combine)
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

/// A thin separator between the parts of a panel.
struct PMDivider: View {
    var body: some View {
        Rectangle().fill(PMColor.hairline).frame(height: 1).accessibilityHidden(true)
    }
}

extension CommandError {
    /// The reason as a help tag or a disabled button's reason.
    @MainActor var reason: String { String(localized: ReasonText.text(for: self)) }
}

/// UI-PG-001: page content that scrolls as a whole only when it cannot fit the page.
struct PMFitScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content().fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) { content() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The four skills of a crew member as labelled bars with their numbers (never the bar alone).
struct PMSkillBars: View {
    let skills: [Int]
    @Environment(\.pmScale) private var scale

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: PMSpace.s * scale, verticalSpacing: 2 * scale) {
            ForEach(SkillType.allCases, id: \.self) { skill in
                let value = skills.indices.contains(skill.rawValue) ? skills[skill.rawValue] : 0
                GridRow {
                    Text(Names.skill(skill)).pmFont(.caption).foregroundStyle(PMColor.textSecondary)
                    Text(verbatim: "\(value.formatted())/10").pmFont(.caption).monospacedDigit().foregroundStyle(PMColor.textPrimary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: PMRadius.control * scale).fill(PMColor.panelInset)
                            RoundedRectangle(cornerRadius: PMRadius.control * scale).fill(PMColor.info)
                                .frame(width: geo.size.width * Double(min(max(value, 0), 10)) / 10)
                        }
                    }
                    .frame(width: 80 * scale, height: 6 * scale)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
