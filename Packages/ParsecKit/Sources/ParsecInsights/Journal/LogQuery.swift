// SPDX-License-Identifier: GPL-2.0-or-later
// Reading the log (docs/specs/LOG.md §5, LOG-022 and LOG-024): grouping, filtering and the Markdown export.

/// LOG-022: a set of categories; empty means every category.
public struct LogFilter: Sendable, Equatable {
    public var categories: [LogCategory]

    public init(_ categories: [LogCategory] = []) {
        self.categories = LogCategory.allCases.filter(categories.contains)
    }

    public static let all = LogFilter()

    public var isEmpty: Bool { categories.isEmpty }

    public func includes(_ entry: LogEntry) -> Bool {
        categories.isEmpty || categories.contains(entry.category)
    }

    /// Toggles one category.
    public mutating func toggle(_ category: LogCategory) {
        var set = categories
        if let i = set.firstIndex(of: category) { set.remove(at: i) } else { set.append(category) }
        self = LogFilter(set)
    }
}

/// LOG-022: consecutive entries of one day and system.
public struct LogDayGroup: Sendable, Equatable, Identifiable {
    public var day: Int
    public var system: Int
    public var entries: [LogEntry]

    public init(day: Int, system: Int, entries: [LogEntry]) {
        self.day = day
        self.system = system
        self.entries = entries
    }

    /// The id of the group's oldest entry.
    public var id: Int { entries.map(\.id).min() ?? 0 }
}

public enum LogQuery {
    /// LOG-022: entries passing the filter and the predicate, grouped by consecutive (day, system); newest group first
    /// and newest entry first within a group.
    public static func groups(_ entries: [LogEntry], filter: LogFilter = .all,
                              matching: (LogEntry) -> Bool = { _ in true }) -> [LogDayGroup] {
        oldestFirstGroups(entries, filter: filter, matching: matching).reversed().map {
            LogDayGroup(day: $0.day, system: $0.system, entries: $0.entries.reversed())
        }
    }

    /// The same groups, oldest first with entries oldest first (the Markdown order).
    static func oldestFirstGroups(_ entries: [LogEntry], filter: LogFilter,
                                  matching: (LogEntry) -> Bool) -> [LogDayGroup] {
        var out: [LogDayGroup] = []
        for entry in entries where filter.includes(entry) && matching(entry) {
            if let last = out.last, last.day == entry.day, last.system == entry.system {
                out[out.count - 1].entries.append(entry)
            } else {
                out.append(LogDayGroup(day: entry.day, system: entry.system, entries: [entry]))
            }
        }
        return out
    }
}

/// LOG-024: the export header, all text supplied (and localized) by the app.
public struct LogMarkdownHeader: Sendable, Equatable {
    public var title: String
    /// Metadata items (commander, ruleset, difficulty, galaxy code), joined with " · ".
    public var metadata: [String]
    /// Renders a group heading such as "Day 12 · Sol".
    public var groupHeading: @Sendable (_ day: Int, _ system: Int) -> String

    public init(title: String, metadata: [String], groupHeading: @escaping @Sendable (_ day: Int, _ system: Int) -> String) {
        self.title = title
        self.metadata = metadata
        self.groupHeading = groupHeading
    }

    public static func == (a: LogMarkdownHeader, b: LogMarkdownHeader) -> Bool {
        a.title == b.title && a.metadata == b.metadata
    }
}

public enum LogMarkdown {
    /// LOG-024: `# title`, the metadata line, then oldest first one `## heading` per day/system group and one bullet
    /// per entry, with an indented italic flavor line when present. Supplied text is escaped; ends with one newline.
    public static func render(journal: GameJournal, header: LogMarkdownHeader, filter: LogFilter = .all,
                              text: (LogEntry) -> String, flavor: (LogEntry) -> String?) -> String {
        render(entries: journal.entries, header: header, filter: filter, text: text, flavor: flavor)
    }

    /// LOG-024 over any entry list (LOG-034 copies the selected rows' bullets).
    public static func render(entries: [LogEntry], header: LogMarkdownHeader, filter: LogFilter = .all,
                              text: (LogEntry) -> String, flavor: (LogEntry) -> String?) -> String {
        var lines = ["# \(MarkdownText.escape(header.title))"]
        if !header.metadata.isEmpty { lines.append(header.metadata.map(MarkdownText.escape).joined(separator: " · ")) }
        for group in LogQuery.oldestFirstGroups(entries, filter: filter, matching: { _ in true }) {
            lines.append("")
            lines.append("## \(MarkdownText.escape(header.groupHeading(group.day, group.system)))")
            lines.append("")
            for entry in group.entries { lines += bullet(entry, text: text, flavor: flavor) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// LOG-024 / LOG-034: the bullet lines of one entry.
    public static func bullet(_ entry: LogEntry, text: (LogEntry) -> String, flavor: (LogEntry) -> String?) -> [String] {
        var lines = ["- \(MarkdownText.escape(text(entry)))"]
        if let f = flavor(entry), !f.isEmpty { lines.append("  *\(MarkdownText.escape(f))*") }
        return lines
    }
}
