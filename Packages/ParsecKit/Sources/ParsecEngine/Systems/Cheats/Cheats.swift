// SPDX-License-Identifier: GPL-2.0-or-later
// Cheat codes (docs/specs/CHEAT.md): the C# Find-box codes, the Palm Find-box codes and the Palm Cheat form.
// Every accepted cheat flags the game permanently (`cheatsUsed`, PRD §8.3).

/// CHEAT-007: which cheat codes a ruleset has (ruleset content, `Ruleset.content.cheatSet`).
public enum CheatSet: String, Codable, Sendable, CaseIterable {
    /// The C# 2.01 codes (Modern and Windows 2.01).
    case windows
    /// The Palm 1.2.2 codes (Find box and Cheat form).
    case palm
}

/// CHEAT-023: the kill counter set by "Ice".
public enum KillKind: String, Codable, Sendable, CaseIterable {
    case pirate, police, trader
}

/// CHEAT-035: the quest statuses addressed by "Status", in the order of the C# readout.
public enum QuestKey: String, Codable, Sendable, CaseIterable {
    case artifact, dragonfly, experiment, gemulon, japori, jarek, moon, princess, reactor, scarab, sculpture, spaceMonster, wild

    /// The C# code word ("Artifact", …, "SpaceMonster", "Wild").
    public var codeWord: String {
        switch self {
        case .spaceMonster: "SpaceMonster"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// CHEAT-042/043: the Palm Cheat form (Commander Status). Nil numeric fields were left empty (keep the value).
public struct PalmCheatForm: Codable, Sendable, Equatable {
    public var credits: Int?
    public var debt: Int?
    public var reputation: Int?
    public var policeRecordMagnitude: Int?
    public var policeRecordNegative: Bool
    public var moon: Bool
    public var lightningShield: Bool
    public var fuelCompactor: Bool
    public var morgansLaser: Bool
    public var singularity: Bool

    public init(credits: Int? = nil, debt: Int? = nil, reputation: Int? = nil, policeRecordMagnitude: Int? = nil,
                policeRecordNegative: Bool = false, moon: Bool = false, lightningShield: Bool = false,
                fuelCompactor: Bool = false, morgansLaser: Bool = false, singularity: Bool = false) {
        self.credits = credits
        self.debt = debt
        self.reputation = reputation
        self.policeRecordMagnitude = policeRecordMagnitude
        self.policeRecordNegative = policeRecordNegative
        self.moon = moon
        self.lightningShield = lightningShield
        self.fuelCompactor = fuelCompactor
        self.morgansLaser = morgansLaser
        self.singularity = singularity
    }
}

/// A cheat (CHEAT §3 Windows/Modern, §4 Palm). Numeric arguments are the raw parsed values; the engine clamps them.
public enum CheatCode: Codable, Sendable, Equatable {
    // Windows 2.01 / Modern (C# Form_SpaceTrader.btnFind_Click).
    case enable
    case bazaar(Int)
    case cover(slot: Int, shield: Int)
    case deLorean(Int)
    case diamond
    case energize
    case events
    case eventsReset
    case fame(Int)
    case go(String)
    /// A second word other than Pirate/Police/Trader is `nil` (accepted, no change).
    case ice(KillKind?, Int)
    case indemnity(Int)
    case iou(Int)
    case iron(slot: Int, weapon: Int)
    case juice(Int)
    /// Up to four parts of the comma-separated third word; `nil` parts did not parse and leave their skill unchanged.
    case knack(mercenary: Int, skills: [Int?])
    case lEngle(Int)
    case lifeBoat
    case monsterListing
    case planB
    case posse(slot: Int, mercenary: Int)
    case rapSheet(Int)
    case rarity(Int)
    case scratch(Int)
    case skin(Int)
    case status(QuestKey, Int)
    case statusList
    case swag(item: Int, quantity: Int)
    case test
    case tool(slot: Int, gadget: Int)
    case varmints(Int)
    case yellow
    /// CHEAT-037: the encounter window's close box, available after "Yellow".
    case dismissEncounter
    // Palm 1.2.2.
    case moolah
    case veryRare(happened: Set<VeryRareEncounter>, chanceOfVeryRare: Int?, chanceOfTradeInOrbit: Int?)
    case palmCheatForm(PalmCheatForm)
    case palmGo(String)
    case quests

    /// CHEAT-007: the set this code belongs to (`enable` exists in both).
    public func belongs(to set: CheatSet) -> Bool {
        switch self {
        case .enable: true
        case .moolah, .veryRare, .palmCheatForm, .palmGo, .quests: set == .palm
        default: set == .windows
        }
    }

    /// Codes that work without a prior `enable`: `enable` itself and Palm's Find-box codes (CHEAT-011/012).
    var needsUnlock: Bool {
        switch self {
        case .enable, .moolah, .veryRare, .palmGo, .quests: false
        default: true
        }
    }
}

/// CHEAT-009: what the Find text means.
public enum FindInput: Codable, Sendable, Equatable {
    /// A normal system search (the whole text).
    case search(String)
    case cheat(CheatCode)
    /// CHEAT-040: Palm "Very rare": the app shows the very-rare form, then sends `.cheat(.veryRare(…))`.
    case palmVeryRareForm
    /// CHEAT-046: Palm "Timewarp" (an app action, not an engine command).
    case timewarp

    /// CHEAT-009…012: parses the Find text. Returns nil only for an empty Palm text (Palm treats it as Cancel).
    public static func parse(_ text: String, cheatSet: CheatSet, cheatsEnabled: Bool) -> FindInput? {
        switch cheatSet {
        case .windows: return parseWindows(text, cheatsEnabled: cheatsEnabled)
        case .palm: return parsePalm(text)
        }
    }

    private static func parsePalm(_ text: String) -> FindInput? {
        if text.isEmpty { return nil }
        switch text {
        case "Moolah": return .cheat(.moolah)
        case "Very rare": return .palmVeryRareForm
        case "Cheetah": return .cheat(.enable)
        case "Quests": return .cheat(.quests)
        case "Timewarp": return .timewarp
        default:
            // Src/WarpFormEvent.c:643: `StrNCompare(FindSystem, "Go ", 3) == 0 && StrLen(FindSystem) > 3`.
            if text.utf8.count > 3, text.utf8.starts(with: "Go ".utf8) {
                return .cheat(.palmGo(String(String.UnicodeScalarView(text.unicodeScalars.dropFirst(3)))))
            }
            return .search(text)
        }
    }

    private static func parseWindows(_ text: String, cheatsEnabled: Bool) -> FindInput {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let first = words.count > 0 ? words[0] : ""
        let second = words.count > 1 ? words[1] : ""
        let third = words.count > 2 ? words[2] : ""
        let n1 = csharpInt(second) ?? 0, n2 = csharpInt(third) ?? 0
        guard cheatsEnabled else { return first == "Cheetah" ? .cheat(.enable) : .search(text) }
        let code = windowsCodeAToK(first, second, third, n1, n2) ?? windowsCodeLToZ(first, second, n1, n2)
        return code.map { .cheat($0) } ?? .search(text)
    }

    /// The C# code words "Bazaar"…"Knack" (Form_SpaceTrader.cs:3302-3386).
    private static func windowsCodeAToK(_ first: String, _ second: String, _ third: String, _ n1: Int, _ n2: Int) -> CheatCode? {
        switch first {
        case "Bazaar": .bazaar(n1)
        case "Cover": .cover(slot: n1, shield: n2)
        case "DeLorean": .deLorean(n1)
        case "Diamond": .diamond
        case "Energize": .energize
        case "Events": second == "Reset" ? .eventsReset : .events
        case "Fame": .fame(n1)
        case "Go": .go(second)
        case "Ice": .ice(["Pirate": .pirate, "Police": .police, "Trader": .trader][second], n2)
        case "Indemnity": .indemnity(n1)
        case "IOU": .iou(n1)
        case "Iron": .iron(slot: n1, weapon: n2)
        case "Juice": .juice(n1)
        case "Knack":
            .knack(mercenary: n1, skills: third.split(separator: ",", omittingEmptySubsequences: false).prefix(4)
                .map { csharpInt(String($0)) })
        default: nil
        }
    }

    /// The C# code words "L'Engle"…"Yellow" (Form_SpaceTrader.cs:3387-3500).
    private static func windowsCodeLToZ(_ first: String, _ second: String, _ n1: Int, _ n2: Int) -> CheatCode? {
        switch first {
        case "L'Engle": .lEngle(n1)
        case "LifeBoat": .lifeBoat
        case "Monster.com": .monsterListing
        case "PlanB": .planB
        case "Posse": .posse(slot: n1, mercenary: n2)
        case "RapSheet": .rapSheet(n1)
        case "Rarity": .rarity(n1)
        case "Scratch": .scratch(n1)
        case "Skin": .skin(n1)
        case "Status": QuestKey.allCases.first { $0.codeWord == second }.map { .status($0, n2) } ?? .statusList
        case "Swag": .swag(item: n1, quantity: n2)
        case "Test": .test
        case "Tool": .tool(slot: n1, gadget: n2)
        case "Varmints": .varmints(n1)
        case "Yellow": .yellow
        default: nil
        }
    }

    /// CHEAT-010: C# `int.Parse` with the default `NumberStyles.Integer` (leading/trailing white space, optional sign,
    /// ASCII digits, Int32 range); nil where `Functions.IsInt` is false.
    static func csharpInt(_ s: String) -> Int? {
        let white: Set<UInt32> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20]
        var scalars = Array(s.unicodeScalars)
        while let f = scalars.first, white.contains(f.value) { scalars.removeFirst() }
        while let l = scalars.last, white.contains(l.value) { scalars.removeLast() }
        var negative = false
        if let f = scalars.first, f == "+" || f == "-" {
            negative = f == "-"
            scalars.removeFirst()
        }
        guard !scalars.isEmpty else { return nil }
        var value = 0
        for c in scalars {
            guard c.value >= 0x30, c.value <= 0x39 else { return nil }
            value = value * 10 + Int(c.value - 0x30)
            if value > Int(Int32.max) + 1 { return nil }
        }
        let result = negative ? -value : value
        return result > Int(Int32.max) ? nil : result
    }
}

/// CHEAT-031: where a mercenary is.
public enum MercenaryLocation: Codable, Sendable, Equatable {
    case crew
    case system(Int)
    case unavailable
}

/// CHEAT-031: Monster.com lists (id order; the app sorts and names them).
public struct MonsterListing: Codable, Sendable, Equatable {
    public struct Mercenary: Codable, Sendable, Equatable {
        public var id: Int
        public var skills: [Int]
        public var location: MercenaryLocation
    }

    public struct Quest: Codable, Sendable, Equatable {
        public var system: Int
        public var event: SpecialEventType
    }

    public struct Shipyard: Codable, Sendable, Equatable {
        public var system: Int
        public var shipyard: ShipyardID
    }

    public var mercenaries: [Mercenary]
    public var quests: [Quest]
    public var shipyards: [Shipyard]
}

/// CHEAT-035: one quest status of the "Status" readout.
public struct QuestStatusEntry: Codable, Sendable, Equatable {
    public var quest: QuestKey
    public var status: Int
}

/// CHEAT-045: the labels of the Palm "Quests" list (`artifact` / `berger` share the artifact line).
public enum PalmQuestLabel: String, Codable, Sendable, CaseIterable {
    case dragonfly, monster, disease, artifact, berger, tribbles, reactor, jarek, invasion, experiment, wild, scarab
}

/// CHEAT-045: one line of the Palm "Quests" list.
public struct PalmQuestLocation: Codable, Sendable, Equatable {
    public var label: PalmQuestLabel
    public var system: Int
}

/// Read-only cheat listings (the classic plain-text alerts, typed).
public enum CheatReadout: Codable, Sendable, Equatable {
    case remainingVeryRare([VeryRareEncounter])
    case questStatuses([QuestStatusEntry])
    case monsterListing(MonsterListing)
    case palmQuestLocations([PalmQuestLocation])
}

public extension GameState {
    /// A trade-in-orbit, plunder or scoop decision is open.
    var hasPendingDecision: Bool { pendingPlunder != nil || pendingOrbitTrade != nil || pendingScoop != nil }

    /// C# `Consts.SpecialCrewMemberIds` (Consts.cs:283-295).
    static let specialCrewIDs: Set<Int> = [CrewID.commander, CrewID.dragonfly, CrewID.famousCaptain, CrewID.jarek,
                                           CrewID.opponent, CrewID.princess, CrewID.scarab, CrewID.scorpion,
                                           CrewID.spaceMonster, CrewID.wild]

    /// CHEAT-031: the Monster.com listing (Form_Monster.cs `PopulateIdArrays`, unsorted).
    var monsterListing: MonsterListing {
        let mercs = mercenaries.filter { !Self.specialCrewIDs.contains($0.id) }.map { m in
            let location: MercenaryLocation = commander.ship.hasCrew(m.id) ? .crew : m.systemID.map { .system($0) } ?? .unavailable
            return MonsterListing.Mercenary(id: m.id, skills: m.skills, location: location)
        }
        let quests = galaxy.systems.compactMap { s in
            s.specialEvent.flatMap { specialEventShown($0) ? MonsterListing.Quest(system: s.id, event: $0) : nil }
        }
        let yards = galaxy.systems.compactMap { s in s.shipyard.map { MonsterListing.Shipyard(system: s.id, shipyard: $0) } }
        return MonsterListing(mercenaries: mercs, quests: quests, shipyards: yards)
    }

    /// CHEAT-045: Palm "Quests" (Src/WarpFormEvent.c:659-697): the last matching system per label.
    var palmQuestLocations: [PalmQuestLocation] {
        var artifactLine: PalmQuestLocation?
        var found: [PalmQuestLabel: Int] = [:]
        for s in galaxy.systems {
            switch s.specialEvent {
            case .dragonfly: found[.dragonfly] = s.id
            case .spaceMonster: found[.monster] = s.id
            case .japori: found[.disease] = s.id
            case .artifact: artifactLine = PalmQuestLocation(label: .artifact, system: s.id)
            case .artifactDelivery where artifactOnBoard: artifactLine = PalmQuestLocation(label: .berger, system: s.id)
            case .tribble: found[.tribbles] = s.id
            case .reactor: found[.reactor] = s.id
            case .jarek: found[.jarek] = s.id
            case .gemulon: found[.invasion] = s.id
            case .experiment: found[.experiment] = s.id
            case .wild: found[.wild] = s.id
            case .scarab: found[.scarab] = s.id
            case .scarabDestroyed where quests.scarab == QuestStatus.Scarab.hunting: found[.scarab] = s.id
            default: break
            }
        }
        return PalmQuestLabel.allCases.compactMap { label in
            if label == .artifact || label == .berger { return artifactLine?.label == label ? artifactLine : nil }
            return found[label].map { PalmQuestLocation(label: label, system: $0) }
        }
    }

    /// The name of system `i` in the ruleset's name table.
    func systemName(_ i: Int) -> String { ruleset.tables.systemNames[i] }
}

extension GameEngine {
    /// CHEAT-001/005/007: `Command.cheat`.
    mutating func cheat(_ code: CheatCode) -> StepResult {
        guard code.belongs(to: ruleset.content.cheatSet) else { return .rejected(.invalidArgument) }
        if code == .dismissEncounter { return dismissEncounter() }
        guard docked, !state.hasPendingDecision else { return .rejected(.notAllowedInPhase) }
        if code.needsUnlock, !state.cheatsUsed { return .rejected(.invalidArgument) }
        state.cheatsUsed = true
        return StepResult(events: [.cheatUsed] + applyCheat(code))
    }

    /// CHEAT-037: the encounter window's close box (C# `EncounterResult.Continue`): the trip simply resumes.
    private mutating func dismissEncounter() -> StepResult {
        guard state.easyEncounters, encounter != nil, !state.hasPendingDecision else { return .rejected(.notAllowedInPhase) }
        state.cheatsUsed = true
        return StepResult(events: [.cheatUsed] + finishEncounter(.normal))
    }

    /// Applies an accepted code: commander and game values here, ship and listing codes in `applyShipCheat`.
    private mutating func applyCheat(_ code: CheatCode) -> [GameEvent] {
        switch code {
        case .enable, .planB, .test, .dismissEncounter: break
        case let .bazaar(n): state.chanceOfTradeInOrbit = clamp(n, 0, 1000)
        case let .deLorean(n): state.commander.days = max(0, n)
        case .energize: state.quests.canSuperWarp.toggle()
        case .events: return [.cheatReadout(.remainingVeryRare(state.veryRareEncounters))]
        case .eventsReset: state.veryRareEncounters = VeryRareEncounter.allCases
        case let .fame(n): state.commander.reputationScore = max(0, n)
        case let .go(name): return cheatGo(name)
        case let .ice(kind, n):
            switch kind {
            case .pirate: state.commander.kills.pirates = max(0, n)
            case .police: state.commander.kills.police = max(0, n)
            case .trader: state.commander.kills.traders = max(0, n)
            case nil: break
            }
        case let .indemnity(n): state.commander.noClaim = max(0, n)
        case let .iou(n): state.commander.debt = max(0, n)
        case let .knack(id, skills):
            guard state.mercenaries.indices.contains(id) else { break }
            for (i, value) in skills.prefix(4).enumerated() {
                if let value { state.mercenaries[id].skills[i] = clamp(value, 1, 10) }
            }
        case let .lEngle(n): state.quests.fabricRipProbability = clamp(n, 0, 25)
        case .monsterListing: return [.cheatReadout(.monsterListing(state.monsterListing))]
        case let .rapSheet(n): state.commander.policeRecordScore = n
        case let .rarity(n): state.chanceOfVeryRareEncounter = clamp(n, 0, 1000)
        case let .scratch(n): state.commander.cash = max(0, n)
        case let .status(quest, n): setQuestStatus(quest, max(0, n))
        case .statusList:
            return [.cheatReadout(.questStatuses(QuestKey.allCases.map { QuestStatusEntry(quest: $0, status: questStatus($0)) }))]
        case .yellow: state.easyEncounters = true
        default: return applyShipCheat(code)
        }
        return []
    }

    /// Ship codes (Windows) and the Palm codes.
    private mutating func applyShipCheat(_ code: CheatCode) -> [GameEvent] {
        let r = ruleset
        switch code {
        case let .cover(slot, type):
            guard slot >= 0, slot < state.commander.ship.spec(r).shieldSlots, type >= 0, type < r.tables.shields.count,
                  let t = ShieldType(rawValue: type) else { break }
            install(&state.commander.ship.shields, at: slot, ShieldInstance(type: t, charge: r.tables.shield(t).power))
        case .diamond: state.commander.ship.hullUpgraded.toggle()
        case let .iron(slot, type):
            guard slot >= 0, slot < state.commander.ship.spec(r).weaponSlots, type >= 0, type < r.tables.weapons.count,
                  let t = WeaponType(rawValue: type) else { break }
            install(&state.commander.ship.weapons, at: slot, t)
        case let .juice(n): state.commander.ship.fuel = clamp(n, 0, state.commander.ship.fuelTanks(r))
        case .lifeBoat: state.commander.ship.escapePod.toggle()
        case let .posse(slot, id):
            guard slot > 0, slot < state.commander.ship.crew.count, id > 0, id < state.mercenaries.count,
                  !GameState.specialCrewIDs.contains(id) else { break }
            let before = state.skill(.trader)
            state.commander.ship.crew[slot] = id
            if state.skill(.trader) != before { state.recalculateBuyPricesHere() }
        case let .skin(n): state.commander.ship.hull = clamp(n, 0, state.commander.ship.hullStrength(r))
        case let .swag(item, n):
            guard item >= 0, item < state.commander.ship.cargo.count else { break }
            state.commander.ship.cargo[item] = max(0, min(state.freeCargoBays + state.commander.ship.cargo[item], n))
        case let .tool(slot, type):
            guard slot >= 0, slot < state.commander.ship.spec(r).gadgetSlots, type >= 0, type < r.tables.gadgets.count,
                  let t = GadgetType(rawValue: type) else { break }
            install(&state.commander.ship.gadgets, at: slot, t)
        case let .varmints(n): state.commander.ship.tribbles = max(0, n)
        case .moolah: state.commander.cash += 100_000
        case let .veryRare(happened, chanceVeryRare, chanceTrade):
            if let chanceVeryRare { state.chanceOfVeryRareEncounter = chanceVeryRare }
            if let chanceTrade { state.chanceOfTradeInOrbit = chanceTrade }
            state.veryRareEncounters = VeryRareEncounter.allCases.filter { !happened.contains($0) }
        case let .palmCheatForm(form): applyPalmCheatForm(form)
        case let .palmGo(name):
            let target = Array(name.utf8).map(Self.asciiLower)
            if let i = state.galaxy.systems.indices.first(where: {
                !Array(state.systemName($0).utf8).map(Self.asciiLower).lexicographicallyPrecedes(target)
            }) {
                state.commander.currentSystem = i
            }
        case .quests: return [.cheatReadout(.palmQuestLocations(state.palmQuestLocations))]
        default: break
        }
        return []
    }

    private func clamp(_ x: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, x)) }

