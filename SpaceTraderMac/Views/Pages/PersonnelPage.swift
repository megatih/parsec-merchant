// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Personnel (⌘4, PRD §4.7): the crew quarters, the mercenaries for hire here and the effective skills.
struct PersonnelPage: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale

    var body: some View {
        GamePage(section: .crew) {
            if let engine = session.engine {
                let model = CrewModel.make(engine: engine)
                PMFitScroll {
                    VStack(alignment: .leading, spacing: PMSpace.s * scale) {
                        HStack(alignment: .top, spacing: PMSpace.s * scale) {
                            quarters(model)
                            forHire(model)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        EffectiveSkillsPanel(model: model)
                    }
                }
            }
        }
    }

    private func quarters(_ model: CrewModel) -> some View {
        PMPanel("Crew Quarters", identifier: "crew.quarters") {
            ForEach(model.seats) { seat in
                CrewSeatCard(seat: seat) { id in session.send(.fire(crewID: id)) }
            }
        }
    }

    private func forHire(_ model: CrewModel) -> some View {
        PMPanel("For Hire", identifier: "crew.forHire") {
            if model.forHire.isEmpty {
                PMEmptyState(symbol: "person.slash", message: "No mercenary is looking for work in this system.", identifier: "crew.forHire.empty")
                    .frame(minHeight: 120 * scale)
            }
            ForEach(model.forHire) { card in
                CrewHireCard(card: card) { session.send(.hire(crewID: card.crewID)) }
            }
        }
    }
}

/// The frame of one person: a 96 pt portrait, then the name, the role and the details.
private struct CrewCardFrame<Details: View, Action: View>: View {
    let crewID: Int?
    let name: String
    let role: LocalizedStringResource?
    @ViewBuilder var details: () -> Details
    @ViewBuilder var action: () -> Action
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: PMSpace.m * scale) {
            Group {
                if let crewID {
                    CrewAvatarView(crewID: crewID, side: 96 * scale)
                } else {
                    RoundedRectangle(cornerRadius: PMRadius.control * scale).fill(PMColor.panelInset)
                        .overlay { Image(systemName: "bed.double").foregroundStyle(PMColor.textDisabled).accessibilityHidden(true) }
                        .frame(width: 96 * scale, height: 96 * scale)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PMRadius.control * scale))
            VStack(alignment: .leading, spacing: PMSpace.xs * scale) {
                HStack(spacing: PMSpace.s * scale) {
                    Text(verbatim: name).pmFont(.valueLarge).foregroundStyle(PMColor.textPrimary)
                    if let role { PMBadge(text: role, symbol: "person.fill", color: PMColor.info, identifier: "crew.role.\(crewID ?? -1)") }
                }
                details()
            }
            Spacer(minLength: PMSpace.s * scale)
            action()
        }
        .padding(PMSpace.s * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PMColor.panelRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: PMRadius.control * scale))
    }
}

/// One seat of the crew quarters (UI-SHELL-079).
private struct CrewSeatCard: View {
    let seat: CrewModel.Seat
    let fire: (Int) -> Void

    var body: some View {
        Group {
            switch seat.occupant {
            case let .commander(name, skills):
                CrewCardFrame(crewID: CrewID.commander, name: name, role: "Commander") { PMSkillBars(skills: skills) } action: { EmptyView() }
            case let .mercenary(id, name, skills, wage):
                CrewCardFrame(crewID: id, name: name, role: nil) {
                    PMSkillBars(skills: skills)
                    Text("\(wage.formatted()) cr. per day").pmFont(.caption).foregroundStyle(PMColor.textSecondary)
                } action: {
                    fireButton(id)
                }
            case let .passenger(id, name):
                CrewCardFrame(crewID: id, name: name, role: "Passenger") {
                    Text("Travels with you until the quest ends.").pmFont(.caption).foregroundStyle(PMColor.textSecondary)
                } action: {
                    fireButton(id)
                }
            case .vacant:
                CrewCardFrame(crewID: nil, name: String(localized: "Vacant"), role: nil) {
                    Text("An empty crew quarter.").pmFont(.caption).foregroundStyle(PMColor.textSecondary)
                } action: {
                    EmptyView()
                }
            }
        }
        .contextMenu {
            // UI-PTR-005: the card's visible action.
            if seat.canBeFired, let id = seat.crewID {
                Button("Fire", role: .destructive) { fire(id) }.disabled(seat.fireBlocker != nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Crew.seat(seat.index))
    }

    private func fireButton(_ id: Int) -> some View {
        PMButton(title: "Fire", kind: .danger, help: "Dismiss this crew member", disabledReason: seat.fireBlocker?.reason, identifier: AXID.Crew.fire(id)) {
            fire(id)
        }
        .fixedSize()
    }
}

/// A mercenary for hire (UI-SHELL-080).
private struct CrewHireCard: View {
    let card: CrewModel.HireCard
    let hire: () -> Void

    var body: some View {
        CrewCardFrame(crewID: card.crewID, name: card.name, role: nil) {
            PMSkillBars(skills: card.skills)
            Text("\(card.dailyWage.formatted()) cr. per day").pmFont(.caption).foregroundStyle(PMColor.textSecondary)
            if let blocker = card.blocker { PMNote(text: ReasonText.text(for: blocker)) }
        } action: {
            PMButton(title: "Hire", kind: .primary, help: "Hire this mercenary", disabledReason: card.blocker?.reason,
                     identifier: AXID.Crew.hire(card.crewID), action: hire)
                .fixedSize()
        }
        .contextMenu {
            Button("Hire", action: hire).disabled(card.blocker != nil)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Effective skills and their parts (UI-SHELL-081).
private struct EffectiveSkillsPanel: View {
    let model: CrewModel
    @Environment(\.pmScale) private var scale

    var body: some View {
        PMPanel("Effective Skills", identifier: AXID.Crew.effectiveSkills) {
            Grid(alignment: .trailing, horizontalSpacing: PMSpace.l * scale, verticalSpacing: PMSpace.xs * scale) {
                GridRow {
                    Text("Skill").gridColumnAlignment(.leading)
                    Text("Best crew")
                    Text("Gadgets")
                    Text("Haggling")
                    Text("Difficulty")
                    Text("Effective")
                }
                .pmFont(.caption)
                .foregroundStyle(PMColor.textSecondary)
                .fixedSize()
                ForEach(model.skills) { row in
                    GridRow {
                        Text(Names.skill(row.skill)).pmFont(.body)
                        Text(verbatim: row.crewMaximum.formatted())
                        Text(verbatim: signed(row.gadgetBonus))
                        if row.skill == .trader {
                            Text(verbatim: signed(row.hagglingBonus))
                        } else {
                            // A11Y-029: a symbol, not a dash glyph too thin to measure.
                            Image(systemName: "minus").accessibilityLabel(Text("Not applicable"))
                        }
                        Text(verbatim: signed(row.difficultyAdjustment))
                        Text(verbatim: row.effective.formatted()).fontWeight(.bold)
                    }
                    .pmFont(.valueLarge)  // A11Y-029: single digits need the larger size to measure as readable
                    .foregroundStyle(PMColor.textPrimary)
                }
            }
            HStack(spacing: PMSpace.xl * scale) {
                Text("Free quarters: \(model.freeQuarters)")
                Text("Daily wages: \(model.dailyWages.formatted()) cr.").monospacedDigit()
            }
            .pmFont(.body)
            .foregroundStyle(PMColor.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .help(Text("Best value in your crew plus gadget bonuses, adjusted for difficulty"))
    }

    private func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : v.formatted() }
}
