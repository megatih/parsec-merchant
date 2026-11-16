// SPDX-License-Identifier: GPL-2.0-or-later
// CHEAT {M6}: cheat codes, Find-text parsing and the direct-warp cheat (docs/specs/CHEAT.md, TRV-085).
import Foundation
import Testing
@testable import ParsecEngine

/// Shared builders for the CHEAT spec tests.
enum CheatKit {
    /// A docked game that has already typed "Cheetah" (so every code of the set is unlocked).
    static func engine(_ id: RulesetID = .windows201, seed: UInt64 = 42, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
        makeEngine(id, seed: seed) { s in
            s.cheatsUsed = true
            adjust(&s)
        }
    }

    /// A Grasshopper (2 weapon, 2 shield, 3 gadget slots, 3 quarters) with only the commander aboard.
    static func grasshopper(_ s: inout GameState) {
        var ship = Ship(type: .grasshopper, spec: s.ruleset.tables.ship(.grasshopper))
        ship.crew[0] = CrewID.commander
        s.commander.ship = ship
    }

    /// A system whose exact name the C# "Go" search selects (no lower-index name contains it), other than `avoid`.
    static func goTarget(_ s: GameState, near start: Int, avoid: Int) -> Int {
        let names = s.ruleset.tables.systemNames
        var t = start
        while t == avoid || names.firstIndex(where: { $0.lowercased().contains(names[t].lowercased()) }) != t {
            t = (t + 1) % names.count
        }
        return t
    }

    /// Every Windows code with in-range arguments, except `go` and `dismissEncounter` (which run the trip pipelines).
    static let windowsCodes: [CheatCode] = [
        .enable, .bazaar(7), .cover(slot: 0, shield: 1), .deLorean(9), .diamond, .energize, .events, .eventsReset, .fame(300),
        .ice(.pirate, 3), .ice(nil, 3), .indemnity(4), .iou(500), .iron(slot: 0, weapon: 2), .juice(3),
        .knack(mercenary: 1, skills: [2, nil, 9, 4]), .lEngle(10), .lifeBoat, .monsterListing, .planB,
        .posse(slot: 1, mercenary: 5), .rapSheet(-8), .rarity(20), .scratch(12_345), .skin(5), .status(.moon, 1), .statusList,
        .swag(item: 2, quantity: 3), .test, .tool(slot: 0, gadget: 3), .varmints(12), .yellow,
    ]

    static let palmCodes: [CheatCode] = [
        .enable, .moolah, .veryRare(happened: [.captainAhab], chanceOfVeryRare: 9, chanceOfTradeInOrbit: 300),
        .palmCheatForm(PalmCheatForm(credits: 5, lightningShield: true, singularity: true)), .palmGo("D"), .quests,
    ]

    static func readout(_ r: StepResult) -> CheatReadout? {
        for ev in r.events { if case let .cheatReadout(x) = ev { return x } }
        return nil
    }

    /// The state with `cheatsUsed` as it was before (to compare "nothing else changed").
    static func sansFlag(_ s: GameState, _ flag: Bool) -> GameState {
        var c = s
        c.cheatsUsed = flag
        return c
    }
}

@Suite("CHEAT §1: command, flagging and availability")
struct CheatCommandTests {
    @Test("CHEAT-001 an accepted cheat sets cheatsUsed and emits cheatUsed first; listings flag too; a rejected cheat changes nothing")
    func flagging() {
        var e = makeEngine(.windows201)
        #expect(!e.state.cheatsUsed)
        let before = e.state
        // Locked code: rejected, nothing changes (the flag included).
        #expect(e.perform(.cheat(.scratch(99))).rejection == .invalidArgument)
        #expect(e.state == before)
        let r = e.perform(.cheat(.enable))
        #expect(r.rejection == nil && r.events == [.cheatUsed] && e.state.cheatsUsed)
        let listing = e.perform(.cheat(.statusList))
        #expect(listing.events.first == .cheatUsed && listing.events.count == 2)
        // A read-only Palm code flags a fresh game.
        var p = makeEngine(.palm122)
        let q = p.perform(.cheat(.quests))
        #expect(q.rejection == nil && q.events.first == .cheatUsed && p.state.cheatsUsed)
    }

    @Test("CHEAT-002 cheatsUsed is never cleared: no command resets it, new games start false, a JSON round trip keeps it")
    func permanent() throws {
        for id in RulesetID.allCases {
            var e = makeEngine(id, seed: 3)
            #expect(!e.state.cheatsUsed)
            _ = e.perform(.cheat(.enable))
            let commands: [Command] = [.setOptions(GameOptions()), .buyFuel(credits: 10), .borrow(100), .selectTarget(2), .track(3),
                                       .readNewspaper, .warp, .encounter(.flee), .plunderDone, .retire]
            for c in commands { _ = e.perform(c, acknowledging: Set(WarningID.allCases)) }
            #expect(e.state.cheatsUsed)
            let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
            #expect(decoded.cheatsUsed && decoded == e.state)
        }
    }

    @Test("CHEAT-003 after enable a qualifying retirement is excludedForCheats and not stored, in every ruleset (Palm included)")
    func consequences() {
        for id in RulesetID.allCases {
            var e = makeEngine(id)
            _ = e.perform(.cheat(.enable))
            _ = e.perform(.retire, acknowledging: [.retire])
            guard case let .gameOver(end) = e.state.phase else {
                Issue.record("retire did not end the game")
                continue
            }
            let entry = e.state.highScoreEntry(for: end)
            #expect(HighScoreTable().qualifies(entry))
            let (table, outcome) = HighScoreTable().inserting(entry, eligible: e.state.highScoreExclusion)
            #expect(outcome == .excludedForCheats && table.entries.isEmpty)
            #expect(e.state.cheatsUsed)
        }
    }

