// SPDX-License-Identifier: GPL-2.0-or-later
// LLM (docs/specs/LLM.md §1–2): flavor values, the provider protocol and the deterministic template provider.
import Foundation
import Testing
import ParsecEngine
@testable import ParsecInsights

private let arrival = FlavorSubject.arrival(system: 4, viaWormhole: false, firstVisit: false, uneventful: true, encounterCount: 0)

/// A provider that always declines (LLM-001: nil keeps the template).
private struct Silent: FlavorProvider {
    var source: FlavorSource { .foundationModels }
    func flavor(for request: FlavorRequest) async -> FlavorText? { nil }
}

@Suite("LLM flavor text")
struct FlavorSpecTests {
    @Test("LLM-001 providers are Sendable; a nil result means no flavor from that provider")
    func providers() async {
        let request = FlavorRequest(entryID: 1, day: 2, system: 3, subject: arrival)
        let providers: [any FlavorProvider] = [TemplateFlavorProvider(), Silent()]
        #expect(await providers[1].flavor(for: request) == nil)
        #expect(await providers[0].flavor(for: request) == .template(TemplateFlavorProvider().line(for: request)))
        #expect(providers.map(\.source) == [.template, .foundationModels])
    }

    @Test("LLM-002 a request is built from a log entry alone")
    func requests() {
        let entry = LogEntry(id: 9, day: 5, system: 2, worth: 0, kind: .quest(.completed(.japoriDelivery)))
        #expect(FlavorRequest(entry: entry) == FlavorRequest(entryID: 9, day: 5, system: 2, subject: .quest(.japoriDelivery)))
        #expect(FlavorRequest(entry: LogEntry(id: 1, day: 0, system: 0, worth: 0, kind: .cheatsEnabled)) == nil)
    }

