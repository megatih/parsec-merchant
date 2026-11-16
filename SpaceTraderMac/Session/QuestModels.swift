// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

// MARK: - Quests (UI-SHELL-086/087)

/// The Quests section: open-quest cards from `GameState.questLog` and the finished chains. Pure over the state.
struct QuestsModel: Equatable, Sendable {
    /// One stop of a multi-stop chain.
    struct Step: Equatable, Sendable {
        var system: Int
        var done: Bool
    }

    struct Card: Equatable, Sendable, Identifiable {
        var index: Int
        var entry: QuestLogEntry
        /// The stops of the Dragonfly or Princess chain, nil for single-stop quests.
        var steps: [Step]?
        /// The deadline gauge's full span in days, nil when the entry has no countdown.
        var deadlineSpan: Int?

        var id: Int { index }
    }

    /// A quest chain that is over.
    enum Chain: String, CaseIterable, Sendable {
        case gemulon, experiment, reactor, spaceMonster, japori, dragonfly, princess, scarab, sculpture, artifact
        case jarek, wild, moon

        var title: LocalizedStringResource {
            switch self {
            case .gemulon: "Alien invasion of Gemulon"
            case .experiment: "Dr. Fehler's experiment"
            case .reactor: "Unstable reactor"
            case .spaceMonster: "Space monster"
            case .japori: "Japori disease"
            case .dragonfly: "Dragonfly"
            case .princess: "The Princess"
            case .scarab: "Scarab"
            case .sculpture: "Stolen sculpture"
            case .artifact: "Alien artifact"
            case .jarek: "Ambassador Jarek"
            case .wild: "Jonathan Wild"
            case .moon: "Moon at Utopia"
            }
        }
    }

    struct Finished: Equatable, Sendable, Identifiable {
        var chain: Chain
        var failed: Bool

        var id: Chain { chain }
        var outcome: LocalizedStringResource { failed ? "Failed" : "Completed" }
    }

    static let dragonflyRoute = [SystemID.baratas, SystemID.melina, SystemID.regulas, SystemID.zalkon]
    static let princessRoute = [SystemID.centauri, SystemID.inthara, SystemID.qonos, SystemID.galvon]

    var cards: [Card]
    var finished: [Finished]

    static func make(state: GameState) -> QuestsModel {
        QuestsModel(cards: state.questLog.enumerated().map { i, entry in
                        Card(index: i, entry: entry, steps: steps(for: entry.kind), deadlineSpan: deadlineSpan(entry))
                    },
                    finished: finished(state.quests))
    }

    /// The chain progress: stops before the current one are done (Dragonfly Baratas → Zalkon, Princess
    /// Centauri → Galvon, where "return to Galvon" is the last stop).
    static func steps(for kind: QuestLogKind) -> [Step]? {
        let route: [Int], current: Int
        switch kind {
        case .dragonflyBaratas: (route, current) = (dragonflyRoute, 0)
        case .dragonflyMelina: (route, current) = (dragonflyRoute, 1)
        case .dragonflyRegulas: (route, current) = (dragonflyRoute, 2)
        case .dragonflyZalkon: (route, current) = (dragonflyRoute, 3)
        case .princessCentauri: (route, current) = (princessRoute, 0)
        case .princessInthara: (route, current) = (princessRoute, 1)
        case .princessQonos: (route, current) = (princessRoute, 2)
        case .princessReturn, .princessReturning, .princessReturningImpatient: (route, current) = (princessRoute, 3)
        default: return nil
        }
        return route.enumerated().map { Step(system: $1, done: $0 < current) }
    }

    /// Full span of the countdown: Gemulon 6 days, Experiment 10, Reactor 19 (UI-SHELL-121 day formulas at status 1).
    static func deadlineSpan(_ entry: QuestLogEntry) -> Int? {
        guard let days = entry.daysLeft else { return nil }
        let span: Int
        switch entry.kind {
        case .gemulonInformDays, .gemulonInformTomorrow: span = QuestStatus.Gemulon.date - QuestStatus.Gemulon.started
        case .experimentInformDays, .experimentInformTomorrow: span = QuestStatus.Experiment.date - QuestStatus.Experiment.started
        default: span = QuestStatus.Reactor.date - QuestStatus.Reactor.fuelOK
        }
        return max(span, days)
    }