    @Test("CHEAT-005 cheats need docked with no pending decision (notAllowedInPhase); an ended game rejects them with gameOver")
    func phases() {
        var enc = CheatKit.engine { s in
            s.encounterTransit = TransitState(destination: s.warpSystem, clicksRemaining: 1, viaWormhole: false)
            s.phase = .encounter(EncounterState(type: .pirateAttack, opponent: EncSpec.gnat(s), clicks: 1))
        }
        #expect(enc.perform(.cheat(.scratch(5))).rejection == .notAllowedInPhase)
        #expect(enc.perform(.cheat(.enable)).rejection == .notAllowedInPhase)
        var transit = CheatKit.engine { s in
            s.phase = .inTransit(TransitState(destination: s.warpSystem, clicksRemaining: 3, viaWormhole: false))
        }
        #expect(transit.perform(.cheat(.scratch(5))).rejection == .notAllowedInPhase)
        var pending = CheatKit.engine { $0.pendingScoop = .water }
        #expect(pending.perform(.cheat(.scratch(5))).rejection == .notAllowedInPhase)
        var over = CheatKit.engine { $0.phase = .gameOver(.retired) }
        #expect(over.perform(.cheat(.scratch(5))).rejection == .gameOver)
        #expect(over.perform(.cheat(.dismissEncounter)).rejection == .gameOver)
    }

    @Test("CHEAT-006 no cheat other than the C# Go warp (and the trip a dismissed encounter resumes) draws from the game RNG")
    func noDraws() {
        for code in CheatKit.windowsCodes {
            var e = CheatKit.engine { s in CheatKit.grasshopper(&s) }
            let rng = e.state.rng
            #expect(e.perform(.cheat(code)).rejection == nil, "\(code)")
            #expect(e.state.rng == rng, "\(code)")
        }
        for code in CheatKit.palmCodes {
            var e = CheatKit.engine(.palm122) { s in CheatKit.grasshopper(&s) }
            let rng = e.state.rng
            #expect(e.perform(.cheat(code)).rejection == nil, "\(code)")
            #expect(e.state.rng == rng, "\(code)")
        }
        // The exact-match Go runs CalculatePrices and the arrival pipeline, which draw.
        var go = CheatKit.engine()
        let target = CheatKit.goTarget(go.state, near: 5, avoid: go.state.commander.currentSystem)
        let rng = go.state.rng
        _ = go.perform(.cheat(.go(go.state.systemName(target))))
        #expect(go.state.rng != rng && go.state.commander.currentSystem == target)
    }

    @Test("CHEAT-007 the cheat set is ruleset content: windows in Modern and Windows 2.01, palm in Palm; foreign codes are invalidArgument")
    func cheatSets() {
        #expect(Ruleset.modern.content.cheatSet == .windows && Ruleset.windows201.content.cheatSet == .windows)
        #expect(Ruleset.palm122.content.cheatSet == .palm)
        var w = CheatKit.engine(.windows201)
        for code in [CheatCode.moolah, .quests, .palmGo("A"), .palmCheatForm(PalmCheatForm())] {
            #expect(w.perform(.cheat(code)).rejection == .invalidArgument, "\(code)")
        }
        var p = CheatKit.engine(.palm122)
        for code in [CheatCode.scratch(5), .go("Acamar"), .yellow, .dismissEncounter, .statusList] {
            #expect(p.perform(.cheat(code)).rejection == .invalidArgument, "\(code)")
        }
        var m = CheatKit.engine(.modern)
        #expect(m.perform(.cheat(.scratch(77))).rejection == nil && m.state.commander.cash == 77)
    }

    @Test("CHEAT-008 cheats are allowed in Ironman: the game stays Ironman, is flagged and excluded from the high scores")
    func ironman() {
        var e = GameEngine(config: NewGameConfig(commanderName: "Iron", ruleset: .modern, seed: 9, ironman: true))
        #expect(e.perform(.cheat(.enable)).rejection == nil)
        #expect(e.perform(.cheat(.scratch(1_000_000))).rejection == nil)
        #expect(e.state.ironman && e.state.cheatsUsed && e.state.highScoreExclusion == .excludedForCheats)
    }
}

@Suite("CHEAT §2: parsing the Find text")
struct CheatParseTests {
    func win(_ text: String, enabled: Bool = true) -> FindInput? { FindInput.parse(text, cheatSet: .windows, cheatsEnabled: enabled) }
    func palm(_ text: String) -> FindInput? { FindInput.parse(text, cheatSet: .palm, cheatsEnabled: false) }

    @Test("CHEAT-009 parse gives search, cheat or timewarp; code words are case-sensitive")
    func kinds() {
        #expect(win("Acamar") == .search("Acamar"))
        #expect(win("Bazaar 5") == .cheat(.bazaar(5)))
        #expect(win("bazaar 5") == .search("bazaar 5"))
        #expect(win("cheetah", enabled: false) == .search("cheetah"))
        #expect(palm("Timewarp") == .timewarp)
        #expect(palm("timewarp") == .search("timewarp"))
    }

    @Test("CHEAT-010 C# splitting on single spaces and int.Parse semantics (sign, white space, Int32 range, else 0)")
    func splitting() {
        #expect(win("Bazaar  5") == .cheat(.bazaar(0)))           // second word is ""
        #expect(win("Cover 1 2 3") == .cheat(.cover(slot: 1, shield: 2)))
        #expect(win("Cover 1") == .cheat(.cover(slot: 1, shield: 0)))
        #expect(win("Fame +12") == .cheat(.fame(12)))
        #expect(win("Fame -3") == .cheat(.fame(-3)))
        #expect(win("Fame 2147483647") == .cheat(.fame(2_147_483_647)))
        #expect(win("Fame -2147483648") == .cheat(.fame(-2_147_483_648)))
        #expect(win("Fame 2147483648") == .cheat(.fame(0)))
        #expect(win("Fame 1x") == .cheat(.fame(0)))
        #expect(win("Fame +") == .cheat(.fame(0)))
        #expect(win("Fame \t7\t") == .cheat(.fame(7)))
        #expect(FindInput.csharpInt("0042") == 42 && FindInput.csharpInt("") == nil && FindInput.csharpInt("١") == nil)
    }