    @Test("LLM-003 LogEntryKind.flavorSubject produces the typed subjects")
    func subjects() {
        let r = record(.destroyed(.gnat), type: .pirateAttack, opponent: .gnat, hull: 33)
        #expect(LogEntryKind.encounter(r).flavorSubject == .encounter(type: .pirateAttack, opponent: .gnat, result: .won, rounds: 2,
                                                                         minHullPercent: 33))
        #expect(LogEntryKind.gameEnded(.killed, score: 1).flavorSubject == .gameEnded(.killed))
        #expect(LogEntryKind.achievementUnlocked(.moon).flavorSubject == .achievement(.moon))
        let a = TripArrival(system: 4, from: 1, viaWormhole: false, firstVisit: false, uneventful: true, encounterCount: 0)
        #expect(LogEntryKind.arrived(a).flavorSubject == arrival)
    }

    @Test("LLM-004 FlavorText stores template lines as key plus typed arguments and round-trips")
    func flavorText() throws {
        let values: [FlavorText] = [
            .template(FlavorLine(key: "flavor.arrival.quiet.1", args: [.system(3), .ship(.gnat), .item(.ore), .count(2), .credits(5),
                                                                        .skill(.pilot)])),
            .generated(text: "Zoë \"quoted\" \\ / 🚀"),
        ]
        for v in values { #expect(try JSONDecoder().decode(FlavorText.self, from: JSONEncoder().encode(v)) == v) }
    }

    @Test("LLM-005 FlavorText.source tells template from generated text")
    func source() {
        #expect(FlavorText.template(FlavorLine(key: "k")).source == .template)
        #expect(FlavorText.generated(text: "x").source == .foundationModels)
    }

    @Test("LLM-006 the template provider is a pure function of the request")
    func pure() {
        let p = TemplateFlavorProvider()
        for id in 1...50 {
            let r = FlavorRequest(entryID: id, day: id * 3, system: id % 7, subject: arrival)
            #expect(p.line(for: r) == TemplateFlavorProvider().line(for: r))
        }
    }

    @Test("LLM-007 FlavorSeed is FNV-1a 64 over little-endian entry id, day, system and subject code (golden vectors)")
    func seed() {
        func reference(_ r: FlavorRequest) -> UInt64 {
            var bytes: [UInt8] = []
            for v in [r.entryID, r.day, r.system] { withUnsafeBytes(of: Int64(v).littleEndian) { bytes += $0 } }
            withUnsafeBytes(of: r.subject.code.littleEndian) { bytes += $0 }
            var h: UInt64 = 14_695_981_039_346_656_037
            for b in bytes { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
            return h
        }
        let a = FlavorRequest(entryID: 1, day: 0, system: 0, subject: arrival)
        let b = FlavorRequest(entryID: 42, day: 17, system: 3, subject: .quest(.japoriDelivery))
        let c = FlavorRequest(entryID: -1, day: Int.max, system: 99, subject: .achievement(.firstProfit))
        for r in [a, b, c] { #expect(FlavorSeed.make(r) == reference(r)) }
        #expect(FlavorSeed.make(a) == 6_995_049_787_377_860_981)
        #expect(FlavorSeed.make(b) == 14_908_073_196_438_424_912)
        #expect(FlavorSeed.make(c) == 41_916_745_530_877_194)
        #expect(arrival.code == 1 && FlavorSubject.achievement(.moon).code == UInt32(FlavorGroup.allCases.count))
    }

    @Test("LLM-008 the recorder attaches template flavor to every new entry with a subject, deterministically")
    func attached() throws {
        var g = RecordedGame(.modern, seed: 19)
        g.fuzz(200, seed: 19)
        for e in g.journal.entries {
            if let request = FlavorRequest(entry: e) {
                #expect(e.flavor == .template(TemplateFlavorProvider().line(for: request)))
            } else {
                #expect(e.flavor == nil)
            }
        }
        let applied = g.journal.setFlavor(.generated(text: "Prose."), forEntry: 1)
        let missing = g.journal.setFlavor(nil, forEntry: -5)
        #expect(applied && !missing && g.journal.entries[0].flavor?.source == .foundationModels)
    }

    @Test("LLM-009 catalog: flavor.<group>.<n> keys, at least 3 variants per group, lines match their declared arguments")
    func catalog() {
        let keys = TemplateFlavorProvider.catalog.map(\.key)
        #expect(Set(keys).count == keys.count && keys.allSatisfy { $0.hasPrefix("flavor.") })
        for group in FlavorGroup.allCases {
            #expect(TemplateFlavorProvider.catalog.filter { $0.group == group }.count >= 3)
        }
        let subjects: [FlavorSubject] = [
            arrival, .arrival(system: 1, viaWormhole: true, firstVisit: true, uneventful: false, encounterCount: 2),
            .arrival(system: 1, viaWormhole: false, firstVisit: false, uneventful: false, encounterCount: 2),
            .encounter(type: .policeInspect, opponent: .wasp, result: .other, rounds: 0, minHullPercent: 100),
            .quest(.lottery), .quest(.princessQuantum), .gameEnded(.retired), .achievement(.hero),
        ]
        for (i, subject) in subjects.enumerated() {
            for id in 0..<12 {
                let line = TemplateFlavorProvider().line(for: FlavorRequest(entryID: id, day: i, system: 2, subject: subject))
                let entry = TemplateFlavorProvider.catalog.first { $0.key == line.key }
                #expect(entry != nil, "\(line.key)")
                guard let entry else { continue }
                #expect(entry.argTypes.count == line.args.count && zip(entry.argTypes, line.args).allSatisfy { $0.matches($1) })
            }
        }
        #expect(!FlavorArgType.system.matches(.count(1)))
    }

    @Test("LLM-010 group choice: arrival wormhole > first visit > eventful > quiet; encounter by result; quest by chain; endings")
    func groups() {
        func a(_ via: Bool, _ first: Bool, _ n: Int) -> FlavorGroup {
            FlavorSubject.arrival(system: 0, viaWormhole: via, firstVisit: first, uneventful: n == 0, encounterCount: n).group
        }
        #expect(a(true, true, 3) == .arrivalWormhole && a(false, true, 3) == .arrivalFirstVisit)
        #expect(a(false, false, 3) == .arrivalEventful && a(false, false, 0) == .arrivalQuiet)
        let results: [(EncounterResultClass, FlavorGroup)] = [(.won, .encounterWon), (.fled, .encounterFled),
                                                              (.surrendered, .encounterSurrendered), (.lost, .encounterLost),
                                                              (.other, .encounterOther)]
        for (r, g) in results {
            #expect(FlavorSubject.encounter(type: .pirateAttack, opponent: .gnat, result: r, rounds: 1, minHullPercent: 1).group == g)
        }
        let chains: [(SpecialEventType, FlavorGroup)] = [
            (.dragonflyShield, .questDragonfly), (.spaceMonsterKilled, .questSpaceMonster), (.scarabUpgradeHull, .questScarab),
            (.japoriDelivery, .questJapori), (.jarekGetsOut, .questJarek), (.wildGetsOut, .questWild), (.reactorLaser, .questReactor),
            (.gemulonFuel, .questGemulon), (.experimentStopped, .questExperiment), (.artifactDelivery, .questArtifact),
            (.moonRetirement, .questMoon), (.tribbleBuyer, .questTribbles), (.sculptureHiddenBays, .questSculpture),
            (.princessQuantum, .questPrincess), (.skill, .questGeneric), (.cargoForSale, .questGeneric),
        ]
        for (e, g) in chains { #expect(FlavorSubject.quest(e).group == g) }
        #expect(SpecialEventType.allCases.allSatisfy { FlavorSubject.quest($0).group.rawValue.hasPrefix("quest.") })
        #expect(FlavorSubject.gameEnded(.killed).group == .gameEndedKilled && FlavorSubject.gameEnded(.retired).group == .gameEndedRetired)
        #expect(FlavorSubject.gameEnded(.boughtMoon).group == .gameEndedMoon && FlavorSubject.gameEnded(.boughtMoonGirl).group == .gameEndedMoon)
    }
}
