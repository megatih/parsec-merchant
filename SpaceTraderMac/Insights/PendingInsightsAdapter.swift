// SPDX-License-Identifier: GPL-2.0-or-later
// TEMPORARY ADAPTER: stand-ins for the ParsecInsights / ParsecPersistence M10 types (INT/LOG/STAT/ACH/LLM proposal
// sections) while the package agent builds them. Deleted when those types land on main.
import Foundation
import ParsecEngine
import ParsecPersistence

// MARK: Flavor (LLM-001…009)

nonisolated enum FlavorSource: String, Codable, Sendable, Equatable { case template, foundationModels }

nonisolated enum FlavorArg: Codable, Sendable, Equatable {
    case system(Int), ship(ShipType), item(TradeItemType), count(Int), credits(Int), skill(SkillType)
}

nonisolated struct FlavorLine: Codable, Sendable, Equatable {
    var key: String
    var args: [FlavorArg]
}

nonisolated enum FlavorText: Codable, Sendable, Equatable {
    case template(FlavorLine)
    case generated(text: String)
    var source: FlavorSource {
        if case .generated = self { return .foundationModels }
        return .template
    }
}

nonisolated enum FlavorSubject: Codable, Sendable, Equatable {
    case arrival(system: Int, viaWormhole: Bool, firstVisit: Bool, uneventful: Bool, encounterCount: Int)
    case encounter(type: EncounterType, opponent: ShipType, result: EncounterResultClass, rounds: Int, minHullPercent: Int)
    case quest(SpecialEventType)
    case gameEnded(GameEndType)
    case achievement(AchievementID)
}

nonisolated struct FlavorRequest: Sendable, Equatable {
    var entryID: Int
    var day: Int
    var system: Int
    var subject: FlavorSubject
    init(entryID: Int, day: Int, system: Int, subject: FlavorSubject) {
        self.entryID = entryID; self.day = day; self.system = system; self.subject = subject
    }
    init?(entry: LogEntry) {
        guard let s = entry.kind.flavorSubject else { return nil }
        self.init(entryID: entry.id, day: entry.day, system: entry.system, subject: s)
    }
}

nonisolated protocol FlavorProvider: Sendable {
    var source: FlavorSource { get }
    func flavor(for request: FlavorRequest) async -> FlavorText?
}

nonisolated enum FlavorArgType: String, Sendable, Equatable, CaseIterable { case system, ship, item, count, credits, skill }

nonisolated struct FlavorCatalogEntry: Sendable, Equatable {
    var key: String
    var argTypes: [FlavorArgType]
}

nonisolated struct TemplateFlavorProvider: FlavorProvider {
    var source: FlavorSource { .template }
    init() {}
    func line(for request: FlavorRequest) -> FlavorLine { FlavorLine(key: "flavor.arrival.quiet.1", args: [.system(request.system)]) }
    func flavor(for request: FlavorRequest) async -> FlavorText? { .template(line(for: request)) }
    static let catalog: [FlavorCatalogEntry] = [FlavorCatalogEntry(key: "flavor.arrival.quiet.1", argTypes: [.system])]
}

// MARK: Journal (LOG)

nonisolated enum LogCategory: String, Codable, Sendable, CaseIterable {
    case trade, travel, encounter, police, finance, ship, crew, quest, news, status, achievement, game
}

nonisolated enum EncounterResultClass: String, Codable, Sendable, CaseIterable { case won, fled, surrendered, lost, other }

nonisolated enum JournalOrigin: String, Codable, Sendable { case newGame, resumed }

nonisolated struct JournalStart: Codable, Sendable, Equatable {
    var origin: JournalOrigin
    var rulesetID: RulesetID
    var difficulty: Difficulty
    var ironman: Bool
    var systemCount: Int
    var startSystem: Int
    var visitedSystems: [Int]
    var kills: Kills
}

nonisolated enum EncounterOutcomeKind: Codable, Sendable, Equatable {
    case destroyed(ShipType), disabled, escaped, opponentEscaped, plundered, traded, bribed(Int), fined(Int), inspectedClean
    case yielded, arrested, raided(units: Int), artifactSurrendered, drank(good: Bool), trained(SkillType), escapePod
    case killed, passed
}

