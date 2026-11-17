// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-068: the newspaper's masthead and headline texts from the classic string tables (Strings.cs `NewsMastheads`,
/// `NewsEvent`, `NewsPressureInternal`, `NewsPoliceRecordPsychopath`/`Hero`, `NewsMoonForSale`/`Shipyard`/`TribbleBuyer`,
/// `NewsPressureExternal`/`Pressures`, `NewsHeadlines`). Palm records use the same tables (NEWS-047) except distant-story
/// template 3, chosen by the ruleset's content `newsWording`, never by its id (UI-ENC-069).
enum NewspaperText {
    /// The names a headline substitutes (`^1`/`^2`/`^3` of the C# templates).
    struct Context: Sendable {
        var commander: String
        var currentSystem: String
        var shipType: String
        var wording: NewsWording
        var systemName: @Sendable (Int) -> String

        init(state: GameState) {
            let names = state.ruleset.tables.systemNames
            commander = state.commander.name
            currentSystem = Names.system(state.commander.currentSystem, in: state)
            shipType = String(localized: Names.ship(state.commander.ship.type))
            wording = state.ruleset.content.newsWording
            systemName = { names.indices.contains($0) ? names[$0] : "#\($0)" }
        }

        init(commander: String, currentSystem: String, shipType: String, wording: NewsWording,
             systemName: @escaping @Sendable (Int) -> String) {
            self.commander = commander
            self.currentSystem = currentSystem
            self.shipType = shipType
            self.wording = wording
            self.systemName = systemName
        }
    }

    // MARK: Masthead

    /// `NewsMastheads[government][index]` with `^1` = the paper's system.
    static func masthead(_ paper: Newspaper, state: GameState) -> String {
        masthead(government: paper.government, index: paper.mastheadIndex, system: Names.system(paper.system, in: state))
    }

    static func masthead(government: PoliticalSystemType, index: Int, system: String) -> String {
        let heads = mastheads(government, system: system)
        return String(localized: heads[min(max(0, index), heads.count - 1)])
    }

    static func mastheads(_ g: PoliticalSystemType, system s: String) -> [LocalizedStringResource] {
        switch g {
        case .anarchy: ["The \(s) Arsenal", "The Grassroot", "Kick It!"]
        case .capitalist: ["The Objectivist", "The \(s) Market", "The Invisible Hand"]
        case .communist: ["The Daily Worker", "The People's Voice", "The \(s) Proletariat"]
        case .confederacy: ["Planet News", "The \(s) Times", "Interstate Update"]
        case .corporate: ["\(s) Memo", "News From The Board", "Status Report"]
        case .cybernetic: ["Pulses", "Binary Stream", "The System Clock"]
        case .democracy: ["The Daily Planet", "The \(s) Majority", "Unanimity"]
        case .dictatorship: ["The Command", "Leader's Voice", "The \(s) Mandate"]
        case .fascist: ["State Tribune", "Motherland News", "Homeland Report"]
        case .feudal: ["News from the Keep", "The Town Crier", "The \(s) Herald"]
        case .military: ["General Report", "\(s) Dispatch", "The \(s) Sentry"]
        case .monarchy: ["Royal Times", "The Loyal Subject", "The Fanfare"]
        case .pacifist: ["Pax Humani", "Principle", "The \(s) Chorus"]
        case .socialist: ["All for One", "Brotherhood", "The People's Syndicate"]
        case .satori: ["The Daily Koan", "Haiku", "One Hand Clapping"]
        case .technocracy: ["The Future", "Hardware Dispatch", "TechNews"]
        case .theocracy: ["The Spiritual Advisor", "Church Tidings", "The Temple Tribune"]
        }
    }

    // MARK: Headlines

    static func headline(_ h: Headline, state: GameState) -> String {
        headline(h, context: Context(state: state))
    }

    /// One headline's text. A `switch` without `default` (UI-ENC-068).
    static func headline(_ h: Headline, context c: Context) -> String {
        switch h {
        case let .event(e):
            return String(localized: event(e, commander: c.commander, system: c.currentSystem, ship: c.shipType))
        case let .internalPressure(p):
            return internalPressure(p).map { String(localized: $0) } ?? ""
        case let .villain(index):
            let all = villain(commander: c.commander, system: c.currentSystem)
            return String(localized: all[min(max(0, index), all.count - 1)])
        case let .hero(index):
            let all = hero(commander: c.commander)
            return String(localized: all[min(max(0, index), all.count - 1)])
        case let .moonForSale(system):
            return String(localized: "Seller in \(c.systemName(system)) System has Utopian Moon available.")
        case let .shipyard(system):
            return String(localized: "Shipyard in \(c.systemName(system)) System offers to design custom ships.")
        case let .tribbleBuyer(system):
            return String(localized: "Collector in \(c.systemName(system)) System seeks to purchase Tribbles.")
        case let .externalPressure(template, pressure, system):
            let word = externalPressureWord(pressure).map { String(localized: $0) } ?? ""
            return String(localized: externalPressure(template: template, word: word, system: c.systemName(system), wording: c.wording))
        case let .canned(government, index):
            let all = canned(government)
            return String(localized: all[min(max(0, index), all.count - 1)])
        }
    }