    private static func asciiLower(_ b: UInt8) -> UInt8 { b >= 0x41 && b <= 0x5A ? b + 0x20 : b }

    /// C# `ship.X[slot] = new`: replaces the item in `slot`, or fills an empty slot (equipment arrays are compact).
    private func install<T>(_ items: inout [T], at slot: Int, _ item: T) {
        if slot < items.count { items[slot] = item } else { items.append(item) }
    }

    /// CHEAT-022 / TRV-085: "Go name" (C# `SelectedSystemName` setter, then `WarpDirect` on an exact match).
    private mutating func cheatGo(_ name: String) -> [GameEvent] {
        let needle = name.lowercased()
        guard let i = state.galaxy.systems.indices.first(where: {
            needle.isEmpty || state.systemName($0).lowercased().contains(needle)
        }) else { return [] }
        state.warpSystem = i
        state.targetWormhole = false
        guard state.systemName(i).lowercased() == needle else { return [] }
        // Game.WarpDirect (Game.cs:3212-3219).
        state.setDepartureCountdown()
        state.newsEvents.removeAll()
        state.calculatePrices(for: i)
        return state.arrival()
    }

    private func questStatus(_ q: QuestKey) -> Int {
        let s = state.quests
        switch q {
        case .artifact: return s.artifact
        case .dragonfly: return s.dragonfly
        case .experiment: return s.experiment
        case .gemulon: return s.gemulon
        case .japori: return s.japori
        case .jarek: return s.jarek
        case .moon: return s.moon
        case .princess: return s.princess
        case .reactor: return s.reactor
        case .scarab: return s.scarab
        case .sculpture: return s.sculpture
        case .spaceMonster: return s.spaceMonster
        case .wild: return s.wild
        }
    }

