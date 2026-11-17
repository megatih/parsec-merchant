// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence
import Testing
@testable import ParsecMerchant

/// LLM §3–§5: the app's flavor service, the Foundation Models provider behind fakes, settings and the launch argument.
@MainActor
struct FlavorTests {
    static func entry(_ id: Int, _ kind: LogEntryKind, flavor: FlavorText? = .template(FlavorLine(key: "flavor.achievement.1", args: [])))
        -> LogEntry {
        LogEntry(id: id, day: 3, system: 0, worth: 1000, kind: kind, flavor: flavor)
    }

    static let request = FlavorRequest(entryID: 7, day: 12, system: 3,
                                       subject: .arrival(system: 3, viaWormhole: false, firstVisit: true, uneventful: true,
                                                         encounterCount: 0))

    // MARK: Mode, availability, settings

    @Test("LLM-024 -PMFlavor template forces templates; parsing and mode derivation")
    func launchArgument() {
        #expect(LaunchOptions.parse(["-PMFlavor", "template"], isDebug: true).flavorTemplate)
        #expect(!LaunchOptions.parse(["-PMFlavor", "model"], isDebug: true).flavorTemplate)
        var forced = LaunchOptions()
        forced.flavorTemplate = true
        #expect(FlavorMode.derive(launch: forced, useFoundationModels: true) == .templateForced)
        #expect(FlavorMode.derive(launch: .none, useFoundationModels: false) == .templateOnly)
        #expect(FlavorMode.derive(launch: .none, useFoundationModels: true) == .foundationModels)
    }

    @Test("LLM-024 a session built without a flavor service uses templates and never creates a provider")
    func testsForceTemplates() throws {
        let s = try TestSessions.make()
        #expect(s.flavor.mode == .templateForced && s.flavor.isTemplateOnly)
        let service = FlavorService(mode: .templateForced) { Issue.record("no provider in templateForced"); return nil }
        service.enqueue([Self.entry(1, .achievementUnlocked(.firstProfit))], gameID: "g") { .empty }
        #expect(!service.providerCreated && service.waiting.isEmpty && service.inFlight == nil)
        service.setMode(.foundationModels)
        #expect(service.mode == .templateForced)
    }