    @Test("CHEAT-011 without the unlock only Cheetah is a cheat; with it the 29 code words are, and Cheetah becomes a search")
    func unlock() {
        #expect(win("Cheetah", enabled: false) == .cheat(.enable))
        #expect(win("Cheetah please", enabled: false) == .cheat(.enable))
        #expect(win("Scratch 5", enabled: false) == .search("Scratch 5"))
        #expect(win("Cheetah") == .search("Cheetah"))
        #expect(win("Unknown 5") == .search("Unknown 5"))
        let words = ["Bazaar", "Cover", "DeLorean", "Diamond", "Energize", "Events", "Fame", "Go", "Ice", "Indemnity", "IOU", "Iron",
                     "Juice", "Knack", "L'Engle", "LifeBoat", "Monster.com", "PlanB", "Posse", "RapSheet", "Rarity", "Scratch",
                     "Skin", "Status", "Swag", "Test", "Tool", "Varmints", "Yellow"]
        #expect(words.count == 29)
        for w in words {
            guard case .cheat = win(w) else { Issue.record("\(w) is not a code"); continue }
            #expect(win(w, enabled: false) == .search(w))
        }
        // Argument forms.
        #expect(win("Events Reset") == .cheat(.eventsReset) && win("Events reset") == .cheat(.events))
        #expect(win("Ice Police 4") == .cheat(.ice(.police, 4)) && win("Ice Ninja 4") == .cheat(.ice(nil, 4)))
        #expect(win("Knack 3 1,x,12,4,9") == .cheat(.knack(mercenary: 3, skills: [1, nil, 12, 4])))
        #expect(win("Status Moon 2") == .cheat(.status(.moon, 2)) && win("Status moon 2") == .cheat(.statusList))
        #expect(win("Status SpaceMonster") == .cheat(.status(.spaceMonster, 0)) && win("Status") == .cheat(.statusList))
        #expect(win("Go Og") == .cheat(.go("Og")) && win("Go") == .cheat(.go("")))
    }

    @Test("CHEAT-012 Palm matches the whole text without unlock; 'Go ' needs more than 3 characters; empty text is nothing")
    func palmParsing() {
        #expect(palm("Moolah") == .cheat(.moolah) && palm("Moolah ") == .search("Moolah "))
        #expect(palm("Very rare") == .palmVeryRareForm)
        #expect(palm("Cheetah") == .cheat(.enable))
        #expect(palm("Quests") == .cheat(.quests))
        #expect(palm("Go Ac") == .cheat(.palmGo("Ac")) && palm("Go  x") == .cheat(.palmGo(" x")))
        #expect(palm("Go ") == .search("Go ") && palm("Go") == .search("Go") && palm("go Ac") == .search("go Ac"))
        #expect(palm("Acamar") == .search("Acamar"))
        #expect(palm("") == nil)
    }
}

@Suite("CHEAT §3: Windows 2.01 / Modern codes")
struct CheatWindowsCodeTests {
    @Test("CHEAT-014 enable sets cheatsUsed and changes nothing else")
    func enable() {
        var e = makeEngine(.windows201)
        let before = e.state
        _ = e.perform(.cheat(.enable))
        #expect(CheatKit.sansFlag(e.state, false) == before && e.state.cheatsUsed)
    }

    @Test("CHEAT-015 Bazaar sets chanceOfTradeInOrbit clamped to 0…1000")
    func bazaar() {
        var e = CheatKit.engine()
        for (n, want) in [(37, 37), (5_000, 1_000), (-3, 0)] {
            _ = e.perform(.cheat(.bazaar(n)))
            #expect(e.state.chanceOfTradeInOrbit == want)
        }
    }

    @Test("CHEAT-016 Cover puts a full-charge shield of type j in slot i when both are in range, else nothing")
    func cover() {
        var e = CheatKit.engine { CheatKit.grasshopper(&$0) }
        _ = e.perform(.cheat(.cover(slot: 0, shield: 2)))
        #expect(e.state.commander.ship.shields == [ShieldInstance(type: .lightning, charge: 350)])
        e.state.commander.ship.shields[0].charge = 10
        _ = e.perform(.cheat(.cover(slot: 0, shield: 0)))
        #expect(e.state.commander.ship.shields == [ShieldInstance(type: .energy, charge: 100)])
        _ = e.perform(.cheat(.cover(slot: 1, shield: 1)))
        #expect(e.state.commander.ship.shields.map(\.type) == [.energy, .reflective])
        let ship = e.state.commander.ship
        for (slot, type) in [(2, 0), (-1, 0), (0, 3), (0, -1)] {
            #expect(e.perform(.cheat(.cover(slot: slot, shield: type))).rejection == nil)
            #expect(e.state.commander.ship == ship)
        }
    }

    @Test("CHEAT-017 DeLorean sets days to max(0, n) and recomputes nothing")
    func deLorean() {
        var e = CheatKit.engine()
        let before = e.state
        _ = e.perform(.cheat(.deLorean(77)))
        var expected = before
        expected.commander.days = 77
        #expect(e.state == expected)
        _ = e.perform(.cheat(.deLorean(-5)))
        #expect(e.state.commander.days == 0)
    }

