// SPDX-License-Identifier: GPL-2.0-or-later
// Chart series, figure tiles and the Markdown table of the statistics (docs/specs/STAT.md §3, STAT-013/014/019).
import ParsecEngine

/// STAT-014: the Statistics tiles, in display order.
public enum StatFigureKind: String, Sendable, Equatable, CaseIterable {
    case daysPlayed, parsecsTravelled, systemsVisited, wormholeJumps, trades, totalTradeProfit, bestTrade
    case encountersWon, encountersFled, encountersSurrendered, killsPirates, killsPolice, killsTraders
    case bounties, finesAndBribes, arrests, peakWorth
}

/// STAT-014: a typed figure value; the app formats it.
public enum StatFigureValue: Sendable, Equatable {
    case days(Int)
    case parsecs(Int)
    case systems(visited: Int, of: Int)
    case credits(Int)
    case count(Int)
    /// The best single sale, or nil before the first sale.
    case trade(BestSale?)
}

/// STAT-014: one tile.
public struct StatFigure: Sendable, Equatable {
    public var kind: StatFigureKind
    public var value: StatFigureValue

    public init(kind: StatFigureKind, value: StatFigureValue) {
        self.kind = kind
        self.value = value
    }
}

public extension CareerStats {
    /// STAT-013: at most `maxPoints` samples. Longer series are bucketed by day (`maxPoints − 1` equal integer
    /// buckets, keeping the last sample of each non-empty bucket) after the first sample, so the first and last
    /// samples are always kept.
    func worthSeries(maxPoints: Int) -> [WorthSample] {
        guard maxPoints > 0 else { return [] }
        guard worthSamples.count > maxPoints, let first = worthSamples.first, let last = worthSamples.last else {
            return worthSamples
        }
        guard maxPoints > 1 else { return [last] }
        let buckets = maxPoints - 1
        let span = last.day - first.day + 1
        var out = [first]
        var current = -1
        for sample in worthSamples.dropFirst() {
            let bucket = (sample.day - first.day) * buckets / span
            if bucket == current {
                out[out.count - 1] = sample
            } else {
                out.append(sample)
                current = bucket
            }
        }
        return out
    }

    /// STAT-014: the tiles in their fixed order.
    var figures: [StatFigure] {
        StatFigureKind.allCases.map { StatFigure(kind: $0, value: value(of: $0)) }
    }

    /// STAT-014: the value of one tile.
    func value(of kind: StatFigureKind) -> StatFigureValue {
        switch kind {
        case .daysPlayed: .days(daysPlayed)
        case .parsecsTravelled: .parsecs(parsecsTravelled)
        case .systemsVisited: .systems(visited: visitedCount, of: systemCount)
        case .wormholeJumps: .count(wormholeJumps)
        case .trades: .count(buys + sells)
        case .totalTradeProfit: .credits(totalTradeProfit)
        case .bestTrade: .trade(bestSale)
        case .encountersWon: .count(won)
        case .encountersFled: .count(fled)
        case .encountersSurrendered: .count(surrendered)
        case .killsPirates: .count(kills.pirates)
        case .killsPolice: .count(kills.police)
        case .killsTraders: .count(kills.traders)
        case .bounties: .credits(bountyTotal)
        case .finesAndBribes: .credits(finesPaid + bribesPaid)
        case .arrests: .count(arrests)
        case .peakWorth: .credits(peakWorth ?? 0)
        }
    }
}

/// STAT-019: the statistics as a two-column Markdown table (labels and formatted values supplied by the app).
public enum StatsMarkdown {
    public static func render(stats: CareerStats, header: (label: String, value: String),
                              labels: (StatFigureKind) -> String, values: (StatFigureValue) -> String) -> String {
        var lines = ["| \(MarkdownText.escape(header.label)) | \(MarkdownText.escape(header.value)) |", "|---|---:|"]
        for figure in stats.figures {
            lines.append("| \(MarkdownText.escape(labels(figure.kind))) | \(MarkdownText.escape(values(figure.value))) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// LOG-024 / STAT-019: Markdown escaping of supplied text.
public enum MarkdownText {
    /// Characters with Markdown meaning that are backslash-escaped (LOG-024), plus `|` for table cells.
    static let special: Set<Character> = ["\\", "*", "_", "[", "]", "#", "<", ">", "`", "|"]

    /// Escapes Markdown-significant characters and folds line breaks into spaces.
    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for c in text {
            if c == "\n" || c == "\r" || c == "\r\n" {
                out.append(" ")
                continue
            }
            if special.contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }
}
