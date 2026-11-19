// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// Commander Status (⌘6, PRD §4.9): the commander, the ship, the finances and the cargo. It replaces the 1.x inspector
/// and shows every field that showed (UI-PG-040).
struct StatusPage: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale

    var body: some View {
        GamePage(section: .status) {
            if let state = session.state {
                let m = InspectorModel.make(state: state)
                PMFitScroll {
                    HStack(alignment: .top, spacing: PMSpace.s * scale) {
                        VStack(spacing: PMSpace.s * scale) {
                            commander(m, state: state)
                            finances(m)
                        }
                        VStack(spacing: PMSpace.s * scale) {
                            ship(m, state: state)
                            cargo(m)
                        }
                        VStack(spacing: PMSpace.s * scale) {
                            crew(m, state: state)
                            quests(state)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AXID.Inspector.root)
            }
        }
    }

    // MARK: Commander

    private func commander(_ m: InspectorModel, state: GameState) -> some View {
        PMPanel("Commander", identifier: "status.commander") {
            HStack(alignment: .top, spacing: PMSpace.m * scale) {
                CrewAvatarView(crewID: CrewID.commander, side: 128 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: PMRadius.control * scale))
                VStack(alignment: .leading, spacing: PMSpace.xs * scale) {
                    Text(verbatim: m.commanderName).pmFont(.title).foregroundStyle(PMColor.textPrimary)
                    Text("\(String(localized: Names.difficulty(m.difficulty))) · Day \(m.days)").pmFont(.body).foregroundStyle(PMColor.textSecondary)
                    ForEach(m.skills, id: \.skill) { row in
                        PMInfoRow(label: Names.skill(row.skill), identifier: AXID.Inspector.skill(row.skill),
                                  help: "Your own value, and in brackets the ship's effective value with crew and gadgets.") {
                            Text(verbatim: "\(row.base) (\(row.effective))")
                        }
                    }
                }
            }
            PMDivider()
            PMInfoRow(label: "Police record", help: "How the police see you.") {
                Text("\(String(localized: Names.policeRecord(m.policeRecord))) (\(m.policeScore))")
            }
            PMInfoRow(label: "Reputation", help: "How dangerous other pilots think you are.") { Text(Names.reputation(m.reputation)) }
            PMInfoRow("Kills", value: m.kills.formatted(), help: "Pirates, police and traders destroyed.")
            switch m.notoriety {
            case .none: EmptyView()
            case let .bounty(n): PMInfoRow("Bounty offered", credits: n)
            case let .angryKingpins(n): PMInfoRow("Angry kingpins", value: n.formatted())
            }
            PMDivider()
            HStack(spacing: PMSpace.s * scale) {
                PMInfoRow("Galaxy code", value: GalaxyCodeCard.code(state: state), identifier: AXID.Inspector.galaxyCode,
                          help: "A friend who enters this code plays the same galaxy.")
                PMButton(title: "Copy", systemImage: "doc.on.doc", help: "Copy the galaxy code so a friend can play the same galaxy",
                         identifier: AXID.Inspector.galaxyCodeCopy) {
                    GalaxyCodeCard.copy(GalaxyCodeCard.code(state: state))
                }
                .fixedSize()
            }
        }
    }

    // MARK: Ship

    private func ship(_ m: InspectorModel, state: GameState) -> some View {
        PMPanel("Ship", identifier: "status.ship") {
            ShipPortrait(input: ArtAdapters.playerShipInput(state))
                .frame(maxWidth: .infinity)
                .frame(height: 150 * scale)
            if let name = m.shipName {
                Text("\(String(localized: Names.ship(m.shipType))) “\(name)”").pmFont(.valueLarge).foregroundStyle(PMColor.textPrimary)
            } else {
                Text(Names.ship(m.shipType)).pmFont(.valueLarge).foregroundStyle(PMColor.textPrimary)
            }
            PMGauge(label: "Hull", fraction: Double(m.hullPercent) / 100, valueText: StatusBarText.percent(m.hullPercent),
                    tone: m.hullPercent < 25 ? .loss : (m.hullPercent < 50 ? .caution : .neutral), identifier: AXID.Inspector.hull)
                .help(Text("Hull strength as a percentage of the maximum."))
            if let s = m.shields {
                PMGauge(label: "Shields", fraction: s.power > 0 ? Double(s.charge) / Double(s.power) : 0, valueText: "\(s.charge)/\(s.power)",
                        identifier: AXID.Inspector.shields)
                    .help(Text("Total shield charge over total shield power."))
            } else {
                PMInfoRow("Shields", value: String(localized: "No shields"), identifier: AXID.Inspector.shields,
                          help: "Total shield charge over total shield power.")
            }
            PMDivider()
            ForEach(m.weapons, id: \.type) { w in line("\(w.count) × \(String(localized: Names.weapon(w.type)))") }
            ForEach(m.shieldsInstalled, id: \.type) { s in line("\(s.count) × \(String(localized: Names.shield(s.type))) (charge \(s.charge))") }
            ForEach(m.gadgets, id: \.type) { g in line("\(g.count) × \(String(localized: Names.gadget(g.type)))") }
            if m.escapePod { line("Escape pod") }
            if m.hardenedHull { line("Hardened hull") }
            if m.freeWeaponSlots > 0 { line("\(m.freeWeaponSlots) free weapon slots", dim: true) }
            if m.freeShieldSlots > 0 { line("\(m.freeShieldSlots) free shield slots", dim: true) }
            if m.freeGadgetSlots > 0 { line("\(m.freeGadgetSlots) free gadget slots", dim: true) }
        }
    }

    private func line(_ text: LocalizedStringResource, dim: Bool = false) -> some View {
        Text(text).pmFont(.body).foregroundStyle(dim ? PMColor.textSecondary : PMColor.textPrimary)
    }

    // MARK: Finances

    private func finances(_ m: InspectorModel) -> some View {
        PMPanel("Finances", identifier: "status.finances") {
            PMInfoRow("Cash", credits: m.cash, identifier: AXID.Inspector.cash, help: "Credits on hand.")
            PMInfoRow("Debt", credits: m.debt, identifier: AXID.Inspector.debt, help: "What you owe the bank. Each warp adds 10% interest.")
            PMInfoRow("Net worth", credits: m.worth, identifier: AXID.Inspector.worth, help: "Your ship, cargo and cash, minus your debt.")
            PMDivider()
            PMInfoRow("Mercenaries", credits: m.dailyCosts.mercenaries)
            PMInfoRow("Insurance", credits: m.dailyCosts.insurance)
            PMInfoRow("Interest", credits: m.dailyCosts.interest)
            PMInfoRow("Wormhole tax", credits: m.dailyCosts.wormholeTax)
            PMInfoRow("Total costs of the next warp", credits: m.dailyCosts.total, help: "What the next warp to your target will cost.")
            // STAT-020: career totals live in Logbook › Statistics.
            let enabled = LogbookLinks.showStatisticsEnabled(sectionContext: session.sectionContext, inputLocked: session.isInputLocked)
            PMButton(title: "Show Statistics", systemImage: "arrow.right", kind: .quiet, help: "Open the Logbook's statistics",
                     disabledReason: enabled ? nil : String(localized: ReasonText.text(for: .notAllowedInPhase)),
                     identifier: AXID.LogbookLinks.inspectorShowStatistics) {
                session.showLogbook(tab: .statistics)
            }
        }
    }

    // MARK: Cargo

    private func cargo(_ m: InspectorModel) -> some View {
        PMPanel("Cargo and Special Cargo", identifier: "status.cargo") {
            if m.cargo.isEmpty { line("The hold is empty.", dim: true) }
            ForEach(m.cargo, id: \.item) { c in
                PMInfoRow(label: Names.item(c.item)) { Text("\(c.units) at \(c.averageCost.formatted()) cr.") }
            }
            PMDivider()
            if m.specialCargo.isEmpty {
                line("No special items.", dim: true)
            } else {
                ForEach(m.specialCargo.indices, id: \.self) { i in
                    Text(InspectorText.specialCargo(m.specialCargo[i])).pmFont(.body).foregroundStyle(PMColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Crew and quests

    private func crew(_ m: InspectorModel, state: GameState) -> some View {
        PMPanel("Crew and Passengers", identifier: "status.crew") {
            Text(verbatim: m.commanderName).pmFont(.body).foregroundStyle(PMColor.textPrimary)
            ForEach(m.crew, id: \.crewID) { row in
                PMInfoRow(label: "\(Names.crew(row.crewID, in: state))") {
                    if row.isPassenger { Text("passenger") } else { Text("\(row.dailyWage.formatted()) cr./day") }
                }
            }
            line("\(m.freeQuarters) free quarters", dim: true)
        }
    }

    /// Active quests: the titles from `GameState.questLog` (UI-SHELL-053/121); each opens the Quests page.
    private func quests(_ state: GameState) -> some View {
        PMPanel("Active Quests", identifier: "status.quests") {
            let log = state.questLog
            if log.isEmpty { Text(QuestText.none).pmFont(.body).foregroundStyle(PMColor.textSecondary) }
            ForEach(Array(log.enumerated()), id: \.offset) { i, entry in
                Button { session.selectedSection = .quests } label: {
                    Text(QuestText.title(for: entry.kind, state: state)).multilineTextAlignment(.leading)
                }
                .buttonStyle(PMButtonStyle(kind: .quiet))
                .help(Text("Open the Quests page"))
                .accessibilityIdentifier(AXID.Inspector.quest(i))
            }
        }
    }
}

/// Special cargo wording (Strings.cs:223-232).
enum InspectorText {
    static func specialCargo(_ c: InspectorModel.SpecialCargo) -> LocalizedStringResource {
        switch c {
        case .tribblesInfestation: "An infestation of tribbles."
        case let .tribbles(n): "\(n) cute, furry tribbles."
        case .antidote: "10 bays of antidote."
        case .artifact: "An alien artifact."
        case .hagglingComputer: "A handheld haggling computer."
        case let .reactor(bays): "An unstable reactor taking up 5 bays, and \(bays) bays of enriched fuel."
        case .sculpture: "A stolen plastic sculpture of a man holding some kind of light sword."
        case .singularity: "A portable singularity."
        }
    }
}