    @Test("CHEAT-018 Diamond toggles hullUpgraded without adjusting the hull")
    func diamond() {
        var e = CheatKit.engine()
        let hull = e.state.commander.ship.hull
        _ = e.perform(.cheat(.diamond))
        #expect(e.state.commander.ship.hullUpgraded && e.state.commander.ship.hull == hull)
        e.state.commander.ship.hull = e.state.commander.ship.hullStrength(e.ruleset)
        _ = e.perform(.cheat(.diamond))
        #expect(!e.state.commander.ship.hullUpgraded && e.state.commander.ship.hull > e.state.commander.ship.hullStrength(e.ruleset))
    }

    @Test("CHEAT-019 Energize toggles the portable singularity")
    func energize() {
        var e = CheatKit.engine()
        _ = e.perform(.cheat(.energize))
        #expect(e.state.quests.canSuperWarp)
        _ = e.perform(.cheat(.energize))
        #expect(!e.state.quests.canSuperWarp)
    }

    @Test("CHEAT-020 Events lists the remaining very rare encounters in stored order; Events Reset restores the canonical six")
    func events() {
        var e = CheatKit.engine { $0.veryRareEncounters = [.bottleGood, .captainAhab] }
        let before = e.state
        let r = e.perform(.cheat(.events))
        #expect(CheatKit.readout(r) == .remainingVeryRare([.bottleGood, .captainAhab]) && e.state == before)
        _ = e.perform(.cheat(.eventsReset))
        #expect(e.state.veryRareEncounters == [.marieCeleste, .captainAhab, .captainConrad, .captainHuie, .bottleOld, .bottleGood])
    }

    @Test("CHEAT-021 Fame sets reputationScore to max(0, n)")
    func fame() {
        var e = CheatKit.engine()
        _ = e.perform(.cheat(.fame(1_234)))
        #expect(e.state.commander.reputationScore == 1_234)
        _ = e.perform(.cheat(.fame(-1)))
        #expect(e.state.commander.reputationScore == 0)
    }

    @Test("CHEAT-022 Go selects the lowest-index system containing the text; only an exact (caseless) name warps directly")
    func go() {
        let names = Ruleset.windows201.tables.systemNames
        var e = CheatKit.engine()
        let cur = e.state.commander.currentSystem
        // Partial match: the lowest index containing the text is selected, nothing else happens.
        let t = CheatKit.goTarget(e.state, near: 40, avoid: cur)
        let partial = String(names[t].lowercased().prefix(3))
        let expected = names.firstIndex { $0.lowercased().contains(partial) }
        #expect(expected != nil && names[expected ?? 0].lowercased() != partial)
        let before = e.state
        let r = e.perform(.cheat(.go(partial)))
        var want = CheatKit.sansFlag(before, true)
        want.warpSystem = expected ?? -1
        want.targetWormhole = false
        #expect(r.events == [.cheatUsed] && e.state == want)
        // An empty text matches system 0; no match leaves the target unchanged.
        _ = e.perform(.cheat(.go("")))
        #expect(e.state.warpSystem == 0 && e.state.commander.currentSystem == cur)
        _ = e.perform(.cheat(.go("Qqqzz")))
        #expect(e.state.warpSystem == 0)
        // Exact name, any case: the direct warp (no fuel, cash or day; the arrival runs).
        let fuel = e.state.commander.ship.fuel, cash = e.state.commander.cash, days = e.state.commander.days
        let warp = e.perform(.cheat(.go(names[t].uppercased())))
        #expect(e.state.commander.currentSystem == t && e.state.galaxy.systems[t].visited)
        #expect(warp.events.contains(.arrived(system: t)))
        #expect(e.state.commander.ship.fuel == fuel && e.state.commander.cash == cash && e.state.commander.days == days)
        // The departure countdown is set, then the arrival's quantity pass counts it down once (ECO-034).
        #expect(e.state.galaxy.systems[cur].countDown == e.state.countDownStart - 1)
    }

    @Test("TRV-085 the direct warp is exactly: warpSystem = selected, departure countdown, news reset, CalculatePrices, arrival")
    func directWarpPipeline() {
        for seed in [UInt64(3), 17, 99] {
            var e = CheatKit.engine(seed: seed) { s in
                s.newsEvents = [.caughtLittering, .wildArrested]
                s.commander.ship.fuel = 1
            }
            let t = CheatKit.goTarget(e.state, near: (e.state.commander.currentSystem + 7) % 128, avoid: e.state.commander.currentSystem)
            var model = e.state
            model.warpSystem = t
            model.targetWormhole = false
            model.setDepartureCountdown()
            model.newsEvents.removeAll()
            model.calculatePrices(for: t)
            let events = model.arrival()
            let r = e.perform(.cheat(.go(e.state.systemName(t))))
            #expect(r.events == [.cheatUsed] + events)
            #expect(e.state == model)
        }
    }

    @Test("CHEAT-023 Ice sets the pirate, police or trader kills to max(0, n); another word is accepted and changes nothing")
    func ice() {
        var e = CheatKit.engine()
        _ = e.perform(.cheat(.ice(.pirate, 11)))
        _ = e.perform(.cheat(.ice(.police, 22)))
        _ = e.perform(.cheat(.ice(.trader, -4)))
        #expect(e.state.commander.kills == Kills(pirates: 11, police: 22, traders: 0))
        let before = e.state
        #expect(e.perform(.cheat(.ice(nil, 50))).rejection == nil && e.state == before)
    }

    @Test("CHEAT-024 Indemnity sets noClaim to max(0, n)")
    func indemnity() {
        var e = CheatKit.engine()
        _ = e.perform(.cheat(.indemnity(150)))
        #expect(e.state.commander.noClaim == 150)
        _ = e.perform(.cheat(.indemnity(-2)))
        #expect(e.state.commander.noClaim == 0)
    }