nonisolated struct EncounterRecord: Codable, Sendable, Equatable {
    var type: EncounterType
    var opponent: ShipType
    var rounds: Int
    var outcome: EncounterOutcomeKind
    var bounty: Int
    var minHullPercent: Int
    var killsAfter: Kills
    var result: EncounterResultClass { .other }
}

nonisolated struct EncounterLedger: Codable, Sendable, Equatable {}

nonisolated enum TradeAction: String, Codable, Sendable {
    case buy, sell, dump, jettison, plunder, scoop, orbitBuy, orbitSell, sealedCanisters
}

nonisolated struct TradeEntry: Codable, Sendable, Equatable {
    var action: TradeAction
    var item: TradeItemType
    var quantity: Int
    var total: Int
    var profit: Int?
}

nonisolated enum LogEntryKind: Codable, Sendable, Equatable {
    case journalStarted(JournalStart)
    case cheatsEnabled
    case gameEnded(GameEndType, score: Int)
    case achievementUnlocked(AchievementID)
    case trade(TradeEntry)
    case encounter(EncounterRecord)

    var category: LogCategory {
        switch self {
        case .journalStarted, .cheatsEnabled, .gameEnded: .game
        case .achievementUnlocked: .achievement
        case .trade: .trade
        case .encounter: .encounter
        }
    }

    var flavorSubject: FlavorSubject? {
        switch self {
        case let .gameEnded(e, _): .gameEnded(e)
        case let .achievementUnlocked(a): .achievement(a)
        default: nil
        }
    }
}

nonisolated struct LogEntry: Codable, Sendable, Equatable, Identifiable {
    var id: Int
    var day: Int
    var system: Int
    var worth: Int
    var kind: LogEntryKind
    var flavor: FlavorText?
}

nonisolated struct GameJournal: Codable, Sendable, Equatable {
    var entries: [LogEntry] = []
    var nextEntryID = 1
    var intel = IntelBook(systems: [])
    var openEncounter: EncounterLedger?

    static func start(state: GameState) -> GameJournal { make(state: state, origin: .newGame) }
    static func bootstrap(from state: GameState) -> GameJournal { make(state: state, origin: .resumed) }

    private static func make(state: GameState, origin: JournalOrigin) -> GameJournal {
        var j = GameJournal()
        j.intel = IntelBook(systems: Array(repeating: SystemIntel(), count: state.galaxy.systems.count))
        let start = JournalStart(origin: origin, rulesetID: state.rulesetID, difficulty: state.difficulty, ironman: state.ironman,
                                 systemCount: state.galaxy.systems.count, startSystem: state.commander.currentSystem,
                                 visitedSystems: [], kills: state.commander.kills)
        j.entries = [LogEntry(id: 1, day: state.commander.days, system: state.commander.currentSystem, worth: state.worth,
                              kind: .journalStarted(start), flavor: nil)]
        j.nextEntryID = 2
        return j
    }
}

nonisolated struct JournalStep: Sendable {
    var command: Command
    var before: GameState
    var result: StepResult
    var after: GameState
}

nonisolated struct JournalStepOutput: Sendable, Equatable {
    var newEntries: [LogEntry] = []
    var unlocked: [AchievementID] = []
}

nonisolated enum JournalRecorder {
    static func record(_ step: JournalStep, into journal: inout GameJournal) -> JournalStepOutput { JournalStepOutput() }
}

nonisolated struct LogFilter: Sendable, Equatable {
    var categories: [LogCategory]
    init(_ categories: [LogCategory] = []) { self.categories = LogCategory.allCases.filter(categories.contains) }
    static let all = LogFilter()
    var isEmpty: Bool { categories.isEmpty }
    mutating func toggle(_ category: LogCategory) {
        var set = categories
        if let i = set.firstIndex(of: category) { set.remove(at: i) } else { set.append(category) }
        self = LogFilter(set)
    }
}

nonisolated struct LogDayGroup: Sendable, Equatable, Identifiable {
    var day: Int
    var system: Int
    var entries: [LogEntry]
    var id: Int { entries.map(\.id).min() ?? 0 }
}

nonisolated enum LogQuery {
    static func groups(_ entries: [LogEntry], filter: LogFilter, matching: (LogEntry) -> Bool) -> [LogDayGroup] {
        let kept = entries.filter { (filter.categories.isEmpty || filter.categories.contains($0.kind.category)) && matching($0) }
        var groups: [LogDayGroup] = []
        for e in kept.reversed() {
            if let last = groups.last, last.day == e.day, last.system == e.system {
                groups[groups.count - 1].entries.append(e)
            } else {
                groups.append(LogDayGroup(day: e.day, system: e.system, entries: [e]))
            }
        }
        return groups
    }
}

