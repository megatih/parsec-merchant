// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// The C# newspaper tables (Strings.cs:154-156, :425-575), copied as fixtures (UI-ENC-068).
private enum CSharpNews {
    static let moon = "Seller in ^1 System has Utopian Moon available."
    static let shipyard = "Shipyard in ^1 System offers to design custom ships."
    static let tribble = "Collector in ^1 System seeks to purchase Tribbles."
    static let events = [
        "Scientist Adds Alien Artifact to Museum Collection.", "Police Trace Orbiting Space Litter to ^1.",
        "Experimental Craft Stolen! Critics Demand Security Review.", "Investigators Report Strange Craft.",
        "Spectacular Display as Stolen Ship Destroyed in Fierce Space Battle.", "Rumors Continue: Melina Orbitted by Odd Starcraft.",
        "Strange Ship Observed in Regulas Orbit.", "Unidentified Ship: A Threat to Zalkon?", "Huge Explosion Reported at Research Facility.",
        "Travelers Report Timespace Damage, Warp Problems!", "Scientists Cancel High-profile Test! Committee to Investigate Design.",
        "Travelers Claim Sighting of Ship Materializing in Orbit!", "Editorial: Who Will Warn Gemulon?", "Alien Invasion Devastates Planet!",
        "Invasion Imminent! Plans in Place to Repel Hostile Invaders.", "Thug Assaults Captain Ahab!",
        "Destruction of Captain Ahab's Ship Causes Anger!", "Captain Conrad Comes Under Attack By Criminal!",
        "Captain Conrad's Ship Destroyed by Villain!", "Famed Captain Huie Attacked by Brigand!",
        "Citizens Mourn Destruction of Captain Huie's Ship!", "Editorial: We Must Help Japori!",
        "Disease Antidotes Arrive! Health Officials Optimistic.", "Ambassador Jarek Returns from Crisis.",
        "Security Scandal: Test Craft Confirmed Stolen.", "Wormhole Traffic Delayed as Stolen Craft Destroyed.",
        "Wormhole Travelers Harassed by Unusual Ship!", "Space Monster Threatens Homeworld!",
        "Hero Slays Space Monster! Parade, Honors Planned for Today.", "Notorious Criminal Jonathan Wild Arrested!",
        "Rumors Suggest Known Criminal J. Wild May Come to Kravat!", "Priceless collector's item stolen from home of Geurge Locas!",
        "Space Corps follows ^3 with alleged stolen sculpture to ^2.", "Member of Royal Family kidnapped!",
        "Aggressive Ship Seen in Orbit Around Centauri", "Dangerous Scorpion Damages Several Other Ships Near Inthara",
        "Kidnappers Holding Out at Qonos", "Scorpion Defeated! Kidnapped Member of Galvon Royal Family Freed!", "Beloved Royal Returns Home!",
    ]
    static let headlines = [
        ["Riots, Looting Mar Factional Negotiations.", "Communities Seek Consensus.", "Successful Bakunin Day Rally!",
         "Major Faction Conflict Expected for the Weekend!"],
        ["Editorial: Taxes Too High!", "Market Indices Read Record Levels!", "Corporate Profits Up!",
         "Restrictions on Corporate Freedom Abolished by Courts!"],
        ["Party Reports Productivity Increase.", "Counter-Revolutionary Bureaucrats Purged from Party!", "Party: Bold New Future Predicted!",
         "Politburo Approves New 5-Year Plan!"],
        ["States Dispute Natural Resource Rights!", "States Denied Federal Funds over Local Laws!",
         "Southern States Resist Federal Taxation for Capital Projects!", "States Request Federal Intervention in Citrus Conflict!"],
        ["Robot Shortages Predicted for Q4.", "Profitable Quarter Predicted.", "CEO: Corporate Rebranding Progressing.",
         "Advertising Budgets to Increase."],
        ["Olympics: Software Beats Wetware in All Events!", "New Network Protocols To Be Deployed.", "Storage Banks to be Upgraded!",
         "System Backup Rescheduled."],
        ["Local Elections on Schedule!", "Polls: Voter Satisfaction High!", "Campaign Spending Aids Economy!", "Police, Politicians Vow Improvements."],
        ["New Palace Planned; Taxes Increase.", "Future Presents More Opportunities for Sacrifice!", "Insurrection Crushed: Rebels Executed!",
         "Police Powers to Increase!"],
        ["Drug Smugglers Sentenced to Death!", "Aliens Required to Carry Visible Identification at All Times!", "Foreign Sabotage Suspected.",
         "Stricter Immigration Laws Installed."],
        ["Farmers Drafted to Defend Lord's Castle!", "Report: Kingdoms Near Flashpoint!", "Baron Ignores Ultimatum!", "War of Succession Threatens!"],
        ["Court-Martials Up 2% This Year.", "Editorial: Why Wait to Invade?", "HQ: Invasion Plans Reviewed.", "Weapons Research Increases Kill-Ratio!"],
        ["King to Attend Celebrations.", "Queen's Birthday Celebration Ends in Riots!", "King Commissions New Artworks.", "Prince Exiled for Palace Plot!"],
        ["Dialog Averts Eastern Conflict!", "Universal Peace: Is it Possible?", "Editorial: Life in Harmony.", "Polls: Happiness Quotient High!"],
        ["Government Promises Increased Welfare Benefits!", "State Denies Food Rationing Required to Prevent Famine.",
         "'Welfare Actually Boosts Economy,' Minister Says.", "Hoarder Lynched by Angry Mob!"],
        ["Millions at Peace.", "Sun Rises.", "Countless Hearts Awaken.", "Serenity Reigns."],
        ["New Processor Hits 10 ZettaHerz!", "Nanobot Output Exceeds Expectation.", "Last Human Judge Retires.", "Software Bug Causes Mass Confusion."],
        ["High Priest to Hold Special Services.", "Temple Restoration Fund at 81%.", "Sacred Texts on Public Display.",
         "Dozen Blasphemers Excommunicated!"],
    ]
    static let mastheads = [
        ["The ^1 Arsenal", "The Grassroot", "Kick It!"], ["The Objectivist", "The ^1 Market", "The Invisible Hand"],
        ["The Daily Worker", "The People's Voice", "The ^1 Proletariat"], ["Planet News", "The ^1 Times", "Interstate Update"],
        ["^1 Memo", "News From The Board", "Status Report"], ["Pulses", "Binary Stream", "The System Clock"],
        ["The Daily Planet", "The ^1 Majority", "Unanimity"], ["The Command", "Leader's Voice", "The ^1 Mandate"],
        ["State Tribune", "Motherland News", "Homeland Report"], ["News from the Keep", "The Town Crier", "The ^1 Herald"],
        ["General Report", "^1 Dispatch", "The ^1 Sentry"], ["Royal Times", "The Loyal Subject", "The Fanfare"],
        ["Pax Humani", "Principle", "The ^1 Chorus"], ["All for One", "Brotherhood", "The People's Syndicate"],
        ["The Daily Koan", "Haiku", "One Hand Clapping"], ["The Future", "Hardware Dispatch", "TechNews"],
        ["The Spiritual Advisor", "Church Tidings", "The Temple Tribune"],
    ]
    static let hero = ["Locals Welcome Visiting Hero ^1!", "Famed Hero ^1 to Visit System!", "Large Turnout At Spaceport to Welcome ^1!"]
    static let villain = ["Police Warning: ^1 Will Dock At ^2!", "Notorious Criminal ^1 Sighted in ^2!",
                          "Locals Rally to Deny Spaceport Access to ^1!", "Terror Strikes Locals on Arrival of ^1!"]
    static let external = ["Reports of ^1 in the ^2 System.", "News of ^1 in the ^2 System.", "New Rumors of ^1 in the ^2 System.",
                           "Sources report ^1 in the ^2 System.", "Notice: ^1 in the ^2 System.", "Evidence Suggests ^1 in the ^2 System."]
    static let pressures = ["", "Strife and War", "Plague Outbreaks", "Severe Drought", "Terrible Boredom", "Cold Weather", "Crop Failures",
                            "Labor Shortages"]
    static let internalPressure = ["", "War News: Offensives Continue!", "Plague Spreads! Outlook Grim.", "No Rain in Sight!",
                                   "Editors: Won't Someone Entertain Us?", "Cold Snap Continues!", "Serious Crop Failure! Must We Ration?",
                                   "Jobless Rate at All-Time Low!"]

