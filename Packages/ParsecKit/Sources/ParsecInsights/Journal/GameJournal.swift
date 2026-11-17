// SPDX-License-Identifier: GPL-2.0-or-later
// The game journal (docs/specs/LOG.md §1, LOG-001…007; ADR-0003): the log, intel and the open encounter, saved in the
// envelope beside `state`. Structs, enums, arrays, Int, Bool and String only (deterministic sorted-key JSON).
import ParsecEngine

/// LOG-002: the persistent, typed history of one game.
public struct GameJournal: Codable, Sendable {
    public var entries: [LogEntry]
    /// The id of the next entry (ids start at 1 and are never reused).
    public var nextEntryID: Int
    public var intel: IntelBook
    public var openEncounter: EncounterLedger?

    /// Statistics of `entries` (a cache for the recorder; not saved and not compared).
    var statsCache: CareerStats?

    enum CodingKeys: String, CodingKey {
        case entries, nextEntryID, intel, openEncounter
    }

    public init(entries: [LogEntry] = [], nextEntryID: Int = 1, intel: IntelBook, openEncounter: EncounterLedger? = nil) {
        self.entries = entries
        self.nextEntryID = nextEntryID
        self.intel = intel
        self.openEncounter = openEncounter
    }

    /// LOG-005: the journal of a new game (New Game, Quick Start, scenarios).
    public static func start(state: GameState) -> GameJournal {
        make(state: state, origin: .newGame)
    }

    /// LOG-006 / INT-010: a journal for a state that has none (a partial history).
    public static func bootstrap(from state: GameState) -> GameJournal {
        make(state: state, origin: .resumed)
    }

    private static func make(state: GameState, origin: JournalOrigin) -> GameJournal {
        let systems = state.galaxy.systems
        let current = state.commander.currentSystem
        var intel = IntelBook(systemCount: systems.count)
        let visited: [Int]
        switch origin {
        case .newGame:
            visited = systems.indices.filter { systems[$0].visited || $0 == current }
            intel.visit(current, day: state.commander.days)
        case .resumed:
            visited = systems.indices.filter { systems[$0].visited }
            for i in visited where i != current { intel.systems[i].visitCount = 1 }
            intel.visit(current, day: state.commander.days)
        }
        intel.observe(state)
        let start = JournalStart(origin: origin, rulesetID: state.rulesetID, difficulty: state.difficulty,
                                 ironman: state.ironman, systemCount: systems.count, startSystem: current,
                                 visitedSystems: visited, kills: state.commander.kills)
        var journal = GameJournal(intel: intel)
        journal.append(.journalStarted(start), state: state)
        if state.cheatsUsed { journal.append(.cheatsEnabled, state: state) }
        return journal
    }

    /// LOG-008: appends an entry stamped with the state's day, system and worth.
    @discardableResult
    mutating func append(_ kind: LogEntryKind, state: GameState) -> LogEntry {
        let entry = LogEntry(id: nextEntryID, day: state.commander.days, system: state.commander.currentSystem,
                             worth: state.worth, kind: kind)
        nextEntryID += 1
        entries.append(entry)
        statsCache?.add(entry)
        return entry
    }

    /// The statistics of every entry (STAT-001), served from the cache when it is current.
    public var stats: CareerStats {
        mutating get {
            if let cached = statsCache, cached.entryCount == entries.count { return cached }
            let folded = CareerStats.fold(entries)
            statsCache = folded
            return folded
        }
    }

    /// LLM-021: replaces the flavor of the entry with `id`; false when there is none.
    @discardableResult
    public mutating func setFlavor(_ flavor: FlavorText?, forEntry id: Int) -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries[i].flavor = flavor
        return true
    }
}

extension GameJournal: Equatable {
    public static func == (a: GameJournal, b: GameJournal) -> Bool {
        a.entries == b.entries && a.nextEntryID == b.nextEntryID && a.intel == b.intel && a.openEncounter == b.openEncounter
    }
}