nonisolated struct LogMarkdownHeader: Sendable {
    var title: String
    var metadata: [String]
    var groupHeading: @Sendable (_ day: Int, _ system: Int) -> String
}

nonisolated enum LogMarkdown {
    static func render(journal: GameJournal, header: LogMarkdownHeader, filter: LogFilter = .all, text: (LogEntry) -> String,
                       flavor: (LogEntry) -> String?) -> String {
        "# \(header.title)\n"
    }
    static func render(entries: [LogEntry], header: LogMarkdownHeader, filter: LogFilter = .all, text: (LogEntry) -> String,
                       flavor: (LogEntry) -> String?) -> String {
        "# \(header.title)\n"
    }
    static func bullet(_ entry: LogEntry, text: (LogEntry) -> String, flavor: (LogEntry) -> String?) -> [String] {
        ["- \(MarkdownText.escape(text(entry)))"]
    }
}

nonisolated enum MarkdownText {
    static func escape(_ text: String) -> String { text }
}

// MARK: Stats (STAT)

nonisolated struct WorthSample: Codable, Sendable, Equatable { var day: Int; var worth: Int }
nonisolated struct BestSale: Codable, Sendable, Equatable { var item: TradeItemType; var quantity: Int; var profit: Int; var day: Int; var system: Int }

nonisolated enum StatFigureKind: String, Sendable, CaseIterable {
    case daysPlayed, parsecsTravelled, systemsVisited, wormholeJumps, trades, totalTradeProfit, bestTrade
    case encountersWon, encountersFled, encountersSurrendered, killsPirates, killsPolice, killsTraders
    case bounties, finesAndBribes, arrests, peakWorth
}

nonisolated enum StatFigureValue: Sendable, Equatable {
    case days(Int), parsecs(Int), systems(visited: Int, of: Int), credits(Int), count(Int), trade(BestSale?)
}

nonisolated struct StatFigure: Sendable, Equatable { var kind: StatFigureKind; var value: StatFigureValue }

nonisolated struct CareerStats: Sendable, Equatable {
    var startDay: Int?
    var lastDay: Int?
    var daysPlayed: Int { (lastDay ?? 0) - (startDay ?? 0) }
    var parsecsTravelled = 0
    var systemCount = 0
    var visitedCount = 0
    var peakWorth: Int?
    var won = 0, fled = 0, surrendered = 0, lost = 0, otherResults = 0
    var profitByItem: [Int] = Array(repeating: 0, count: TradeItemType.allCases.count)
    var destroyedByShipType: [Int] = Array(repeating: 0, count: ShipType.allCases.count)
    var bestSale: BestSale?
    var cheatsUsed = false
    var isPartial = false
    var achievementsUnlocked = 0
    var worthSamples: [WorthSample] = []

    static func fold(_ entries: [LogEntry]) -> CareerStats { entries.reduce(into: CareerStats()) { $0.add($1) } }
    mutating func add(_ entry: LogEntry) {
        lastDay = entry.day
        if case let .journalStarted(s) = entry.kind {
            startDay = entry.day
            systemCount = s.systemCount
            isPartial = s.origin == .resumed
        }
        if case .cheatsEnabled = entry.kind { cheatsUsed = true }
        if case .achievementUnlocked = entry.kind { achievementsUnlocked += 1 }
    }
    func worthSeries(maxPoints: Int) -> [WorthSample] { worthSamples }
    var figures: [StatFigure] { [StatFigure(kind: .daysPlayed, value: .days(daysPlayed))] }
}

nonisolated enum StatsMarkdown {
    static func render(stats: CareerStats, header: (label: String, value: String), labels: (StatFigureKind) -> String,
                       values: (StatFigureValue) -> String) -> String {
        stats.figures.map { "| \(labels($0.kind)) | \(values($0.value)) |" }.joined(separator: "\n") + "\n"
    }
}

// MARK: Achievements (ACH)