    @Test("CHEAT-025 IOU sets debt to max(0, n)")
    func iou() {
        var e = CheatKit.engine()
        _ = e.perform(.cheat(.iou(4_000)))
        #expect(e.state.commander.debt == 4_000)
        _ = e.perform(.cheat(.iou(-9)))
        #expect(e.state.commander.debt == 0)
    }

    @Test("CHEAT-026 Iron puts weapon type j (0…5) in weapon slot i when both are in range, else nothing")
    func iron() {
        var e = CheatKit.engine { CheatKit.grasshopper(&$0) }
        _ = e.perform(.cheat(.iron(slot: 0, weapon: 5)))
        _ = e.perform(.cheat(.iron(slot: 1, weapon: 3)))
        _ = e.perform(.cheat(.iron(slot: 0, weapon: 1)))
        #expect(e.state.commander.ship.weapons == [.beamLaser, .morgansLaser])
        let ship = e.state.commander.ship
        for (slot, type) in [(2, 0), (-1, 0), (0, 6), (0, -1)] {
            _ = e.perform(.cheat(.iron(slot: slot, weapon: type)))
            #expect(e.state.commander.ship == ship)
        }
    }

    @Test("CHEAT-027 Juice sets fuel clamped to 0…fuel tanks")
    func juice() {
        var e = CheatKit.engine()
        let tanks = e.state.commander.ship.fuelTanks(e.ruleset)
        _ = e.perform(.cheat(.juice(3)))
        #expect(e.state.commander.ship.fuel == 3)
        _ = e.perform(.cheat(.juice(999)))
        #expect(e.state.commander.ship.fuel == tanks)
        _ = e.perform(.cheat(.juice(-5)))
        #expect(e.state.commander.ship.fuel == 0)
    }

    @Test("CHEAT-028 Knack sets the parsed skills of mercenary n (0 = commander) clamped to 1…10; prices are not recalculated")
    func knack() {
        var e = CheatKit.engine { $0.mercenaries[0].skills = [5, 5, 5, 5] }
        let buy = e.state.buyPrices
        _ = e.perform(.cheat(.knack(mercenary: 0, skills: [3, nil, 12, 0])))
        #expect(e.state.mercenaries[0].skills == [3, 5, 10, 1] && e.state.buyPrices == buy)
        _ = e.perform(.cheat(.knack(mercenary: CrewID.wild, skills: [7])))
        #expect(e.state.mercenaries[CrewID.wild].skills[0] == 7)
        let before = e.state
        _ = e.perform(.cheat(.knack(mercenary: e.state.mercenaries.count, skills: [7, 7, 7, 7])))
        _ = e.perform(.cheat(.knack(mercenary: -1, skills: [7, 7, 7, 7])))
        #expect(e.state == before)
    }

    @Test("CHEAT-029 L'Engle sets fabricRipProbability clamped to 0…25")
    func lEngle() {
        var e = CheatKit.engine()
        for (n, want) in [(10, 10), (99, 25), (-1, 0)] {
            _ = e.perform(.cheat(.lEngle(n)))
            #expect(e.state.quests.fabricRipProbability == want)
        }
    }

    @Test("CHEAT-030 LifeBoat toggles the escape pod")
    func lifeBoat() {
        var e = CheatKit.engine()
        let pod = e.state.commander.ship.escapePod
        _ = e.perform(.cheat(.lifeBoat))
        #expect(e.state.commander.ship.escapePod == !pod)
        _ = e.perform(.cheat(.lifeBoat))
        #expect(e.state.commander.ship.escapePod == pod)
    }

    @Test("CHEAT-031 Monster.com lists non-special mercenaries with location, systems showing a special button, and shipyards")
    func monster() throws {
        var e = CheatKit.engine { s in
            CheatKit.grasshopper(&s)
            s.commander.ship.crew[1] = 3
            s.mercenaries[3].systemID = nil
            s.mercenaries[4].systemID = 17
            s.mercenaries[5].systemID = nil
        }
        let before = e.state
        let r = e.perform(.cheat(.monsterListing))
        #expect(CheatKit.sansFlag(e.state, true) == before)
        guard case let .monsterListing(list) = CheatKit.readout(r) else {
            Issue.record("no listing")
            return
        }
        let special: Set<Int> = [0, 31, 32, 33, 34, 35, 36, 37, 53, 54]
        #expect(list.mercenaries.map(\.id) == (0..<e.state.mercenaries.count).filter { !special.contains($0) })
        #expect(list.mercenaries.contains { $0.id == CrewID.zeethibal })
        let byID = Dictionary(uniqueKeysWithValues: list.mercenaries.map { ($0.id, $0) })
        #expect(byID[3]?.location == .crew && byID[4]?.location == .system(17) && byID[5]?.location == .unavailable)
        #expect(byID[4]?.skills == e.state.mercenaries[4].skills)
        let quests = e.state.galaxy.systems.filter { s in s.specialEvent.map { e.state.specialEventShown($0) } ?? false }
        #expect(list.quests.map(\.system) == quests.map(\.id) && list.quests.map(\.event) == quests.compactMap(\.specialEvent))
        #expect(!list.quests.isEmpty)
        let yards = e.state.galaxy.systems.filter { $0.shipyard != nil }
        #expect(list.shipyards.map(\.system) == yards.map(\.id) && list.shipyards.count == 5)
    }

    @Test("CHEAT-032 PlanB is accepted and changes nothing else (Parsec Merchant always autosaves)")
    func planB() {
        var e = CheatKit.engine()
        let before = e.state
        let r = e.perform(.cheat(.planB))
        #expect(r.rejection == nil && r.events == [.cheatUsed] && e.state == before)
    }

