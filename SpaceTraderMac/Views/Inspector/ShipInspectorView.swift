// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// The ship-status inspector (UI-SHELL-046…053): replaces Commander Status, Current Ship and Special Cargo.
struct ShipInspectorView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        if let state = session.state {
            let m = InspectorModel.make(state: state)
            Form {
                header(m, state: state)
                finances(m)
                skills(m)
                notoriety(m)
                cargo(m)
                equipment(m)
                crew(m, state: state)
                quests(state)
                costs(m)
            }
            .formStyle(.grouped)
            .labeledContentStyle(ReadableLabeledContentStyle())  // A11Y-029: values at full contrast
            .scrollEdgeEffectHidden(true, for: .bottom)  // A11Y-029: no fade over the last rows
            .accessibilityIdentifier(AXID.Inspector.root)
        }
    }

    // MARK: Sections

    private func header(_ m: InspectorModel, state: GameState) -> some View {
        SwiftUI.Section {
            // D7: the ship is a full-width hero at the top of the inspector.
            ShipPortrait(input: ArtAdapters.shipInput(state.commander.ship, ruleset: state.ruleset, facing: .right))
                .frame(maxWidth: .infinity)
                .frame(height: ShipPanelSize.inspectorHero)
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text(verbatim: m.commanderName).scaledFont(.headline)
                    Text("\(String(localized: Names.difficulty(m.difficulty))) · Day \(m.days)")
                        .foregroundStyle(.readableSecondary)
                    if let name = m.shipName {
                        Text("\(String(localized: Names.ship(m.shipType))) “\(name)”")
                    } else {
                        Text(Names.ship(m.shipType))
                    }
                }
            }
            LabeledContent("Hull") {
                Gauge(value: Double(m.hullPercent), in: 0...100) { EmptyView() } currentValueLabel: { Text("\(m.hullPercent)%") }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .frame(width: 120)
            }
            .help(Text("Hull strength as a percentage of the maximum."))
            // A11Y-004: one progress element "Hull", "78 percent" (a gauge in a LabeledContent has no role).
            .accessibilityRepresentation {
                ProgressView(value: Double(m.hullPercent), total: 100) { Text("Hull") }
                    .accessibilityValue(Text(verbatim: AccessibilityText.percent(m.hullPercent)))
            }
            .accessibilityIdentifier(AXID.Inspector.hull)
            LabeledContent("Shields") {
                if let s = m.shields {
                    Text("\(s.charge)/\(s.power)").monospacedDigit()
                } else {
                    Text("No shields")
                }
            }
            .help(Text("Total shield charge over total shield power."))
            .accessibilityIdentifier(AXID.Inspector.shields)
        }
    }

    private func finances(_ m: InspectorModel) -> some View {
        SwiftUI.Section("Finances") {
            LabeledContent("Cash") { Text("\(m.cash.formatted()) cr.").monospacedDigit() }
                .help(Text("Credits on hand."))
                .accessibilityIdentifier(AXID.Inspector.cash)
            LabeledContent("Debt") { Text("\(m.debt.formatted()) cr.").monospacedDigit() }
                .help(Text("What you owe the bank. Each warp adds 10% interest."))
                .accessibilityIdentifier(AXID.Inspector.debt)
            LabeledContent("Net worth") { Text("\(m.worth.formatted()) cr.").monospacedDigit() }
                .help(Text("Your ship, cargo and cash, minus your debt."))
                .accessibilityIdentifier(AXID.Inspector.worth)
            // STAT-020: career totals live in Logbook › Statistics.
            Button("Show Statistics") { session.showLogbook(tab: .statistics) }
                .disabled(!LogbookLinks.showStatisticsEnabled(sectionContext: session.sectionContext,
                                                              inputLocked: session.isInputLocked))
                .accessibilityIdentifier(AXID.LogbookLinks.inspectorShowStatistics)
        }
    }

    private func skills(_ m: InspectorModel) -> some View {
        SwiftUI.Section("Skills") {
            ForEach(m.skills, id: \.skill) { row in
                LabeledContent {
                    Text(verbatim: "\(row.base) (\(row.effective))").monospacedDigit()
                } label: {
                    Text(Names.skill(row.skill))
                }
                .help(Text("Your own value, and in brackets the ship's effective value with crew and gadgets."))
                .accessibilityIdentifier(AXID.Inspector.skill(row.skill))
            }
        }
    }

    private func notoriety(_ m: InspectorModel) -> some View {
        SwiftUI.Section("Notoriety") {
            LabeledContent("Police record") {
                Text("\(String(localized: Names.policeRecord(m.policeRecord))) (\(m.policeScore))")
            }
            .help(Text("How the police see you."))
            LabeledContent("Reputation") { Text(Names.reputation(m.reputation)) }
                .help(Text("How dangerous other pilots think you are."))
            LabeledContent("Kills") { Text(verbatim: m.kills.formatted()).monospacedDigit() }
                .help(Text("Pirates, police and traders destroyed."))
            switch m.notoriety {
            case let .bounty(n):
                LabeledContent("Bounty offered") { Text("\(n.formatted()) cr.").monospacedDigit() }
            case let .angryKingpins(n):
                LabeledContent("Angry kingpins") { Text(verbatim: n.formatted()).monospacedDigit() }
            case .none:
                EmptyView()
            }
        }
    }

    private func cargo(_ m: InspectorModel) -> some View {
        SwiftUI.Section("Cargo") {
            ForEach(m.cargo, id: \.item) { c in
                LabeledContent {
                    Text("\(c.units) at \(c.averageCost.formatted()) cr.").monospacedDigit()
                } label: {
                    Text(Names.item(c.item))
                }
            }
            if m.specialCargo.isEmpty {
                Text("No special items.").foregroundStyle(.readableSecondary)
            } else {
                ForEach(m.specialCargo.indices, id: \.self) { i in
                    Text(InspectorText.specialCargo(m.specialCargo[i]))
                }
            }
        }
    }

    private func equipment(_ m: InspectorModel) -> some View {
        SwiftUI.Section("Equipment") {
            ForEach(m.weapons, id: \.type) { w in
                Text("\(w.count) × \(String(localized: Names.weapon(w.type)))")
            }
            ForEach(m.shieldsInstalled, id: \.type) { s in
                Text("\(s.count) × \(String(localized: Names.shield(s.type))) (charge \(s.charge))")
            }
            ForEach(m.gadgets, id: \.type) { g in
                Text("\(g.count) × \(String(localized: Names.gadget(g.type)))")
            }
            if m.escapePod { Text("Escape pod") }
            if m.hardenedHull { Text("Hardened hull") }
            if m.freeWeaponSlots > 0 { Text("\(m.freeWeaponSlots) free weapon slots").foregroundStyle(.readableSecondary) }
            if m.freeShieldSlots > 0 { Text("\(m.freeShieldSlots) free shield slots").foregroundStyle(.readableSecondary) }
            if m.freeGadgetSlots > 0 { Text("\(m.freeGadgetSlots) free gadget slots").foregroundStyle(.readableSecondary) }
        }
    }

    private func crew(_ m: InspectorModel, state: GameState) -> some View {
        SwiftUI.Section("Crew & Passengers") {
            Text(verbatim: m.commanderName)
            ForEach(m.crew, id: \.crewID) { row in
                LabeledContent {
                    if row.isPassenger {
                        Text("passenger").foregroundStyle(.readableSecondary)
                    } else {
                        Text("\(row.dailyWage.formatted()) cr./day").monospacedDigit()
                    }
                } label: {
                    Text(verbatim: Names.crew(row.crewID, in: state))
                }
            }
            Text("\(m.freeQuarters) free quarters").foregroundStyle(.readableSecondary)
        }
    }

    /// Active quests: the titles from `GameState.questLog` (UI-SHELL-053/121); each row selects the Quests section.
    private func quests(_ state: GameState) -> some View {
        SwiftUI.Section("Active Quests") {
            let log = state.questLog
            if log.isEmpty {
                Text(QuestText.none).foregroundStyle(.readableSecondary)
            }
            ForEach(Array(log.enumerated()), id: \.offset) { i, entry in
                Button { session.selectedSection = .quests } label: {
                    Text(QuestText.title(for: entry.kind, state: state)).multilineTextAlignment(.leading)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier(AXID.Inspector.quest(i))
            }
        }
    }

    private func costs(_ m: InspectorModel) -> some View {
        SwiftUI.Section("Daily Costs") {
            LabeledContent("Mercenaries") { Text("\(m.dailyCosts.mercenaries.formatted()) cr.").monospacedDigit() }
            LabeledContent("Insurance") { Text("\(m.dailyCosts.insurance.formatted()) cr.").monospacedDigit() }
            LabeledContent("Interest") { Text("\(m.dailyCosts.interest.formatted()) cr.").monospacedDigit() }
            LabeledContent("Wormhole tax") { Text("\(m.dailyCosts.wormholeTax.formatted()) cr.").monospacedDigit() }
            LabeledContent("Total") { Text("\(m.dailyCosts.total.formatted()) cr.").monospacedDigit().bold() }
        }
        .help(Text("What the next warp to your target will cost."))
    }
}

/// Inspector wording (Strings.cs:223-232 for special cargo).
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