nonisolated enum AchievementID: String, Codable, Sendable, CaseIterable {
    case firstProfit, worth10k, worth100k, worth1m, dragonfly, spaceMonster, scarab, japori, jarek, wild, reactor, gemulon
    case experiment, artifact, sculpture, princess, moon, waspKiller, closeCall, hero, villain, debtFree, explorer50
    case explorerAll, wormhole, winHard, winImpossible, allCommodities, tribbleMax, marieCeleste, famousCaptains, escapePod
    case designer, ironman, bountyHunter, bigScore
}

nonisolated enum AchievementKind: Sendable, Equatable { case threshold(target: Int), flag }

nonisolated struct AchievementProgress: Sendable, Equatable {
    var id: AchievementID
    var current: Int
    var target: Int
    var satisfied: Bool
}

nonisolated enum AchievementCatalog {
    static func evaluate(_ stats: CareerStats, ruleset: Ruleset) -> [AchievementProgress] {
        AchievementID.allCases.filter { isAvailable($0, ruleset: ruleset) }
            .map { AchievementProgress(id: $0, current: 0, target: 1, satisfied: false) }
    }
    static func satisfied(_ stats: CareerStats, ruleset: Ruleset) -> [AchievementID] { [] }
    static func available(in ruleset: Ruleset) -> [AchievementID] { AchievementID.allCases.filter { isAvailable($0, ruleset: ruleset) } }
    static func isAvailable(_ id: AchievementID, ruleset: Ruleset) -> Bool {
        id != .designer || ruleset.content.hasShipyards
    }
}

nonisolated struct AchievementRecord: Codable, Sendable, Equatable {
    var id: String
    var unlockedAt: String
    var gameID: String
    var rulesetID: String
    var day: Int
}

nonisolated struct AchievementStore: Sendable {
    let root: URL
    private var stored: [AchievementRecord] = []
    init(root: URL, clock: @escaping @Sendable () -> Date = { Date() }) { self.root = root }
    mutating func unlock(_ ids: [String], gameID: String, rulesetID: String, day: Int) throws -> [String] {
        let new = ids.filter { id in !stored.contains { $0.id == id } }
        stored += new.map { AchievementRecord(id: $0, unlockedAt: "2026-01-01T00:00:00Z", gameID: gameID, rulesetID: rulesetID, day: day) }
        return new
    }
    func records() throws -> [AchievementRecord] { stored }
    func isUnlocked(_ id: String) throws -> Bool { stored.contains { $0.id == id } }
    mutating func reset() throws { stored = [] }
}

// MARK: Intel (INT)

nonisolated enum PressureHintSource: String, Codable, Sendable { case news, observed }
nonisolated struct PressureHint: Codable, Sendable, Equatable { var pressure: SystemPressure; var day: Int; var source: PressureHintSource }
nonisolated struct MarketObservation: Codable, Sendable, Equatable {
    var day: Int; var buy: [Int]; var sell: [Int]; var stock: [Int]; var pressure: SystemPressure
}
nonisolated struct SystemIntel: Codable, Sendable, Equatable {
    var lastVisitDay: Int?
    var visitCount = 0
    var history: [MarketObservation] = []
    var pressureHint: PressureHint?
    var latest: MarketObservation? { history.last }
}
nonisolated struct IntelBook: Codable, Sendable, Equatable { var systems: [SystemIntel] }

nonisolated struct AdapterSystemFacts: Sendable, Equatable {
    var visited: Bool
    var knownResource: SpecialResource
}

nonisolated struct IntelSnapshot: Sendable, Equatable {
    var day: Int
    var currentSystem: Int
    var isDocked: Bool
    var destinations: [Int]
    var systems: [AdapterSystemFacts]
    var cargo: [Int]
    var hasCargo: Bool { cargo.contains { $0 > 0 } }
    init(_ state: GameState) {
        day = state.commander.days
        currentSystem = state.commander.currentSystem
        isDocked = state.phase == .docked
        destinations = state.destinations
        systems = state.galaxy.systems.map { AdapterSystemFacts(visited: $0.visited, knownResource: $0.knownResource) }
        cargo = state.commander.ship.cargo
    }
}

nonisolated enum QuoteSource: Sendable, Equatable { case live, observed(day: Int), estimate }
nonisolated enum Staleness: Sendable, Equatable { case live, fresh, old, estimate }

nonisolated struct PriceQuote: Sendable, Equatable {
    var item: TradeItemType
    var system: Int
    var sell: Int?
    var buy: Int?
    var stock: Int?
    var source: QuoteSource
    var age: Int?
    var staleness: Staleness
    var pressureHint: PressureHint?
}