    @Test("CHEAT-033 Posse puts mercenary j in crew slot i (bounds, no special crew); location untouched; prices follow a trader change")
    func posse() {
        var e = CheatKit.engine { s in
            CheatKit.grasshopper(&s)
            s.mercenaries[0].skills = [5, 5, 2, 5]
            s.mercenaries[7].skills = [1, 1, 10, 1]
            s.mercenaries[7].systemID = 12
        }
        let buy = e.state.buyPrices
        _ = e.perform(.cheat(.posse(slot: 1, mercenary: 7)))
        #expect(e.state.commander.ship.crew == [CrewID.commander, 7, nil])
        #expect(e.state.mercenaries[7].systemID == 12)
        let expected = Pricing.buyPrices(sell: e.state.sellPrices, in: e.state.currentSystem, criminal: e.state.commander.policeRecordScore < -5,
                                         traderSkill: e.state.skill(.trader), ruleset: e.ruleset)
        #expect(e.state.buyPrices == expected && expected != buy)
        let before = e.state
        for (slot, id) in [(0, 8), (3, 8), (1, 0), (1, CrewID.wild), (1, CrewID.princess), (1, e.state.mercenaries.count), (2, -1)] {
            _ = e.perform(.cheat(.posse(slot: slot, mercenary: id)))
            #expect(e.state == before, "\(slot) \(id)")
        }
        // The same mercenary may appear twice aboard (C# quirk kept).
        _ = e.perform(.cheat(.posse(slot: 2, mercenary: 7)))
        #expect(e.state.commander.ship.crew == [CrewID.commander, 7, 7])
    }

    @Test("CHEAT-034 RapSheet (unclamped), Rarity (0…1000), Scratch (≥ 0) and Skin (0…hull strength; 0 does not end the game)")
    func values() {
        var e = CheatKit.engine()
        _ = e.perform(.cheat(.rapSheet(-500)))
        #expect(e.state.commander.policeRecordScore == -500)
        _ = e.perform(.cheat(.rarity(2_000)))
        #expect(e.state.chanceOfVeryRareEncounter == 1_000)
        _ = e.perform(.cheat(.rarity(-2)))
        #expect(e.state.chanceOfVeryRareEncounter == 0)
        _ = e.perform(.cheat(.scratch(-10)))
        #expect(e.state.commander.cash == 0)
        _ = e.perform(.cheat(.scratch(31_337)))
        #expect(e.state.commander.cash == 31_337)
        _ = e.perform(.cheat(.skin(9_999)))
        #expect(e.state.commander.ship.hull == e.state.commander.ship.hullStrength(e.ruleset))
        _ = e.perform(.cheat(.skin(0)))
        #expect(e.state.commander.ship.hull == 0 && e.state.phase == .docked)
    }

    @Test("CHEAT-035 Status Q n sets that quest status to max(0, n); the listing reports the 13 statuses in C# order")
    func status() {
        var e = CheatKit.engine()
        for (i, q) in QuestKey.allCases.enumerated() { _ = e.perform(.cheat(.status(q, 100 + i))) }
        let q = e.state.quests
        #expect([q.artifact, q.dragonfly, q.experiment, q.gemulon, q.japori, q.jarek, q.moon, q.princess, q.reactor, q.scarab,
                  q.sculpture, q.spaceMonster, q.wild] == Array(100...112))
        _ = e.perform(.cheat(.status(.reactor, -4)))
        #expect(e.state.quests.reactor == 0)
        let before = e.state
        let r = e.perform(.cheat(.statusList))
        #expect(e.state == before)
        let expected: [QuestStatusEntry] = [
            .init(quest: .artifact, status: 100), .init(quest: .dragonfly, status: 101), .init(quest: .experiment, status: 102),
            .init(quest: .gemulon, status: 103), .init(quest: .japori, status: 104), .init(quest: .jarek, status: 105),
            .init(quest: .moon, status: 106), .init(quest: .princess, status: 107), .init(quest: .reactor, status: 0),
            .init(quest: .scarab, status: 109), .init(quest: .sculpture, status: 110), .init(quest: .spaceMonster, status: 111),
            .init(quest: .wild, status: 112),
        ]
        #expect(CheatKit.readout(r) == .questStatuses(expected))
        #expect(QuestKey.allCases.map(\.codeWord) == ["Artifact", "Dragonfly", "Experiment", "Gemulon", "Japori", "Jarek", "Moon",
                                                      "Princess", "Reactor", "Scarab", "Sculpture", "SpaceMonster", "Wild"])
    }

    @Test("CHEAT-036 Swag (clamped to free bays + held, cost basis kept), Tool (gadget slots, 7 types) and Varmints (≥ 0)")
    func swagToolVarmints() {
        var e = CheatKit.engine { s in
            CheatKit.grasshopper(&s)
            s.commander.ship.cargo[1] = 5
            s.commander.priceCargo[1] = 250
        }
        let free = e.state.freeCargoBays
        _ = e.perform(.cheat(.swag(item: 1, quantity: 999)))
        #expect(e.state.commander.ship.cargo[1] == free + 5 && e.state.commander.priceCargo[1] == 250 && e.state.freeCargoBays == 0)
        _ = e.perform(.cheat(.swag(item: 1, quantity: -3)))
        #expect(e.state.commander.ship.cargo[1] == 0)
        let cargo = e.state.commander.ship.cargo
        _ = e.perform(.cheat(.swag(item: 10, quantity: 1)))
        _ = e.perform(.cheat(.swag(item: -1, quantity: 1)))
        #expect(e.state.commander.ship.cargo == cargo)
        _ = e.perform(.cheat(.tool(slot: 0, gadget: 6)))
        _ = e.perform(.cheat(.tool(slot: 1, gadget: 0)))
        _ = e.perform(.cheat(.tool(slot: 2, gadget: 4)))
        #expect(e.state.commander.ship.gadgets == [.hiddenCargoBays, .extraCargoBays, .cloakingDevice])
        let ship = e.state.commander.ship
        for (slot, type) in [(3, 0), (-1, 0), (0, 7), (0, -1)] {
            _ = e.perform(.cheat(.tool(slot: slot, gadget: type)))
            #expect(e.state.commander.ship == ship)
        }
        _ = e.perform(.cheat(.varmints(250)))
        #expect(e.state.commander.ship.tribbles == 250)
        _ = e.perform(.cheat(.varmints(-1)))
        #expect(e.state.commander.ship.tribbles == 0)
    }

    @Test("CHEAT-037 Yellow enables dismissEncounter: the encounter ends with no change and the trip resumes as after a normal end")
    func yellow() {
        func encounterEngine(easy: Bool) -> GameEngine {
            var e = EncSpec.encounter(.pirateAttack)
            e.state.cheatsUsed = true
            e.state.easyEncounters = easy
            return e
        }
        var locked = encounterEngine(easy: false)
        #expect(locked.perform(.cheat(.dismissEncounter)).rejection == .notAllowedInPhase)
        var docked = CheatKit.engine { $0.easyEncounters = true }
        #expect(docked.perform(.cheat(.dismissEncounter)).rejection == .notAllowedInPhase)
        var yellow = CheatKit.engine()
        _ = yellow.perform(.cheat(.yellow))
        #expect(yellow.state.easyEncounters)
        var e = encounterEngine(easy: true)
        var model = e
        let modelEvents = model.finishEncounter(.normal)
        let record = e.state.commander.policeRecordScore, rep = e.state.commander.reputationScore
        let r = e.perform(.cheat(.dismissEncounter))
        #expect(r.rejection == nil && r.events == [.cheatUsed] + modelEvents)
        #expect(e.state == model.state && EncSpec.endedNormally(e, r))
        #expect(e.state.commander.policeRecordScore == record && e.state.commander.reputationScore == rep && e.state.easyEncounters)
        var pending = encounterEngine(easy: true)
        pending.state.pendingScoop = .water
        #expect(pending.perform(.cheat(.dismissEncounter)).rejection == .notAllowedInPhase)
    }
}