    @Test("LLM-025 the Intelligence settings: keys, defaults, availability reasons and the forced-template status")
    func settingsModel() throws {
        let defaults = try #require(UserDefaults(suiteName: "pm-flavor-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.useFoundationModels && settings.showFlavor && settings.showRecommendations)
        #expect(AppSettingsKey.useFoundationModels == "settings.flavor.useFoundationModels")
        #expect(AppSettingsKey.showFlavor == "settings.flavor.show")
        #expect(AppSettingsKey.showRecommendations == "settings.intel.showRecommendations")
        #expect(Set(FlavorAvailability.allCases.map(\.text)).count == FlavorAvailability.allCases.count)
        #expect(FlavorAvailability.deviceNotEligible.text == "This Mac doesn't support Apple Intelligence")
        #expect(FlavorAvailability.unsupportedBuild.text == "Not available in this build")
        let available = FlavorSettingsModel.make(launch: .none, availability: .available)
        #expect(available.toggleEnabled && available.status == "Available")
        #expect(!FlavorSettingsModel.make(launch: .none, availability: .modelNotReady).toggleEnabled)
        var forced = LaunchOptions()
        forced.flavorTemplate = true
        let f = FlavorSettingsModel.make(launch: forced, availability: .available)
        #expect(!f.toggleEnabled && f.status == "Template text is forced by a launch argument")
        #expect([AXID.IntelSettings.foundationModels, AXID.IntelSettings.flavorStatus, AXID.IntelSettings.showFlavor]
            == ["settings.flavor.foundationModels", "settings.flavor.status", "settings.flavor.show"])
        #expect(SettingsTab.intelligence.arrivesIn == nil)
    }

    @Test("LLM-026 turning the toggle off cancels the queue; generated texts stay; on affects later entries only")
    func toggle() async throws {
        let gate = GatedGenerator()
        let service = FlavorService(mode: .templateOnly) { gate.generator }
        service.enqueue([Self.entry(1, .achievementUnlocked(.firstProfit))], gameID: "g") { .empty }
        #expect(service.inFlight == nil && !service.providerCreated)
        service.setMode(.foundationModels)
        service.enqueue([Self.entry(2, .achievementUnlocked(.firstProfit))], gameID: "g") { .empty }
        await gate.waitForStart(count: 1)
        #expect(gate.started == [2])
        service.setMode(.templateOnly)
        #expect(service.inFlight == nil && service.waiting.isEmpty)
    }

    // MARK: Foundation Models provider (fakes only)

    @Test("LLM-012 LLM-013 the provider answers through the injected client only when available")
    func availabilityGate() async {
        let client = FakeModelClient(.answer("We slipped into orbit quietly."))
        let unavailable = FoundationModelsFlavorProvider(client: client, availability: { .appleIntelligenceNotEnabled })
        #expect(await unavailable.flavor(for: Self.request, names: .empty) == nil)
        #expect(client.calls == 0)
        let available = FoundationModelsFlavorProvider(client: client, availability: { .available })
        #expect(await available.flavor(for: Self.request, names: .empty) == .generated(text: "We slipped into orbit quietly."))
        #expect(client.calls == 1 && available.source == .foundationModels)
    }

    @Test("LLM-014 the 4 s timeout wins over a client that never answers; nothing is applied afterwards")
    func timeout() async {
        let clock = ManualClock()
        let provider = FoundationModelsFlavorProvider(client: FakeModelClient(.hang), availability: { .available }, clock: clock)
        #expect(provider.timeout == .seconds(4))
        let task = Task { await provider.flavor(for: Self.request, names: .empty) }
        await clock.waitForSleepers()
        clock.advance(by: .seconds(3))
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .seconds(1))
        #expect(await task.value == nil)
    }

    @Test("LLM-015 errors return nil; output is trimmed, unwrapped, stripped, length-checked")
    func validation() async {
        let failing = FoundationModelsFlavorProvider(client: FakeModelClient(.fail), availability: { .available })
        #expect(await failing.flavor(for: Self.request, names: .empty) == nil)
        #expect(FlavorOutputValidator.validate("  We arrived.\nAll quiet.  ") == "We arrived. All quiet.")
        #expect(FlavorOutputValidator.validate("**Bold** and \"quoted\" _words_") == "Bold and quoted words")
        #expect(FlavorOutputValidator.validate("   \n ") == nil)
        let long = String(repeating: "word ", count: 30) + "end. " + String(repeating: "more ", count: 40)
        let cut = FlavorOutputValidator.validate(long)
        #expect(cut?.hasSuffix("end.") == true && (cut?.count ?? 999) <= 240)
        #expect(FlavorOutputValidator.validate(String(repeating: "a", count: 300)) == nil)
    }

    @Test("LLM-016 fixed instructions and golden prompts per subject; no commander or ship names")
    func prompts() {
        let names = FlavorNames(systems: ["Acamar", "Rhymus"], ships: ShipType.allCases.map { "\($0)" }, language: "English")
        #expect(FlavorPromptBuilder.instructions.hasPrefix("You write one or two short sentences for a starship captain's log"))
        let arrival = FlavorRequest(entryID: 1, day: 2, system: 1,
                                    subject: .arrival(system: 1, viaWormhole: true, firstVisit: true, uneventful: false, encounterCount: 2))
        #expect(FlavorPromptBuilder.prompt(for: arrival, names: names)
            == "The ship arrived at the Rhymus system through a wormhole. It was the first visit there. "
            + "There were 2 encounters on the way. Write the log line in English.")
        let enc = FlavorRequest(entryID: 1, day: 2, system: 1,
                                subject: .encounter(type: .pirateAttack, opponent: .gnat, result: .won, rounds: 3, minHullPercent: 40))
        #expect(FlavorPromptBuilder.prompt(for: enc, names: names)
            == "The ship met a pirate gnat. Result: the ship won after 3 rounds of combat; the hull fell to 40 percent. "
            + "Write the log line in English.")
        let end = FlavorRequest(entryID: 1, day: 2, system: 1, subject: .gameEnded(.retired))
        #expect(FlavorPromptBuilder.prompt(for: end, names: names) == "The career ended: the commander retired. Write the log line in English.")
        let quest = FlavorRequest(entryID: 1, day: 2, system: 1, subject: .quest(.japoriDelivery))
        #expect(FlavorPromptBuilder.prompt(for: quest, names: names).contains("japori delivery"))
        let ach = FlavorRequest(entryID: 1, day: 2, system: 1, subject: .achievement(.firstProfit))
        #expect(FlavorPromptBuilder.prompt(for: ach, names: names).contains("First Profit"))
    }

    @Test("LLM-017 the production client is the on-device default model (or no provider in a build without it)")
    func onDeviceOnly() {
        #if canImport(FoundationModels)
        #expect(FoundationModelsFlavorProvider.system()?.client is SystemLanguageModelClient)
        #else
        #expect(FoundationModelsFlavorProvider.system() == nil)
        #endif
    }

    // MARK: Service and cache

    @Test("LLM-018 LLM-019 one request in flight, at most 8 waiting (oldest dropped), cancelled on close/new/load")
    func queue() async throws {
        let gate = GatedGenerator()
        let service = FlavorService(mode: .foundationModels) { gate.generator }
        var results: [FlavorResult] = []
        service.setResultHandler { results.append($0) }
        let entries = (1...11).map { Self.entry($0, .achievementUnlocked(.firstProfit)) }
        // An entry without a flavor subject and one that already has generated prose are never requested.
        let skipped = [Self.entry(20, .cheatsEnabled), Self.entry(21, .achievementUnlocked(.moon), flavor: .generated(text: "x"))]
        service.enqueue(entries + skipped, gameID: "g") { .empty }
        await gate.waitForStart(count: 1)
        #expect(service.inFlight?.request.entryID == 1)
        #expect(service.waiting.map(\.request.entryID) == Array(4...11))
        gate.release(1, with: .generated(text: "Prose."))
        await gate.waitForStart(count: 2)
        #expect(results == [FlavorResult(entryID: 1, gameID: "g", text: .generated(text: "Prose."))])
        #expect(service.inFlight?.request.entryID == 4)
        service.cancelAll()
        gate.release(4, with: .generated(text: "Too late."))
        for _ in 0..<50 { await Task.yield() }
        #expect(results.count == 1 && service.waiting.isEmpty && service.inFlight == nil)
    }

    @Test("LLM-020 a nil or template answer keeps the entry's template")
    func fallback() async {
        let gate = GatedGenerator()
        let service = FlavorService(mode: .foundationModels) { gate.generator }
        var results: [FlavorResult] = []
        service.setResultHandler { results.append($0) }
        service.enqueue([Self.entry(1, .achievementUnlocked(.firstProfit)), Self.entry(2, .achievementUnlocked(.moon))], gameID: "g") {
            .empty
        }
        await gate.waitForStart(count: 1)
        gate.release(1, with: nil)
        await gate.waitForStart(count: 2)
        gate.release(2, with: .template(FlavorLine(key: "k", args: [])))
        for _ in 0..<50 { await Task.yield() }
        #expect(results.isEmpty)
    }

    @Test("LLM-021 LLM-022 LOG-027 generated prose is cached only for the same game and a template entry; nothing else changes")
    func cache() throws {
        let s = try TestSessions.playing()
        var j = try #require(s.journal)
        let id = j.nextEntryID
        j.entries.append(Self.entry(id, .achievementUnlocked(.firstProfit)))
        j.nextEntryID += 1
        s.journal = j
        let before = (s.state, s.stateGeneration, s.feed, s.presentation, s.pendingPresentations)
        let autosave = try? s.slotStore.info(slot: "autosave").modified
        s.applyGeneratedFlavor(FlavorResult(entryID: id, gameID: "other", text: .generated(text: "Nope.")))
        #expect(s.journal?.entries.last?.flavor?.source == .template)
        s.applyGeneratedFlavor(FlavorResult(entryID: id, gameID: try #require(s.gameID), text: .generated(text: "We celebrated.")))
        #expect(s.journal?.entries.last?.flavor == .generated(text: "We celebrated."))
        s.applyGeneratedFlavor(FlavorResult(entryID: id, gameID: try #require(s.gameID), text: .generated(text: "Again.")))
        #expect(s.journal?.entries.last?.flavor == .generated(text: "We celebrated."))
        #expect(s.state == before.0 && s.stateGeneration == before.1 && s.feed == before.2 && s.presentation == before.3
            && s.pendingPresentations == before.4)
        #expect((try? s.slotStore.info(slot: "autosave").modified) == autosave)
    }

    @Test("LLM-023 the service never blocks the main actor: a slow model does not delay the next send")
    func neverBlocks() async throws {
        let gate = GatedGenerator()
        let service = FlavorService(mode: .foundationModels) { gate.generator }
        let s = try TestSessions.playing()
        let start = ContinuousClock.now
        service.enqueue([Self.entry(1, .achievementUnlocked(.firstProfit))], gameID: "g") { .empty }
        s.send(.selectTarget(s.state?.destinations.first ?? 0))
        #expect(ContinuousClock.now - start < .seconds(1))
        await gate.waitForStart(count: 1)
        #expect(service.inFlight != nil)
        service.cancelAll()
    }
}
