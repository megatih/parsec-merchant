// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// Crew section (⌘5): crew quarters as seats, mercenaries for hire and the effective-skills panel (UI-SHELL-079…081).
struct CrewSectionView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        ScrollView {
            if let engine = session.engine {
                let model = CrewModel.make(engine: engine)
                VStack(alignment: .leading, spacing: 24) {
                    quarters(model)
                    forHire(model)
                    EffectiveSkillsPanel(model: model)
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.SectionRoot.root(.crew))
    }

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)]

    private func quarters(_ model: CrewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Crew Quarters").font(.title3.bold())
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(model.seats) { seat in
                    SeatCard(seat: seat, standing: model.standing) { id in session.send(.fire(crewID: id)) }
                }
            }
        }
    }

    private func forHire(_ model: CrewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("For Hire").font(.title3.bold())
            if model.forHire.isEmpty {
                Text("No one for hire").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(model.forHire) { card in
                        HireCardView(card: card) { session.send(.hire(crewID: card.crewID)) }
                    }
                }
            }
        }
    }
}

/// One seat of the crew quarters.
private struct SeatCard: View {
    let seat: CrewModel.Seat
    let standing: CrewModel.Standing
    let fire: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch seat.occupant {
            case let .commander(name, skills):
                header(name, badge: "Commander", crewID: CrewID.commander)
                SkillBars(skills: skills)
                standingLines
            case let .mercenary(id, name, skills, wage):
                header(name, badge: nil, crewID: id)
                SkillBars(skills: skills)
                Text("\(wage.formatted()) cr. daily").monospacedDigit().foregroundStyle(.secondary)
            case let .passenger(id, name):
                header(name, badge: "Passenger", crewID: id)
            case .vacant:
                Text("Vacant").font(.headline).foregroundStyle(.secondary)
            }
            if seat.canBeFired, let id = seat.crewID {
                Button("Fire", role: .destructive) { fire(id) }
                    .disabled(seat.fireBlocker != nil)
                    .help(seat.fireBlocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Dismiss this crew member."))
                    .accessibilityIdentifier(AXID.Crew.fire(id))
                if let blocker = seat.fireBlocker {
                    Text(ReasonText.text(for: blocker)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Crew.seat(seat.index))
    }

    private func header(_ name: String, badge: LocalizedStringResource?, crewID: Int) -> some View {
        HStack {
            CrewAvatarView(crewID: crewID)
            Text(verbatim: name).font(.headline)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.2), in: .capsule)
            }
        }
    }

    private var standingLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Police record: \(String(localized: Names.policeRecord(standing.policeRecord))) (\(standing.policeScore))")
            Text("Reputation: \(String(localized: Names.reputation(standing.reputation)))")
            Text("Kills: \(standing.kills)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A mercenary for hire.
private struct HireCardView: View {
    let card: CrewModel.HireCard
    let hire: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CrewAvatarView(crewID: card.crewID)
                Text(verbatim: card.name).font(.headline)
            }
            SkillBars(skills: card.skills)
            HStack {
                Text("\(card.dailyWage.formatted()) cr. daily").monospacedDigit()
                Spacer()
                Button("Hire", action: hire)
                    .disabled(card.blocker != nil)
                    .help(card.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Hire this mercenary."))
                    .accessibilityIdentifier(AXID.Crew.hire(card.crewID))
            }
            if let blocker = card.blocker {
                Text(ReasonText.text(for: blocker)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }
}

/// Pilot, Fighter, Trader and Engineer as bars with their numbers.
private struct SkillBars: View {
    let skills: [Int]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            ForEach(SkillType.allCases, id: \.self) { skill in
                let value = skills.indices.contains(skill.rawValue) ? skills[skill.rawValue] : 0
                GridRow {
                    Text(Names.skill(skill)).font(.caption)
                    ProgressView(value: Double(min(max(value, 0), 10)), total: 10)
                        .frame(width: 90)
                    Text(verbatim: value.formatted()).font(.caption).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Effective skills and their parts (UI-SHELL-081).
private struct EffectiveSkillsPanel: View {
    let model: CrewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Effective Skills").font(.title3.bold())
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Skill").gridColumnAlignment(.leading)
                    Text("Best crew")
                    Text("Gadgets")
                    Text("Haggling")
                    Text("Difficulty")
                    Text("Effective")
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                Divider()
                ForEach(model.skills) { row in
                    GridRow {
                        Text(Names.skill(row.skill))
                        Text(verbatim: row.crewMaximum.formatted())
                        Text(verbatim: signed(row.gadgetBonus))
                        Text(verbatim: row.skill == .trader ? signed(row.hagglingBonus) : "–")
                        Text(verbatim: signed(row.difficultyAdjustment))
                        Text(verbatim: row.effective.formatted()).bold()
                    }
                    .monospacedDigit()
                }
            }
            HStack(spacing: 24) {
                Text("Free quarters: \(model.freeQuarters)")
                Text("Daily wages: \(model.dailyWages.formatted()) cr.").monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Crew.effectiveSkills)
        .help(Text("Each skill is the best value in your crew, plus gadget and haggling bonuses, adjusted for difficulty."))
    }

    private func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : v.formatted() }
}