@Suite("CHEAT §4: Palm 1.2.2 codes")
struct CheatPalmCodeTests {
    @Test("CHEAT-039 Moolah adds 100000 credits without an unlock")
    func moolah() {
        var e = makeEngine(.palm122)
        let cash = e.state.commander.cash
        #expect(e.perform(.cheat(.moolah)).rejection == nil)
        #expect(e.state.commander.cash == cash + 100_000 && e.state.cheatsUsed)
    }

    @Test("CHEAT-040 Very rare: remaining = encounters not marked as happened (canonical order); given chances replace, unclamped")
    func veryRare() {
        var e = makeEngine(.palm122)
        _ = e.perform(.cheat(.veryRare(happened: [.captainHuie, .marieCeleste], chanceOfVeryRare: 99_999, chanceOfTradeInOrbit: nil)))
        #expect(e.state.veryRareEncounters == [.captainAhab, .captainConrad, .bottleOld, .bottleGood])
        #expect(e.state.chanceOfVeryRareEncounter == 99_999 && e.state.chanceOfTradeInOrbit == 100)
        _ = e.perform(.cheat(.veryRare(happened: [], chanceOfVeryRare: nil, chanceOfTradeInOrbit: 0)))
        #expect(e.state.veryRareEncounters == VeryRareEncounter.allCases)
        #expect(e.state.chanceOfVeryRareEncounter == 99_999 && e.state.chanceOfTradeInOrbit == 0)
    }

    @Test("CHEAT-041 Palm Cheetah sets cheatsUsed and makes the Cheat form available for the rest of the game")
    func palmEnable() {
        var e = makeEngine(.palm122)
        #expect(e.perform(.cheat(.palmCheatForm(PalmCheatForm(credits: 1)))).rejection == .invalidArgument)
        let before = e.state
        #expect(e.perform(.cheat(.enable)).events == [.cheatUsed])
        #expect(CheatKit.sansFlag(e.state, false) == before)
        #expect(e.perform(.cheat(.palmCheatForm(PalmCheatForm(credits: 1)))).rejection == nil && e.state.commander.cash == 1)
        _ = e.perform(.buyFuel(credits: 1_000))
        _ = e.perform(.selectTarget(3))
        #expect(e.perform(.cheat(.palmCheatForm(PalmCheatForm(credits: 2)))).rejection == nil && e.state.commander.cash == 2)
    }

    @Test("CHEAT-042 Cheat form: credits/debt/reputation replace when given; police record magnitude then sign; moon; singularity")
    func palmForm() {
        var e = CheatKit.engine(.palm122) { s in
            s.commander.cash = 10
            s.commander.debt = 20
            s.commander.reputationScore = 30
            s.commander.policeRecordScore = -10
        }
        _ = e.perform(.cheat(.palmCheatForm(PalmCheatForm(debt: 0, policeRecordNegative: true, moon: true, singularity: true))))
        #expect(e.state.commander.cash == 10 && e.state.commander.debt == 0 && e.state.commander.reputationScore == 30)
        #expect(e.state.commander.policeRecordScore == 10)    // no magnitude, box checked: −(−10)
        #expect(e.state.quests.moon == QuestStatus.Moon.bought && e.state.quests.canSuperWarp)
        _ = e.perform(.cheat(.palmCheatForm(PalmCheatForm(credits: 5, reputation: 7, policeRecordMagnitude: 25, policeRecordNegative: true))))
        #expect(e.state.commander.cash == 5 && e.state.commander.reputationScore == 7 && e.state.commander.policeRecordScore == -25)
        #expect(e.state.quests.moon == QuestStatus.Moon.notStarted && !e.state.quests.canSuperWarp)
        _ = e.perform(.cheat(.palmCheatForm(PalmCheatForm(policeRecordMagnitude: 3))))
        #expect(e.state.commander.policeRecordScore == 3)
        e.state.quests.moon = QuestStatus.Moon.done
        _ = e.perform(.cheat(.palmCheatForm(PalmCheatForm(moon: false))))
        #expect(e.state.quests.moon == QuestStatus.Moon.done)
    }

