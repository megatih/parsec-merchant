// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-002: what the plunder sheet plunders.
struct PlunderSheetContext: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        /// A surrendered or disabled opponent.
        case opponent
        /// The derelict Marie Celeste after boarding (ENC-161).
        case marieCeleste
    }

    /// Units per `TradeItemType` raw value, as in `PendingDecision.plunder`.
    var victimCargo: [Int]
    var source: Source
}

/// UI-ENC-074: one page of the narrative sheet.
enum NarrativePage: Equatable, Sendable {
    /// The offer of the current system's special event (the `acceptSpecialEvent` consent, UI-ENC-076).
    case offer(SpecialEventType)
    /// The result page after an accepted step (UI-ENC-077/078).
    case result(NarrativeResult)

    var key: String {
        switch self {
        case let .offer(type): "offer.\(type)"
        case let .result(r): "result.\(r.key)"
        }
    }
}

/// UI-ENC-078: a narrative result page (built by `NarrativeText.result`).
struct NarrativeResult: Equatable, Sendable {
    /// The special event the page belongs to, when there is one (the key of the page).
    var type: SpecialEventType?
    var title: String
    var message: String

    var key: String { type.map { "\($0)" } ?? "message" }
}

/// UI-ENC-058: the report sheets. The report models are filled by the arrival-report builders (UI-ENC-053…060).
enum ReportSheet: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case arrival, arrest, escapePod, reactorMeltdown
    }

    case arrival(ArrivalReport)
    case arrest(ArrestReport)
    case escapePod(EscapePodReport)
    case reactorMeltdown(ReactorReport)

    var kind: Kind {
        switch self {
        case .arrival: .arrival
        case .arrest: .arrest
        case .escapePod: .escapePod
        case .reactorMeltdown: .reactorMeltdown
        }
    }
}

/// A titled list of report lines (shared by the report models until their own sections are specified in code).
struct ReportSection: Equatable, Sendable {
    var title: String
    var lines: [String]
}

/// UI-ENC-054: the arrival report (sections in UX order). Built by `ArrivalReport.make(trip:after:)`.
struct ArrivalReport: Equatable, Sendable {
    var sections: [ReportSection] = []
}

/// UI-ENC-059: the arrest report.
struct ArrestReport: Equatable, Sendable {
    var sections: [ReportSection] = []
}

/// UI-ENC-060: the escape-pod report.
struct EscapePodReport: Equatable, Sendable {
    var sections: [ReportSection] = []
}

/// UI-ENC-060: the reactor-meltdown report.
struct ReactorReport: Equatable, Sendable {
    var sections: [ReportSection] = []
}