    static func fill(_ s: String, _ args: String...) -> String {
        var out = s
        for (i, a) in args.enumerated() { out = out.replacingOccurrences(of: "^\(i + 1)", with: a) }
        return out
    }
}

@MainActor
@Suite("Newspaper and special-event narrative (UI-ENC §10–11)")
struct NewspaperNarrativeTests {
    private let state = GameState(config: NewGameConfig(commanderName: "Reader", seed: 4))

    private func context(_ wording: NewsWording = .csharp) -> NewspaperText.Context {
        NewspaperText.Context(commander: "Jameson", currentSystem: "Acamar", shipType: "Gnat", wording: wording) { "Sys\($0)" }
    }

    /// A state offering `type` at the current system.
    private func offering(_ type: SpecialEventType, in base: GameState) -> GameState {
        var s = base
        s.galaxy.systems[s.commander.currentSystem].specialEvent = type
        return s
    }

    // MARK: UI-ENC-068 … 072

    @Test("UI-ENC-068 every headline case and masthead equals the C# string tables")
    func stringTables() {
        let c = context()
        for e in NewsEvent.allCases {
            #expect(NewspaperText.headline(.event(e), context: c) == CSharpNews.fill(CSharpNews.events[e.rawValue], "Jameson", "Acamar", "Gnat"))
        }
        for g in PoliticalSystemType.allCases {
            for i in 0..<NewsTables.mastheadsPerGovernment {
                #expect(NewspaperText.masthead(government: g, index: i, system: "Acamar") == CSharpNews.fill(CSharpNews.mastheads[g.rawValue][i], "Acamar"))
            }
            for i in 0..<NewsTables.cannedPerGovernment {
                #expect(NewspaperText.headline(.canned(government: g, index: i), context: c) == CSharpNews.headlines[g.rawValue][i])
            }
        }
        for p in SystemPressure.allCases where p != .none {
            #expect(NewspaperText.headline(.internalPressure(p), context: c) == CSharpNews.internalPressure[p.rawValue])
            for t in 0..<NewsTables.externalTemplates {
                #expect(NewspaperText.headline(.externalPressure(template: t, pressure: p, system: 7), context: c)
                        == CSharpNews.fill(CSharpNews.external[t], CSharpNews.pressures[p.rawValue], "Sys7"))
            }
        }
        for i in 0..<NewsTables.villainCount {
            #expect(NewspaperText.headline(.villain(index: i), context: c) == CSharpNews.fill(CSharpNews.villain[i], "Jameson", "Acamar"))
        }
        for i in 0..<NewsTables.heroCount {
            #expect(NewspaperText.headline(.hero(index: i), context: c) == CSharpNews.fill(CSharpNews.hero[i], "Jameson"))
        }
        #expect(NewspaperText.headline(.moonForSale(system: 2), context: c) == CSharpNews.fill(CSharpNews.moon, "Sys2"))
        #expect(NewspaperText.headline(.shipyard(system: 2), context: c) == CSharpNews.fill(CSharpNews.shipyard, "Sys2"))
        #expect(NewspaperText.headline(.tribbleBuyer(system: 2), context: c) == CSharpNews.fill(CSharpNews.tribble, "Sys2"))
        // Masthead of a real paper uses the paper's system.
        let paper = state.newspaper
        #expect(NewspaperText.masthead(paper, state: state)
                == CSharpNews.fill(CSharpNews.mastheads[paper.government.rawValue][paper.mastheadIndex], Names.system(paper.system, in: state)))
    }

    @Test("UI-ENC-069 NEWS-047 UI-ENC-106 template 3 reads \"Sources say\" under Palm content, \"Sources report\" otherwise")
    func palmWording() {
        for id in RulesetID.allCases {
            let s = GameState(config: NewGameConfig(commanderName: "W", ruleset: id, seed: 3))
            let c = NewspaperText.Context(state: s)
            let text = NewspaperText.headline(.externalPressure(template: 3, pressure: .war, system: 1), context: c)
            let palm = Ruleset.named(id).content.newsWording == .palm
            #expect(text.hasPrefix(palm ? "Sources say Strife and War" : "Sources report Strife and War"), "\(id)")
            #expect((id == .palm122) == palm)
        }
        for t in [0, 1, 2, 4, 5] {
            let a = NewspaperText.headline(.externalPressure(template: t, pressure: .cold, system: 1), context: context(.csharp))
            let b = NewspaperText.headline(.externalPressure(template: t, pressure: .cold, system: 1), context: context(.palm))
            #expect(a == b)
        }
    }

    @Test("UI-ENC-071 the newspaper sheet: masthead, date line, serif headlines in two balanced columns from four on; Palm page rule")
    func sheetModel() {
        var paper = state.newspaper
        paper.headlines = (0..<5).map { .canned(government: paper.government, index: $0 % 4) }
        let model = NewspaperSheetModel.make(paper: paper, state: state)
        #expect(model.masthead == NewspaperText.masthead(paper, state: state))
        #expect(model.dateLine == "Day \(state.commander.days) · \(Names.system(paper.system, in: state)) · \(state.newspaperCost) cr.")
        #expect(model.columns.count == 2 && model.columns[0].count == 3 && model.columns[1].count == 2)
        paper.headlines = Array(paper.headlines.prefix(3))
        #expect(NewspaperSheetModel.make(paper: paper, state: state).columns.count == 1)
        // Palm: the shown headlines are the page-limited ones (NEWS-046).
        let palm = GameState(config: NewGameConfig(commanderName: "P", ruleset: .palm122, seed: 8))
        let context = NewspaperText.Context(state: palm)
        let expected = palm.newspaper.applyingPageLimit { NewspaperText.palmMetrics($0, context: context) }
        #expect(NewspaperText.shownHeadlines(palm.newspaper, state: palm) == expected)
        #expect(NewspaperText.shownHeadlines(state: palm) == expected)
        #expect(NewspaperText.shownHeadlines(state.newspaper, state: state) == state.newspaper.headlines)
        #expect(PalmStdFont.width(of: "iii") < PalmStdFont.width(of: "MMM"))
        let ids = [AXID.Newspaper.sheet, AXID.Newspaper.masthead, AXID.Newspaper.headline(0), AXID.Decision.newspaperClose]
        #expect(ids.allSatisfy(AXID.all.contains))
    }

    @Test("UI-ENC-072 the Bridge newspaper card: masthead once paid, price before; Read and the menu are disabled when unaffordable")
    func newspaperCard() throws {
        var s = state
        s.paidForNewspaper = false
        let unpaid = NewspaperCardModel.make(state: s)
        #expect(unpaid.masthead == nil && unpaid.blocker == nil && unpaid.command == .readNewspaper)
        s.paidForNewspaper = true
        #expect(NewspaperCardModel.make(state: s).masthead == NewspaperText.masthead(s.newspaper, state: s))
        var broke = state
        broke.commander.cash = 0
        #expect(NewspaperCardModel.make(state: broke).blocker == .insufficientFunds)
        let ctx = MenuContext.make(state: broke, isModal: false)
        #expect(MenuRules.availability(of: .newspaper, in: ctx) == .disabled(.engine(.insufficientFunds)))
        #expect(MenuRules.availability(of: .newspaper, in: MenuContext.make(state: state, isModal: false)).isEnabled)
        // Read sends .readNewspaper (the buyNewspaper consent first).
        let session = try TestSessions.playing()
        session.readNewspaper()
        guard case let .confirmation(pending) = session.presentation else {
            Issue.record("Read asks to buy the paper")
            return
        }
        #expect(pending.confirmation.warning == .buyNewspaper && pending.command == .readNewspaper)
        #expect([BridgeID.System.news].allSatisfy(AXID.all.contains))
    }

    // MARK: UI-ENC-073 … 080

    @Test("UI-ENC-073 the special card's excerpt is the first sentence or 160 characters and …; Read opens the offer page")
    func specialCard() throws {
        #expect(NarrativeModel.excerpt("Short one. Second sentence.") == "Short one.")
        #expect(NarrativeModel.excerpt("No stop") == "No stop")
        let long = String(repeating: "word ", count: 50) + "end."
        #expect(NarrativeModel.excerpt(long) == String(long.prefix(160)) + "…")
        let lottery = String(localized: SpecialEventText.story(.lottery))
        #expect(NarrativeModel.excerpt(lottery) == "You are lucky!")
        let session = try TestSessions.playing()
        let current = try #require(session.state)
        let found = SpecialEventType.allCases.map { offering($0, in: current) }.first { $0.specialEventAvailable != nil }
        let candidate = try #require(found)
        try TestSessions.edit(session) { $0 = candidate }
        session.openSpecialEvent()
        #expect(session.presentation == .sheet(.narrative(.offer(try #require(candidate.specialEventAvailable)))))
    }

    @Test("UI-ENC-074 UI-ENC-079 offer pages for all 46 types (Modern) and the Palm subset: title, story, price line, message-only")
    func offerPages() {
        for id in RulesetID.allCases {
            let s = GameState(config: NewGameConfig(commanderName: "O", ruleset: id, seed: 6))
            for type in SpecialEventType.allCases {
                guard let spec = s.specialEventSpec(type) else {
                    #expect(id != .modern, "Modern has every type: \(type)")
                    continue
                }
                let offer = NarrativeModel.offer(type: type, state: s, preview: nil)
                #expect(!offer.title.isEmpty && !offer.story.isEmpty, "\(id) \(type)")
                #expect(offer.messageOnly == spec.messageOnly, "\(id) \(type)")
                #expect(offer.priceLine == NarrativeModel.priceLine(spec.price))
                #expect(NarrativeText.hasResultPage(type) != NarrativeText.feedOnly.contains(type))
            }
        }
        #expect(NarrativeModel.priceLine(1_000) == "Costs 1,000 cr." && NarrativeModel.priceLine(-500) == "You receive 500 cr.")
        #expect(NarrativeModel.priceLine(0) == nil)
        #expect(NarrativeModel.vignette(.dragonfly) == .ship && NarrativeModel.vignette(.moon) == .planet)
        var poor = offering(.eraseRecord, in: state)
        poor.commander.policeRecordScore = -30
        poor.commander.cash = 0
        if poor.specialEventAvailable == .eraseRecord {
            let blocked = NarrativeModel.offer(type: .eraseRecord, state: poor, preview: GameEngine(state: poor).specialEventPreview)
            #expect(blocked.blocker == .insufficientFunds && !blocked.canAccept)
        }
    }

    @Test("UI-ENC-075 ALR-152 ALR-154 Accept is disabled with the inline reason: insufficient funds, no free quarters")
    func acceptBlockers() throws {
        let session = try TestSessions.playing()
        var poor = offering(.moon, in: try #require(session.state))
        poor.commander.cash = 0
        try TestSessions.edit(session) { $0 = poor }
        if session.state?.specialEventAvailable == .moon {
            let preview = try #require(session.engine?.specialEventPreview)
            let offer = NarrativeModel.offer(type: .moon, state: poor, preview: preview)
            #expect(offer.blocker == .insufficientFunds && !offer.canAccept)
        }
        var full = offering(.jarek, in: try #require(session.state))
        full.commander.cash = 100_000
        full.commander.ship.crew = full.commander.ship.crew.map { $0 ?? 5 }
        try TestSessions.edit(session) { $0 = full }
        if session.state?.specialEventAvailable == .jarek {
            let offer = NarrativeModel.offer(type: .jarek, state: full, preview: session.engine?.specialEventPreview)
            #expect(offer.blocker == .noFreeQuarters)
        }
        #expect([AXID.Narrative.sheet, AXID.Narrative.title, AXID.Narrative.vignette, AXID.Narrative.story, AXID.Narrative.accept,
                 AXID.Narrative.decline, AXID.Narrative.continueButton].allSatisfy(AXID.all.contains))
    }

    @Test("UI-ENC-076 UI-ENC-077 Accept closes the sheet, then sends the event acknowledged; follow-up consents are dialogs; results page")
    func acceptFlow() throws {
        // A priced event with a result page (Erase Record → "Clean Record", ALR-150).
        let session = try TestSessions.playing()
        var s = offering(.eraseRecord, in: try #require(session.state))
        s.commander.cash = 100_000
        s.commander.policeRecordScore = -30
        try TestSessions.edit(session) { $0 = s }
        try #require(session.state?.specialEventAvailable == .eraseRecord)
        session.send(.specialEvent)
        #expect(session.presentation == .sheet(.narrative(.offer(.eraseRecord))))
        session.acceptSpecialEvent(messageOnly: false)
        guard case let .sheet(.narrative(.result(result))) = session.presentation else {
            Issue.record("the result page follows: \(String(describing: session.presentation))")
            return
        }
        #expect(result.title == "Clean Record" && result.message == "The hacker resets your police record to Clean.")
        #expect(session.state?.specialEventAvailable == nil || session.state?.specialEventAvailable != .eraseRecord)
        session.dismissPresentation()

        // The reactor with Wild aboard: the Wild warning is a dialog whose resend still acknowledges the event.
        var r = offering(.reactor, in: try #require(session.state))
        r.commander.policeRecordScore = -10
        r.commander.reputationScore = 500
        r.commander.ship.cargo = r.commander.ship.cargo.map { _ in 0 }
        r.commander.ship.crew = [CrewID.commander, CrewID.wild] + Array(repeating: nil, count: 3)
        r.quests.wild = QuestStatus.Wild.started
        try TestSessions.edit(session) { $0 = r }
        if session.state?.specialEventAvailable == .reactor {
            session.openSpecialEvent()
            session.acceptSpecialEvent(messageOnly: false)
            if case let .confirmation(pending) = session.presentation {
                #expect(pending.confirmation.warning == .wildLeavesForReactor)
                #expect(pending.acknowledgingOnConfirm == [.acceptSpecialEvent, .wildLeavesForReactor])
            }
        }

        // A message-only event: Continue sends without an acknowledgement; no result page (feed only).
        let lotterySession = try TestSessions.playing()
        try TestSessions.edit(lotterySession) { $0 = offering(.lottery, in: $0) }
        if lotterySession.state?.specialEventAvailable == .lottery {
            lotterySession.openSpecialEvent()
            lotterySession.acceptSpecialEvent(messageOnly: true)
            #expect(lotterySession.presentation == nil && lotterySession.lastRejection == nil)
            #expect(lotterySession.feed.contains { $0.event == .specialEventCompleted(.lottery) })
        }
    }

    @Test("""
        UI-ENC-078 UI-ENC-080 ALR-002 ALR-083 ALR-084 ALR-086 ALR-087 ALR-089 ALR-129 ALR-149 ALR-150 ALR-153 ALR-162 \
        ALR-163 ALR-164 ALR-171 ALR-175 ALR-184 NarrativeText.result worded as the C# alerts; nil for the feed-only types
        """)
    func resultPages() throws {
        let s = state
        func page(_ type: SpecialEventType, after: GameState? = nil) -> NarrativeResult? {
            NarrativeText.result(for: [.specialEventCompleted(type)], before: s, after: after ?? s)
        }
        let expected: [(SpecialEventType, String, String)] = [
            (.japori, "Antidote", "Ten of your cargo bays now contain antidote for the Japori system."),
            (.gemulonFuel, "Fuel Compactor", "You now have a fuel compactor installed on your ship."),
            (.dragonflyShield, "Lightning Shield", "You now have one lightning shield installed on your ship."),
            (.reactorLaser, "Morgan's Laser", "You now have Henry Morgan's special laser installed on your ship."),
            (.princessQuantum, "Quantum Disruptor", "You now have one quantum disruptor installed on your ship."),
            (.reactor, "Reactor", "Five of your cargo bays now contain the unstable Ion Reactor, and ten of your bays contain enriched fuel."),
            (.scarabUpgradeHull, "Hull Upgraded", "Technicians spend the day retrofitting the hull of your ship."),
            (.eraseRecord, "Clean Record", "The hacker resets your police record to Clean."),
            (.moon, "Moon Bought", "You bought a moon in the Utopia system. Go there to claim it."),
            (.tribbleBuyer, "No More Tribbles", "The alien uses his alien technology to beam over your whole collection of tribbles to his ship."),
            (.tribble, "A Tribble", "You are now the proud owner of a little, cute, furry tribble."),
        ]
        for (type, title, message) in expected {
            let p = try #require(page(type), "\(type)")
            #expect(p.title == title && p.message == message && p.type == type)
        }
        #expect(page(.sculptureHiddenBays)?.message.hasPrefix("You now have hidden compartments equivalent to 5 extra cargo bays") == true)
        let jarek = try #require(page(.jarek))
        #expect(jarek.title == "Passenger On Board" && jarek.message.hasPrefix("You have taken \(Names.crew(CrewID.jarek, in: s)) on board."))
        #expect(page(.princessQonos)?.message.contains(Names.crew(CrewID.princess, in: s)) == true)
        var withSculpture = s
        withSculpture.quests.sculpture = QuestStatus.Sculpture.inTransit
        #expect(page(.wild, after: withSculpture)?.message.contains("Jonathan Wild sees the stolen sculpture.") == true)
        #expect(page(.wild)?.message.contains("sculpture") == false)
        var trained = s
        trained.mercenaries[CrewID.commander].skills[SkillType.trader.rawValue] += 1
        let skill = try #require(page(.skill, after: trained))
        #expect(skill.title == "Skill Increase" && skill.message.contains(String(localized: Names.skill(.trader))))
        let canisters = try #require(NarrativeText.result(for: [.sealedCanisters(.robots)], before: s, after: s))
        #expect(canisters.title == "Sealed Canisters" && canisters.message.hasPrefix("You bought the sealed canisters and put them in your cargo bays."))
        let refused = try #require(NarrativeText.result(for: [.specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot)],
                                                        before: s, after: s))
        #expect(refused.message == ReasonText.string(for: .noFreeSlot))
        // Feed-only types, listed explicitly.
        let feedOnly: Set<SpecialEventType> = [.artifact, .artifactDelivery, .cargoForSale, .dragonfly, .dragonflyBaratas, .dragonflyDestroyed,
                                               .dragonflyMelina, .dragonflyRegulas, .experiment, .experimentFailed, .experimentStopped, .gemulon,
                                               .gemulonInvaded, .gemulonRescued, .japoriDelivery, .jarekGetsOut, .lottery, .moonRetirement,
                                               .reactorDelivered, .scarab, .scarabDestroyed, .spaceMonster, .spaceMonsterKilled, .wildGetsOut,
                                               .sculpture, .sculptureDelivered, .princess, .princessCentauri, .princessInthara, .princessReturned]
        #expect(NarrativeText.feedOnly == feedOnly)
        for type in feedOnly { #expect(page(type) == nil, "\(type)") }
        #expect(NarrativeText.result(for: [.arrived(system: 1)], before: s, after: s) == nil)
        // UI-ENC-080: every narrative ALR row reaches a result page or a comm line, without chain-specific views.
        for row in ALRCatalog.rows {
            switch row.presentation.narrativeKey {
            case let .specialEventResult(types)?:
                for t in types { #expect(NarrativeText.hasResultPage(t), "row \(row.number) \(t)") }
            case .sealedCanisters?:
                #expect(NarrativeText.result(for: [.sealedCanisters(.water)], before: s, after: s) != nil)
            case let .passengerComm(id, impatient)?:
                #expect(PassengerComm.line(crewID: id, impatient: impatient, state: s).hasPrefix("Ship's comm — "))
            case nil:
                break
            }
        }
    }
}
