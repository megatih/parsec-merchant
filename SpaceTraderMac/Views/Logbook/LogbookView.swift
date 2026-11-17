// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import ParsecInsights
import SwiftUI

/// LOG-029 / LOG-030: the Logbook (⌘9): Captain's Log, Statistics and Achievements tabs.
struct LogbookView: View {
    @Environment(GameSession.self) private var session
    @SceneStorage("logbookTab") private var storedTab = LogbookTab.log.rawValue

    private var tab: LogbookTab { session.logbookTab ?? LogbookTab(rawValue: storedTab) ?? .log }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if session.state.map({ GameSession.isGameOver($0.phase) }) == true {
                    Button {
                        session.backToSummary()
                    } label: {
                        Label("Back to Summary", systemImage: "chevron.backward")
                    }
                    .accessibilityIdentifier(AXID.Logbook.backToSummary)
                }
                Spacer()
                Picker(selection: tabBinding) {
                    ForEach(LogbookTab.allCases, id: \.self) { t in
                        Text(t.title).tag(t).accessibilityIdentifier(AXID.Logbook.tab(t))
                    }
                } label: {
                    Text("Logbook")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier(AXID.Logbook.tab)
                Spacer()
            }
            .padding(10)
            Divider()
            switch tab {
            case .log: CaptainsLogView()
            case .statistics: StatisticsView()
            case .achievements: AchievementsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Logbook.root)
    }

    private var tabBinding: Binding<LogbookTab> {
        Binding { tab } set: { new in
            session.logbookTab = new
            storedTab = new.rawValue
        }
    }
}

/// LOG-010: the symbol of a log category (the feed symbols of UI-ENC-065 where they exist).
enum LogCategoryStyle {
    static func symbol(_ c: LogCategory) -> String {
        switch c {
        case .trade: FeedCategory.trade.symbol
        case .travel: FeedCategory.travel.symbol
        case .encounter: FeedCategory.encounter.symbol
        case .police: FeedCategory.police.symbol
        case .finance: FeedCategory.finance.symbol
        case .ship: FeedCategory.ship.symbol
        case .crew: FeedCategory.crew.symbol
        case .quest: FeedCategory.quest.symbol
        case .news: FeedCategory.news.symbol
        case .status: "person.text.rectangle"
        case .achievement: "rosette"
        case .game: "flag"
        }
    }

    static func title(_ c: LogCategory) -> LocalizedStringResource {
        switch c {
        case .trade: "Trade"
        case .travel: "Travel"
        case .encounter: "Encounters"
        case .police: "Police"
        case .finance: "Finance"
        case .ship: "Ship"
        case .crew: "Crew"
        case .quest: "Quests"
        case .news: "News"
        case .status: "Status"
        case .achievement: "Achievements"
        case .game: "Game"
        }
    }
}

// MARK: - Captain's Log (LOG-031…034)

struct CaptainsLogView: View {
    @Environment(GameSession.self) private var session
    @AppStorage(AppSettingsKey.showFlavor) private var showFlavor = true
    @State private var model = LogbookModel()
    @State private var exportDocument: LogMarkdownDocument?
    @FocusState private var searchFocused: Bool

    var body: some View {
        if let state = session.state, let journal = session.journal {
            let rows = groups(journal: journal, state: state)
            VStack(spacing: 0) {
                toolbar(state: state, journal: journal)
                Divider()
                if rows.isEmpty {
                    ContentUnavailableView(model.isFiltered ? "No entries match" : "No entries yet",
                                           systemImage: "book.closed")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(rows, journal: journal, state: state)
                }
            }
            .focusedSceneValue(\.contextSearch, ContextSearchAction { searchFocused = true })
            .fileExporter(isPresented: exportBinding, document: exportDocument, contentType: LogMarkdownDocument.markdown,
                          defaultFilename: LogbookModel.exportName(commander: state.commander.name)) { _ in
                exportDocument = nil
            }
        }
    }