nonisolated struct TradeRecommendation: Sendable, Equatable {
    var item: TradeItemType; var profitPerBay: Int; var units: Int; var projectedProfit: Int; var quoteSource: QuoteSource
    var staleness: Staleness
}
nonisolated struct HoldValue: Sendable, Equatable {
    var revenue: Int; var costBasis: Int; var profit: Int; var unsellable: [TradeItemType]; var usesEstimates: Bool
}
nonisolated struct DestinationRecommendation: Sendable, Equatable {
    var system: Int; var profit: Int; var distance: Int; var usesEstimates: Bool
}
nonisolated struct SellAdvice: Sendable, Equatable {
    var item: TradeItemType; var herePerUnit: Int?; var bestSystem: Int?; var bestSell: Int?; var bestPerUnit: Int?
    var bestSource: QuoteSource?; var bestAge: Int?
}

nonisolated enum SellsMatch: Sendable, Equatable { case observed, estimate }

nonisolated enum TradeIntel {
    static func sells(item: TradeItemType, system: Int, book: IntelBook, snapshot: IntelSnapshot) -> SellsMatch? { nil }
    static func estimate(item: TradeItemType, system: Int, snapshot: IntelSnapshot) -> Int { 0 }
    static func quote(item: TradeItemType, system: Int, book: IntelBook, snapshot: IntelSnapshot) -> PriceQuote {
        PriceQuote(item: item, system: system, sell: nil, buy: nil, stock: nil, source: .estimate, age: nil, staleness: .estimate,
                   pressureHint: nil)
    }
    static func profitPerBay(item: TradeItemType, target: Int, book: IntelBook, snapshot: IntelSnapshot) -> Int? { nil }
    static func bestBuys(for target: Int, book: IntelBook, snapshot: IntelSnapshot, limit: Int = 3) -> [TradeRecommendation] { [] }
    static func holdValue(at system: Int, book: IntelBook, snapshot: IntelSnapshot) -> HoldValue {
        HoldValue(revenue: 0, costBasis: 0, profit: 0, unsellable: [], usesEstimates: false)
    }
    static func bestDestinations(book: IntelBook, snapshot: IntelSnapshot, limit: Int = 3) -> [DestinationRecommendation] { [] }
    static func sellAdvice(item: TradeItemType, book: IntelBook, snapshot: IntelSnapshot) -> SellAdvice? { nil }
}

nonisolated enum PriceFactor: String, Sendable, CaseIterable {
    case base, wanted, traderActivity, size, resource, pressure, criminal, fluctuation, buyMarkup
}
nonisolated struct PriceExplanationStep: Sendable, Equatable {
    var factor: PriceFactor; var valueAfter: Int; var delta: Int
    var isNeutral: Bool { delta == 0 }
}
nonisolated struct PriceExplanation: Sendable, Equatable {
    var steps: [PriceExplanationStep]
    static func make(_ b: PriceBreakdown) -> PriceExplanation { PriceExplanation(steps: []) }
}

nonisolated enum HeatmapMode: Sendable, Hashable {
    case none, price(TradeItemType), holdProfit, police, pirates, techLevel, lastVisited
}
nonisolated enum HeatmapNote: Sendable, Equatable { case estimate, dateUnknown }
nonisolated struct HeatmapValue: Sendable, Equatable { var value: Int?; var note: HeatmapNote?; var age: Int? }
nonisolated struct HeatmapScale: Sendable, Equatable { var min: Int; var max: Int }
nonisolated struct HeatmapResult: Sendable, Equatable { var values: [HeatmapValue]; var scale: HeatmapScale }
nonisolated enum HeatmapModel {
    static func values(mode: HeatmapMode, intel: IntelBook, snapshot: IntelSnapshot) -> HeatmapResult {
        HeatmapResult(values: [], scale: HeatmapScale(min: 0, max: 0))
    }
}

// MARK: Persistence (LOG-007)

extension SlotStore {
    nonisolated func save(_ state: GameState, journal: GameJournal?, slot id: String, gameID: String) throws -> URL {
        try save(state, slot: id, gameID: gameID)
    }
    nonisolated func autosave(_ state: GameState, journal: GameJournal?, gameID: String) throws -> URL {
        try autosave(state, gameID: gameID)
    }
}

extension LoadedGame {
    nonisolated var journal: GameJournal { .bootstrap(from: state) }
}