    // swiftlint:disable cyclomatic_complexity
    /// `NewsEvent[rawValue]`: ^1 = commander, ^2 = current system, ^3 = ship type.
    static func event(_ e: NewsEvent, commander: String, system: String, ship: String) -> LocalizedStringResource {
        switch e {
        case .artifactDelivery: "Scientist Adds Alien Artifact to Museum Collection."
        case .caughtLittering: "Police Trace Orbiting Space Litter to \(commander)."
        case .dragonfly: "Experimental Craft Stolen! Critics Demand Security Review."
        case .dragonflyBaratas: "Investigators Report Strange Craft."
        case .dragonflyDestroyed: "Spectacular Display as Stolen Ship Destroyed in Fierce Space Battle."
        case .dragonflyMelina: "Rumors Continue: Melina Orbitted by Odd Starcraft."
        case .dragonflyRegulas: "Strange Ship Observed in Regulas Orbit."
        case .dragonflyZalkon: "Unidentified Ship: A Threat to Zalkon?"
        case .experimentFailed: "Huge Explosion Reported at Research Facility."
        case .experimentPerformed: "Travelers Report Timespace Damage, Warp Problems!"
        case .experimentStopped: "Scientists Cancel High-profile Test! Committee to Investigate Design."
        case .experimentArrival: "Travelers Claim Sighting of Ship Materializing in Orbit!"
        case .gemulon: "Editorial: Who Will Warn Gemulon?"
        case .gemulonInvaded: "Alien Invasion Devastates Planet!"
        case .gemulonRescued: "Invasion Imminent! Plans in Place to Repel Hostile Invaders."
        case .captAhabAttacked: "Thug Assaults Captain Ahab!"
        case .captAhabDestroyed: "Destruction of Captain Ahab's Ship Causes Anger!"
        case .captConradAttacked: "Captain Conrad Comes Under Attack By Criminal!"
        case .captConradDestroyed: "Captain Conrad's Ship Destroyed by Villain!"
        case .captHuieAttacked: "Famed Captain Huie Attacked by Brigand!"
        case .captHuieDestroyed: "Citizens Mourn Destruction of Captain Huie's Ship!"
        case .japori: "Editorial: We Must Help Japori!"
        case .japoriDelivery: "Disease Antidotes Arrive! Health Officials Optimistic."
        case .jarekGetsOut: "Ambassador Jarek Returns from Crisis."
        case .scarab: "Security Scandal: Test Craft Confirmed Stolen."
        case .scarabDestroyed: "Wormhole Traffic Delayed as Stolen Craft Destroyed."
        case .scarabHarass: "Wormhole Travelers Harassed by Unusual Ship!"
        case .spaceMonster: "Space Monster Threatens Homeworld!"
        case .spaceMonsterKilled: "Hero Slays Space Monster! Parade, Honors Planned for Today."
        case .wildArrested: "Notorious Criminal Jonathan Wild Arrested!"
        case .wildGetsOut: "Rumors Suggest Known Criminal J. Wild May Come to Kravat!"
        case .sculptureStolen: "Priceless collector's item stolen from home of Geurge Locas!"
        case .sculptureTracked: "Space Corps follows \(ship) with alleged stolen sculpture to \(system)."
        case .princess: "Member of Royal Family kidnapped!"
        case .princessCentauri: "Aggressive Ship Seen in Orbit Around Centauri"
        case .princessInthara: "Dangerous Scorpion Damages Several Other Ships Near Inthara"
        case .princessQonos: "Kidnappers Holding Out at Qonos"
        case .princessRescued: "Scorpion Defeated! Kidnapped Member of Galvon Royal Family Freed!"
        case .princessReturned: "Beloved Royal Returns Home!"
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// `NewsPressureInternal[p]` (index 0 is empty in C#; `.none` never makes a headline).
    static func internalPressure(_ p: SystemPressure) -> LocalizedStringResource? {
        switch p {
        case .none: nil
        case .war: "War News: Offensives Continue!"
        case .plague: "Plague Spreads! Outlook Grim."
        case .drought: "No Rain in Sight!"
        case .boredom: "Editors: Won't Someone Entertain Us?"
        case .cold: "Cold Snap Continues!"
        case .cropFailure: "Serious Crop Failure! Must We Ration?"
        case .employment: "Jobless Rate at All-Time Low!"
        }
    }

    /// `NewsPoliceRecordPsychopath`: ^1 = commander, ^2 = current system.
    static func villain(commander: String, system: String) -> [LocalizedStringResource] {
        ["Police Warning: \(commander) Will Dock At \(system)!", "Notorious Criminal \(commander) Sighted in \(system)!",
         "Locals Rally to Deny Spaceport Access to \(commander)!", "Terror Strikes Locals on Arrival of \(commander)!"]
    }

    /// `NewsPoliceRecordHero`: ^1 = commander.
    static func hero(commander: String) -> [LocalizedStringResource] {
        ["Locals Welcome Visiting Hero \(commander)!", "Famed Hero \(commander) to Visit System!",
         "Large Turnout At Spaceport to Welcome \(commander)!"]
    }

    /// `NewsPressureExternal[template]` with ^1 = the pressure word and ^2 = the system. Template 3 follows the
    /// content's wording (NEWS-047: Palm "Sources say", C# "Sources report").
    static func externalPressure(template: Int, word: String, system: String, wording: NewsWording) -> LocalizedStringResource {
        switch template {
        case 0: return "Reports of \(word) in the \(system) System."
        case 1: return "News of \(word) in the \(system) System."
        case 2: return "New Rumors of \(word) in the \(system) System."
        case 3:
            switch wording {
            case .csharp: return "Sources report \(word) in the \(system) System."
            case .palm: return "Sources say \(word) in the \(system) System."
            }
        case 4: return "Notice: \(word) in the \(system) System."
        default: return "Evidence Suggests \(word) in the \(system) System."
        }
    }

    /// `NewsPressureExternalPressures[p]`.
    static func externalPressureWord(_ p: SystemPressure) -> LocalizedStringResource? {
        switch p {
        case .none: nil
        case .war: "Strife and War"
        case .plague: "Plague Outbreaks"
        case .drought: "Severe Drought"
        case .boredom: "Terrible Boredom"
        case .cold: "Cold Weather"
        case .cropFailure: "Crop Failures"
        case .employment: "Labor Shortages"
        }
    }

    /// `NewsHeadlines[government]` (4 canned stories per government).
    static func canned(_ g: PoliticalSystemType) -> [LocalizedStringResource] {
        switch g {
        case .anarchy:
            ["Riots, Looting Mar Factional Negotiations.", "Communities Seek Consensus.", "Successful Bakunin Day Rally!",
             "Major Faction Conflict Expected for the Weekend!"]
        case .capitalist:
            ["Editorial: Taxes Too High!", "Market Indices Read Record Levels!", "Corporate Profits Up!",
             "Restrictions on Corporate Freedom Abolished by Courts!"]
        case .communist:
            ["Party Reports Productivity Increase.", "Counter-Revolutionary Bureaucrats Purged from Party!",
             "Party: Bold New Future Predicted!", "Politburo Approves New 5-Year Plan!"]
        case .confederacy:
            ["States Dispute Natural Resource Rights!", "States Denied Federal Funds over Local Laws!",
             "Southern States Resist Federal Taxation for Capital Projects!", "States Request Federal Intervention in Citrus Conflict!"]
        case .corporate:
            ["Robot Shortages Predicted for Q4.", "Profitable Quarter Predicted.", "CEO: Corporate Rebranding Progressing.",
             "Advertising Budgets to Increase."]
        case .cybernetic:
            ["Olympics: Software Beats Wetware in All Events!", "New Network Protocols To Be Deployed.",
             "Storage Banks to be Upgraded!", "System Backup Rescheduled."]
        case .democracy:
            ["Local Elections on Schedule!", "Polls: Voter Satisfaction High!", "Campaign Spending Aids Economy!",
             "Police, Politicians Vow Improvements."]
        case .dictatorship:
            ["New Palace Planned; Taxes Increase.", "Future Presents More Opportunities for Sacrifice!",
             "Insurrection Crushed: Rebels Executed!", "Police Powers to Increase!"]
        case .fascist:
            ["Drug Smugglers Sentenced to Death!", "Aliens Required to Carry Visible Identification at All Times!",
             "Foreign Sabotage Suspected.", "Stricter Immigration Laws Installed."]
        case .feudal:
            ["Farmers Drafted to Defend Lord's Castle!", "Report: Kingdoms Near Flashpoint!", "Baron Ignores Ultimatum!",
             "War of Succession Threatens!"]
        case .military:
            ["Court-Martials Up 2% This Year.", "Editorial: Why Wait to Invade?", "HQ: Invasion Plans Reviewed.",
             "Weapons Research Increases Kill-Ratio!"]
        case .monarchy:
            ["King to Attend Celebrations.", "Queen's Birthday Celebration Ends in Riots!", "King Commissions New Artworks.",
             "Prince Exiled for Palace Plot!"]
        case .pacifist:
            ["Dialog Averts Eastern Conflict!", "Universal Peace: Is it Possible?", "Editorial: Life in Harmony.",
             "Polls: Happiness Quotient High!"]
        case .socialist:
            ["Government Promises Increased Welfare Benefits!", "State Denies Food Rationing Required to Prevent Famine.",
             "'Welfare Actually Boosts Economy,' Minister Says.", "Hoarder Lynched by Angry Mob!"]
        case .satori:
            ["Millions at Peace.", "Sun Rises.", "Countless Hearts Awaken.", "Serenity Reigns."]
        case .technocracy:
            ["New Processor Hits 10 ZettaHerz!", "Nanobot Output Exceeds Expectation.", "Last Human Judge Retires.",
             "Software Bug Causes Mass Confusion."]
        case .theocracy:
            ["High Priest to Hold Special Services.", "Temple Restoration Fund at 81%.", "Sacred Texts on Public Display.",
             "Dozen Blasphemers Excommunicated!"]
        }
    }

    // MARK: Palm page limit (NEWS-046)

    /// The app's measure function for Palm's page rule: the headline fits one 148 px line of Palm `stdFont`.
    static func palmMetrics(_ h: Headline, context: Context) -> HeadlineMetrics {
        let text = headline(h, context: context)
        return HeadlineMetrics(fitsOneLine: PalmStdFont.width(of: text) <= 148, length: text.count)
    }

    /// The headlines the sheet shows: Palm drops what does not fit its page (NEWS-046), others show all.
    static func shownHeadlines(state: GameState) -> [Headline] {
        let context = Context(state: state)
        return state.newspaperHeadlines { palmMetrics($0, context: context) }
    }

    /// The headlines of `paper` the sheet shows (the page rule of NEWS-046 when the ruleset has it).
    static func shownHeadlines(_ paper: Newspaper, state: GameState) -> [Headline] {
        guard state.ruleset.flags.travel.newsPageLimit else { return paper.headlines }
        let context = Context(state: state)
        return paper.applyingPageLimit { palmMetrics($0, context: context) }
    }
}

/// UI-ENC-071: what the styled newspaper sheet shows, from the `Newspaper` value it was given.
struct NewspaperSheetModel: Equatable, Sendable {
    var masthead: String
    /// "Day N · <system> · <price> cr."
    var dateLine: String
    var headlines: [String]

    /// Two balanced columns from 4 headlines on, else one.
    var columns: [[String]] {
        guard headlines.count >= 4 else { return [headlines] }
        let half = (headlines.count + 1) / 2
        return [Array(headlines.prefix(half)), Array(headlines.dropFirst(half))]
    }

    static func make(paper: Newspaper, state: GameState) -> NewspaperSheetModel {
        let context = NewspaperText.Context(state: state)
        let system = Names.system(paper.system, in: state)
        return NewspaperSheetModel(masthead: NewspaperText.masthead(paper, state: state),
                                   dateLine: String(localized: "Day \(state.commander.days) · \(system) · \(state.newspaperCost) cr."),
                                   headlines: NewspaperText.shownHeadlines(paper, state: state).map { NewspaperText.headline($0, context: context) })
    }
}

/// Approximate glyph advance widths of Palm OS `stdFont` (pixels), for NEWS-046's one-line test (docs/QA-REPORT.md,
/// Accepted assumptions).
enum PalmStdFont {
    static func width(of text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + advance($1) }
    }

    static func advance(_ c: Unicode.Scalar) -> Int {
        switch c {
        case " ", "'", "!", ".", ",", ":", ";", "|", "i", "l": 2
        case "j", "I", "(", ")", "[", "]", "f", "t", "r", "1": 3
        case "-", "?", "\"", "c", "k", "s", "z", "J", "x", "y", "v": 4
        case "m", "M", "W", "w": 6
        case "N", "Q", "O", "G", "C", "D", "H", "U", "V", "X", "Y", "A", "&", "%": 6
        default: 5
        }
    }
}