    @Test("CHEAT-043 Cheat form equipment: slot 0 replaced (charge kept); unchecking turns every one into table index 1")
    func palmEquipment() {
        var e = CheatKit.engine(.palm122) { s in
            CheatKit.grasshopper(&s)
            s.commander.ship.shields = [ShieldInstance(type: .energy, charge: 40), ShieldInstance(type: .energy, charge: 60)]
            s.commander.ship.weapons = [.pulseLaser]
            s.commander.ship.gadgets = []
        }
        var form = PalmCheatForm(lightningShield: true, fuelCompactor: true, morgansLaser: true)
        _ = e.perform(.cheat(.palmCheatForm(form)))
        #expect(e.state.commander.ship.shields == [ShieldInstance(type: .lightning, charge: 40), ShieldInstance(type: .energy, charge: 60)])
        #expect(e.state.commander.ship.weapons == [.morgansLaser] && e.state.commander.ship.gadgets == [.fuelCompactor])
        // Already aboard: checked again changes nothing.
        let ship = e.state.commander.ship
        _ = e.perform(.cheat(.palmCheatForm(form)))
        #expect(e.state.commander.ship == ship)
        e.state.commander.ship.shields[1].type = .lightning
        e.state.commander.ship.weapons.append(.morgansLaser)
        e.state.commander.ship.gadgets.append(.fuelCompactor)
        form = PalmCheatForm()
        _ = e.perform(.cheat(.palmCheatForm(form)))
        #expect(e.state.commander.ship.shields == [ShieldInstance(type: .reflective, charge: 40), ShieldInstance(type: .reflective, charge: 60)])
        #expect(e.state.commander.ship.weapons == [.beamLaser, .beamLaser])
        #expect(e.state.commander.ship.gadgets == [.autoRepairSystem, .autoRepairSystem])
        // Empty slot 0: a Lightning shield with charge 0; no slots at all: nothing.
        e.state.commander.ship.shields = []
        _ = e.perform(.cheat(.palmCheatForm(PalmCheatForm(lightningShield: true))))
        #expect(e.state.commander.ship.shields == [ShieldInstance(type: .lightning, charge: 0)])
        var flea = CheatKit.engine(.palm122) { s in
            var ship = Ship(type: .flea, spec: s.ruleset.tables.ship(.flea))
            ship.crew[0] = CrewID.commander
            s.commander.ship = ship
        }
        let spec = flea.state.commander.ship.spec(flea.ruleset)
        #expect(spec.shieldSlots == 0 && spec.weaponSlots == 0)
        _ = flea.perform(.cheat(.palmCheatForm(PalmCheatForm(lightningShield: true, morgansLaser: true))))
        #expect(flea.state.commander.ship.shields.isEmpty && flea.state.commander.ship.weapons.isEmpty)
    }

    @Test("CHEAT-044 Palm Go moves to the first system whose name is not caselessly before the text; nothing else changes")
    func palmGo() {
        let names = Ruleset.palm122.tables.systemNames
        var e = makeEngine(.palm122)
        let start = e.state.commander.currentSystem
        let before = e.state
        let probe = start == 0 ? "b" : "a"
        let expected = names.firstIndex { $0.lowercased() >= probe }
        _ = e.perform(.cheat(.palmGo(probe.uppercased())))
        var want = CheatKit.sansFlag(before, true)
        want.commander.currentSystem = expected ?? start
        #expect(e.state == want && expected != start)
        _ = e.perform(.cheat(.palmGo("Zzzzzz")))
        #expect(e.state.commander.currentSystem == expected)
        _ = e.perform(.cheat(.palmGo(names[17].lowercased())))
        #expect(e.state.commander.currentSystem == 17)
    }

    @Test("CHEAT-045 Palm Quests lists the last system per quest label; artifact/Berger and Scarab variants follow the status")
    func palmQuests() {
        var e = CheatKit.engine(.palm122) { s in
            for i in s.galaxy.systems.indices { s.galaxy.systems[i].specialEvent = nil }
            s.galaxy.systems[3].specialEvent = .dragonfly
            s.galaxy.systems[7].specialEvent = .dragonfly
            s.galaxy.systems[5].specialEvent = .artifact
            s.galaxy.systems[9].specialEvent = .artifactDelivery
            s.galaxy.systems[11].specialEvent = .scarabDestroyed
            s.galaxy.systems[12].specialEvent = .gemulon
            s.galaxy.systems[13].specialEvent = .moon
        }
        let before = e.state
        let r = e.perform(.cheat(.quests))
        #expect(CheatKit.sansFlag(e.state, false) == CheatKit.sansFlag(before, false))
        #expect(CheatKit.readout(r) == .palmQuestLocations([.init(label: .dragonfly, system: 7), .init(label: .artifact, system: 5),
                                                             .init(label: .invasion, system: 12)]))
        e.state.quests.artifact = QuestStatus.Artifact.onBoard
        e.state.quests.scarab = QuestStatus.Scarab.hunting
        let r2 = e.perform(.cheat(.quests))
        #expect(CheatKit.readout(r2) == .palmQuestLocations([.init(label: .dragonfly, system: 7), .init(label: .berger, system: 9),
                                                              .init(label: .invasion, system: 12), .init(label: .scarab, system: 11)]))
    }
}