    private mutating func setQuestStatus(_ q: QuestKey, _ v: Int) {
        switch q {
        case .artifact: state.quests.artifact = v
        case .dragonfly: state.quests.dragonfly = v
        case .experiment: state.quests.experiment = v
        case .gemulon: state.quests.gemulon = v
        case .japori: state.quests.japori = v
        case .jarek: state.quests.jarek = v
        case .moon: state.quests.moon = v
        case .princess: state.quests.princess = v
        case .reactor: state.quests.reactor = v
        case .scarab: state.quests.scarab = v
        case .sculpture: state.quests.sculpture = v
        case .spaceMonster: state.quests.spaceMonster = v
        case .wild: state.quests.wild = v
        }
    }

    /// CHEAT-042/043: Palm Cheat form (Src/CmdrStatusEvent.c:177-224).
    private mutating func applyPalmCheatForm(_ f: PalmCheatForm) {
        let r = ruleset
        if let v = f.credits { state.commander.cash = v }
        if let v = f.debt { state.commander.debt = v }
        if let v = f.reputation { state.commander.reputationScore = v }
        if let v = f.policeRecordMagnitude { state.commander.policeRecordScore = v }
        if f.policeRecordNegative { state.commander.policeRecordScore = -state.commander.policeRecordScore }
        if f.moon, state.quests.moon == QuestStatus.Moon.notStarted { state.quests.moon = QuestStatus.Moon.bought }
        if !f.moon, state.quests.moon == QuestStatus.Moon.bought { state.quests.moon = QuestStatus.Moon.notStarted }
        var ship = state.commander.ship
        // Palm writes index 1 of each table when unchecking (Reflective, Auto-repair, Beam laser).
        if f.lightningShield, !ship.has(.lightning), ship.spec(r).shieldSlots > 0 {
            if ship.shields.isEmpty {
                ship.shields.append(ShieldInstance(type: .lightning, charge: 0))
            } else {
                ship.shields[0].type = .lightning
            }
        } else if !f.lightningShield, ship.has(.lightning) {
            for i in ship.shields.indices where ship.shields[i].type == .lightning { ship.shields[i].type = .reflective }
        }
        if f.fuelCompactor, !ship.has(.fuelCompactor), ship.spec(r).gadgetSlots > 0 {
            install(&ship.gadgets, at: 0, .fuelCompactor)
        } else if !f.fuelCompactor, ship.has(.fuelCompactor) {
            ship.gadgets = ship.gadgets.map { $0 == .fuelCompactor ? .autoRepairSystem : $0 }
        }
        if f.morgansLaser, !ship.has(.morgansLaser), ship.spec(r).weaponSlots > 0 {
            install(&ship.weapons, at: 0, .morgansLaser)
        } else if !f.morgansLaser, ship.has(.morgansLaser) {
            ship.weapons = ship.weapons.map { $0 == .morgansLaser ? .beamLaser : $0 }
        }
        state.commander.ship = ship
        state.quests.canSuperWarp = f.singularity
    }
}
