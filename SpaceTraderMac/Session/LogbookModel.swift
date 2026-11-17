// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import SwiftUI
import UniformTypeIdentifiers

/// LOG-030: the Logbook's tabs. Raw values are the identifier suffixes.
nonisolated enum LogbookTab: String, CaseIterable, Sendable {
    case log, statistics, achievements

    var title: LocalizedStringResource {
        switch self {
        case .log: "Captain's Log"
        case .statistics: "Statistics"
        case .achievements: "Achievements"
        }
    }
}

/// LOG-031…034: the Captain's Log tab's state (search text, category filter, selection) and its pure queries.
struct LogbookModel: Equatable {
    var searchText = ""
    var filter = LogFilter()
    var selection: Set<Int> = []

    var isFiltered: Bool { !filter.isEmpty || !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// LOG-023: the search predicate: the rendered text or the flavor text contains the query, ignoring case and
    /// diacritics.
    static func matches(query: String, text: String, flavor: String?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return text.range(of: q, options: options) != nil || flavor?.range(of: q, options: options) != nil
    }

    /// LOG-022 / LOG-031: the filtered day groups, newest first.
    func groups(journal: GameJournal, text: (LogEntry) -> String, flavor: (LogEntry) -> String?) -> [LogDayGroup] {
        LogQuery.groups(journal.entries, filter: filter, matching: { Self.matches(query: searchText, text: text($0), flavor: flavor($0)) })
    }

    mutating func toggle(_ category: LogCategory) {
        filter.toggle(category)
    }

    mutating func clearFilters() {
        filter = LogFilter()
    }

    /// LOG-034: the selected rows as their LOG-024 bullet lines, oldest first.
    func copyText(journal: GameJournal, text: (LogEntry) -> String, flavor: (LogEntry) -> String?) -> String? {
        let rows = journal.entries.filter { selection.contains($0.id) }
        guard !rows.isEmpty else { return nil }
        return rows.flatMap { LogMarkdown.bullet($0, text: text, flavor: flavor) }.joined(separator: "\n") + "\n"
    }

    /// LOG-033: the export file's name.
    static func exportName(commander: String) -> String {
        String(localized: "\(commander) – Captain's Log")
    }
}

/// LOG-033: the Markdown export document (`fileExporter`).
nonisolated struct LogMarkdownDocument: FileDocument {
    static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [markdown] }
    static var writableContentTypes: [UTType] { [markdown] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = s
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// LOG-024 / LOG-033: the header and rendering of an export from the session's journal.
@MainActor
enum LogExport {
    static func header(state: GameState) -> LogMarkdownHeader {
        let names = state.galaxy.systems.indices.map { Names.system($0, in: state) }
        return LogMarkdownHeader(title: String(localized: "\(state.commander.name) – Captain's Log"),
                                 metadata: [state.commander.name, String(localized: Names.ruleset(state.rulesetID)),
                                            String(localized: Names.difficulty(state.difficulty)), GalaxyCode(state).string],
                                 groupHeading: { day, system in
                                     let name = names.indices.contains(system) ? names[system] : "\(system)"
                                     return String(localized: "Day \(day) · \(name)")
                                 })
    }

    /// LOG-033 with LLM-027: flavor lines are included only when "Show flavor text" is on.
    static func markdown(journal: GameJournal, state: GameState, filter: LogFilter, showFlavor: Bool) -> String {
        LogMarkdown.render(journal: journal, header: header(state: state), filter: filter,
                           text: { LogEntryText.text(for: $0, journal: journal, state: state) },
                           flavor: { showFlavor ? FlavorCatalogText.text(for: $0.flavor, state: state) : nil })
    }
}