    /// Reads `journalRevision` so generated flavor refreshes the rows (LOG-027).
    private func groups(journal: GameJournal, state: GameState) -> [LogDayGroup] {
        _ = session.journalRevision
        return model.groups(journal: journal, text: { LogEntryText.text(for: $0, journal: journal, state: state) },
                            flavor: { FlavorCatalogText.text(for: $0.flavor, state: state) })
    }

    private func toolbar(state: GameState, journal: GameJournal) -> some View {
        HStack(spacing: 8) {
            TextField(text: $model.searchText) { Text("Search the log") }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .focused($searchFocused)
                // UI-KEYS-017 level 3: the window's Esc router clears the focused search.
                .escapeHandler(.clearField, active: searchFocused && !model.searchText.isEmpty) { model.searchText = "" }
                .accessibilityIdentifier(AXID.Logbook.search)
            Menu {
                ForEach(LogCategory.allCases, id: \.self) { c in
                    Toggle(isOn: Binding { model.filter.categories.contains(c) } set: { _ in model.toggle(c) }) {
                        Label { Text(LogCategoryStyle.title(c)) } icon: { Image(systemName: LogCategoryStyle.symbol(c)) }
                    }
                    .accessibilityIdentifier(AXID.Logbook.filter(c))
                }
                Divider()
                Button("Clear filters") { model.clearFilters() }
                    .accessibilityIdentifier(AXID.Logbook.filterClear)
            } label: {
                Label("Filter", systemImage: model.filter.isEmpty
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .fixedSize()
            .accessibilityIdentifier(AXID.Logbook.filter)
            Spacer()
            Button {
                exportDocument = LogMarkdownDocument(text: LogExport.markdown(journal: journal, state: state, filter: model.filter,
                                                                             showFlavor: showFlavor))
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .help(Text("Export the log as a Markdown file."))
            .accessibilityIdentifier(AXID.Logbook.export)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func list(_ groups: [LogDayGroup], journal: GameJournal, state: GameState) -> some View {
        List(selection: $model.selection) {
            ForEach(groups) { group in
                SwiftUI.Section {
                    ForEach(group.entries) { entry in
                        LogEntryRow(entry: entry, journal: journal, state: state, showFlavor: showFlavor)
                            .tag(entry.id)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(AXID.Logbook.entry(entry.id))
                    }
                } header: {
                    Text("Day \(group.day) · \(Names.system(group.system, in: state))")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AXID.Logbook.group(group.id))
                }
            }
        }
        .onCopyCommand {
            guard let text = model.copyText(journal: journal, text: { LogEntryText.text(for: $0, journal: journal, state: state) },
                                            flavor: { showFlavor ? FlavorCatalogText.text(for: $0.flavor, state: state) : nil })
            else { return [] }
            return [NSItemProvider(object: text as NSString)]
        }
        .accessibilityIdentifier(AXID.Logbook.list)
    }

    private var exportBinding: Binding<Bool> {
        Binding { exportDocument != nil } set: { if !$0 { exportDocument = nil } }
    }
}

/// One log row: category symbol, text, optional flavor line (LLM-027) and the encounter details (LOG-031).
private struct LogEntryRow: View {
    let entry: LogEntry
    let journal: GameJournal
    let state: GameState
    let showFlavor: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: LogCategoryStyle.symbol(entry.kind.category))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: LogEntryText.text(for: entry, journal: journal, state: state))
                    .fixedSize(horizontal: false, vertical: true)
                if showFlavor, let flavor = FlavorCatalogText.text(for: entry.flavor, state: state) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if entry.flavor?.source == .foundationModels {
                            Image(systemName: "apple.intelligence")
                                .font(.caption)
                                .help(Text("Written by Apple Intelligence"))
                                .accessibilityLabel(Text("Apple Intelligence"))
                        }
                        Text(verbatim: flavor).font(.callout).italic().foregroundStyle(.secondary)
                    }
                }
                if case let .encounter(record) = entry.kind {
                    DisclosureGroup {
                        Text(verbatim: LogEntryText.encounterDetails(record))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("Details").font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
