// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import SwiftUI

/// The Help window's topics (UI-SHELL-109). Raw values are the bundled `Help/<id>.md` names and identifier suffixes.
nonisolated enum HelpTopic: String, CaseIterable, Sendable, Identifiable {
    case gettingStarted, bridge, market, shipyard, outfitter, crew, bank, quests, travel, encounters, howPricesWork, rulesets,
         keyboardShortcuts, credits

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .gettingStarted: "Getting Started"
        case .bridge: "Bridge"
        case .market: "Market"
        case .shipyard: "Shipyard"
        case .outfitter: "Outfitter"
        case .crew: "Crew"
        case .bank: "Bank"
        case .quests: "Quests"
        case .travel: "Travel"
        case .encounters: "Encounters"
        case .howPricesWork: "How Prices Work"
        case .rulesets: "Rulesets"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .credits: "Credits"
        }
    }
}

/// Bundled Markdown help (UI-SHELL-109…111).
nonisolated enum HelpContent {
    static let topics = HelpTopic.allCases

    /// The bundled Markdown of a topic ("" when missing).
    static func markdown(_ topic: HelpTopic, bundle: Bundle = .main) -> String {
        let url = bundle.url(forResource: topic.rawValue, withExtension: "md")
            ?? bundle.url(forResource: topic.rawValue, withExtension: "md", subdirectory: "Help")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    /// UI-SHELL-110: the menu shortcut rows (from `KeyBindingTable`, so they can't drift from the menus).
    static func shortcutRows(milestone: Int = MenuCatalog.currentMilestone) -> [(shortcut: String, title: String)] {
        KeyboardShortcutsPage.make(milestone: milestone).flatMap { section in
            section.rows.filter { row in KeyBindingTable.menuBindings.contains { $0.action == row.action && !row.isAlias } }
                .map { ($0.display, $0.title) }
        }
    }

    /// The full text of a topic: the bundled file, plus the generated table for Keyboard Shortcuts (UI-KEYS-002).
    static func text(_ topic: HelpTopic, bundle: Bundle = .main) -> String {
        let base = markdown(topic, bundle: bundle)
        guard topic == .keyboardShortcuts else { return base }
        return [base, KeyboardShortcutsPage.markdown()].joined(separator: "\n\n")
    }
}

/// Which Help topic the Help window shows; menus set it before opening the window.
@Observable
final class HelpRouter {
    var topic: HelpTopic = .gettingStarted
}

/// The Help window (UI-SHELL-109): a topic sidebar and the topic's Markdown.
struct HelpView: View {
    @Environment(HelpRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(HelpContent.topics, selection: Binding($router.topic)) { topic in
                Text(topic.title)
                    .tag(topic)
                    .accessibilityIdentifier(AXID.Help.topic(topic))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ScrollView {
                MarkdownBlocks(text: HelpContent.text(router.topic))
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier(AXID.Help.content)
        }
        .frame(minWidth: 720, minHeight: 480)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Help.window)
        .modifier(AppTextSize())
    }
}

/// Renders simple Markdown: `#`/`##` headings, `-` list items and paragraphs with inline styling.
struct MarkdownBlocks: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, s):
                    Text(MarkdownBlock.inline(s)).scaledFont(level == 1 ? .title : .title3, weight: .bold)
                case let .item(s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "•")
                        Text(MarkdownBlock.inline(s))
                    }
                case let .paragraph(s):
                    Text(MarkdownBlock.inline(s))
                }
            }
        }
        .textSelection(.enabled)
    }
}

/// A block of the simple Markdown used by the help files.
nonisolated enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case item(String)
    case paragraph(String)

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("## ") {
                flush()
                blocks.append(.heading(2, String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush()
                blocks.append(.heading(1, String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flush()
                blocks.append(.item(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