    /// Chains whose status is a closed code, in quest-list order; Gemulon too late and Experiment performed failed.
    static func finished(_ q: QuestState) -> [Finished] {
        var out: [Finished] = []
        func add(_ c: Chain, _ done: Bool, failed: Bool = false) {
            if done || failed { out.append(Finished(chain: c, failed: failed)) }
        }
        add(.gemulon, q.gemulon == QuestStatus.Gemulon.done, failed: q.gemulon == QuestStatus.Gemulon.tooLate)
        add(.experiment, q.experiment == QuestStatus.Experiment.cancelled, failed: q.experiment == QuestStatus.Experiment.performed)
        add(.reactor, q.reactor == QuestStatus.Reactor.done)
        add(.spaceMonster, q.spaceMonster == QuestStatus.SpaceMonster.done)
        add(.japori, q.japori == QuestStatus.Japori.done)
        add(.dragonfly, q.dragonfly == QuestStatus.Dragonfly.done)
        add(.princess, q.princess == QuestStatus.Princess.done)
        add(.scarab, q.scarab == QuestStatus.Scarab.done)
        add(.sculpture, q.sculpture == QuestStatus.Sculpture.done)
        add(.artifact, q.artifact == QuestStatus.Artifact.done)
        add(.jarek, q.jarek == QuestStatus.Jarek.done)
        add(.wild, q.wild == QuestStatus.Wild.done)
        add(.moon, q.moon == QuestStatus.Moon.done)
        return out
    }
}

// MARK: - Find System (UI-SHELL-085)

/// The Find System sheet's logic. Pure over the state.
enum FindSystemModel {
    /// What Select does with the typed text.
    enum Outcome: Equatable, Sendable {
        /// Select the system as warp target, and track it when the toggle is on.
        case select(system: Int, track: Bool)
        /// "No system found." inline; the sheet stays open.
        case noMatch
        /// Nothing to do (empty text; Palm treats an empty Find as Cancel).
        case none
        /// A cheat code: perform it; `.enable` also opens the cheat console (CHEAT-013).
        case cheat(CheatCode)
        /// Palm "Very rare": the cheat console's very-rare form (CHEAT-040).
        case veryRareForm
        /// Palm "Timewarp": Open Saved Game after the CHEAT-046 warning (refused in Ironman).
        case timewarp
    }

    /// Case-insensitive substring matches over the system names, in galaxy order (C# `SelectedSystemName`).
    static func matches(_ text: String, in state: GameState) -> [Int] {
        guard !text.isEmpty else { return [] }
        let needle = text.lowercased()
        return state.galaxy.systems.indices.filter { Names.system($0, in: state).lowercased().contains(needle) }
    }

    /// Select: `FindInput.parse` (CHEAT-009/013); a search picks the first match (Game.cs:4302).
    static func resolve(_ text: String, track: Bool, state: GameState) -> Outcome {
        guard !text.isEmpty,
              let input = FindInput.parse(text, cheatSet: state.ruleset.content.cheatSet, cheatsEnabled: state.cheatsUsed)
        else { return .none }
        switch input {
        case let .search(query):
            guard let first = matches(query, in: state).first else { return .noMatch }
            return .select(system: first, track: track)
        case let .cheat(code): return .cheat(code)
        case .palmVeryRareForm: return .veryRareForm
        case .timewarp: return .timewarp
        }
    }

    /// The commands a selection sends.
    static func commands(for outcome: Outcome) -> [Command] {
        switch outcome {
        case let .select(system, track): track ? [.selectTarget(system), .track(system)] : [.selectTarget(system)]
        case let .cheat(code): [.cheat(code)]
        case .noMatch, .none, .veryRareForm, .timewarp: []
        }
    }
}

extension GameSession {
    /// A quest's system link, as the C# hyperlinks did: select the system as target, then show the Bridge (UI-SHELL-086).
    func selectQuestSystem(_ system: Int) {
        send(.selectTarget(system))
        if lastRejection == nil { selectedSection = .bridge }
    }

    /// Find System's Select: performs the outcome (UI-SHELL-085). Returns false when the sheet stays open.
    @discardableResult
    func performFind(_ outcome: FindSystemModel.Outcome) -> Bool {
        guard let state else { return false }
        switch outcome {
        case .noMatch:
            return false
        case .none:
            dismissPresentation()
        case .select, .cheat:
            dismissPresentation()
            for command in FindSystemModel.commands(for: outcome) { send(command) }
            if case .cheat(.enable) = outcome { present(.sheet(.cheatConsole)) }
        case .veryRareForm:
            dismissPresentation()
            present(.sheet(.cheatConsole))
        case .timewarp:
            // CHEAT-046: refused in an Ironman game; otherwise warn or confirm before Open Saved Game.
            guard !state.ironman else { return false }
            dismissPresentation()
            present(.appConfirmation(.timewarpLoad(reloaded: state.reloadCount > 0)))
        }
        return true
    }
}
