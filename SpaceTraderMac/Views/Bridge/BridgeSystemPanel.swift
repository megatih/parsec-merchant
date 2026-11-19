// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// Region A, System Information (PRD §4.2): the planet, the facts of the current system, fuel and hull with their
/// services, and the four notices. Every element is present in every state.
struct BridgeSystemPanel: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    let state: GameState

    /// The planet's side at the design size, and the width the rest of the panel needs beside it.
    static let planetSide: CGFloat = 112
    static let contentWidth: CGFloat = 636

    var body: some View {
        let model = SystemCardModel.make(state: state, system: state.commander.currentSystem)
        BridgePanel(identifier: BridgeID.system) {
            GeometryReader { geo in
                // The planet grows with the panel's height, but never takes the width the facts need.
                let side = max(Self.planetSide * scale, min(geo.size.height, geo.size.width - (Self.contentWidth + PMSpace.m) * scale))
                HStack(alignment: .top, spacing: PMSpace.m * scale) {
                    planet(model).frame(width: side, height: side)
                    VStack(alignment: .leading, spacing: 3 * scale) {
                        facts(model)
                        services
                        notices
                    }
                }
            }
        }
    }

    private func planet(_ model: SystemCardModel) -> some View {
        PlanetHero(input: ArtAdapters.planetInput(system: model.index, state: state, showPressure: true))
            .clipShape(RoundedRectangle(cornerRadius: PMRadius.control * scale))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(SystemText.planetLabel(model)))
            .accessibilityAddTraits(.isImage)
            .probed(BridgeID.System.planet)
    }

    // MARK: Facts

    private func facts(_ model: SystemCardModel) -> some View {
        HStack(alignment: .top, spacing: PMSpace.l * scale) {
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(verbatim: model.name).pmFont(.title).foregroundStyle(PMColor.textPrimary).fixedSize()
                    .frame(height: 16 * scale)
                    .accessibilityAddTraits(.isHeader)
                    .probed(BridgeID.System.name)
                BridgeFact(label: "Police", labelWidth: 46, identifier: BridgeID.System.police) { BridgeActivity(activity: model.police) }
                BridgeFact(label: "Pirates", labelWidth: 46, identifier: BridgeID.System.pirates) { BridgeActivity(activity: model.pirates) }
            }
            VStack(alignment: .leading, spacing: 3 * scale) {
                BridgeFact(label: "Size", labelWidth: 74, identifier: BridgeID.System.size) { Text(Names.size(model.size)) }
                BridgeFact(label: "Tech level", labelWidth: 74, identifier: BridgeID.System.tech) { Text(SystemText.techLevel(model.techLevel)) }
                BridgeFact(label: "Government", labelWidth: 74, identifier: BridgeID.System.government) {
                    Text(SystemText.government(model.government))
                }
            }
            VStack(alignment: .leading, spacing: 3 * scale) {
                BridgeFact(label: "Resources", labelWidth: 66, identifier: BridgeID.System.resources) { Text(SystemText.resource(model.resource)) }
                BridgeFact(label: "Status", labelWidth: 66, identifier: BridgeID.System.status) {
                    if let pressure = model.pressure, let tag = SystemText.pressure(pressure) {
                        Label { Text(tag) } icon: { Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true) }
                            .foregroundStyle(PMColor.caution)
                            .help(Text(SystemText.pressureDescription(pressure)))
                    } else {
                        Text("No pressure").help(Text(SystemText.pressureDescription(.none)))
                    }
                }
            }
        }
        .frame(height: 54 * scale, alignment: .top)
    }

    // MARK: Fuel and hull

    private var services: some View {
        let fuel = DockServiceModel.fuel(state: state), hull = DockServiceModel.hull(state: state)
        let fuelShort = StatusBarModel.make(state: state, feed: []).fuelShort
        return HStack(spacing: PMSpace.s * scale) {
            PMGauge(label: "Fuel", fraction: Double(fuel.current) / Double(max(1, fuel.maximum)),
                    valueText: String(localized: "\(fuel.current)/\(fuel.maximum) parsecs"), tone: fuelShort ? .caution : .neutral,
                    identifier: BridgeID.System.fuel)
            PMButton(title: fuel.isComplete ? "Fill Tank" : "Fill Tank \(fuel.fullCost.formatted()) cr.", help: "Buy as much fuel as you can afford",
                     disabledReason: reason(fuel.blocker), identifier: BridgeID.System.fillTank) {
                session.send(fuel.fullCommand)
            }
            .fixedSize()
            PMGauge(label: "Hull", fraction: Double(hull.current) / Double(max(1, hull.maximum)), valueText: StatusBarText.percent(hull.percent),
                    tone: hull.percent < 25 ? .loss : (hull.percent < 50 ? .caution : .neutral), identifier: BridgeID.System.hull)
            PMButton(title: hull.isComplete ? "Repair Hull" : "Repair Hull \(hull.fullCost.formatted()) cr.",
                     help: "Repair as much of the hull as you can afford", disabledReason: reason(hull.blocker), identifier: BridgeID.System.repairHull) {
                session.send(hull.fullCommand)
            }
            .fixedSize()
        }
        .frame(width: Self.contentWidth * scale, height: PointerTarget.minimum * scale)
    }

    private func reason(_ error: CommandError?) -> String? {
        if !session.isDocked { return String(localized: ReasonText.text(for: .notAllowedInPhase)) }
        return error.map { String(localized: ReasonText.text(for: $0)) }
    }

    // MARK: Notices

    private var notices: some View {
        let model = BridgeNoticesModel.make(state: state)
        return HStack(spacing: 6 * scale) {
            BridgeNotice(symbol: "newspaper", title: model.news.paid ? "News" : "News \(model.news.cost.formatted()) cr.",
                         emptyReason: model.news.blocker.map { ReasonText.text(for: $0) }, help: String(localized: "Read the local newspaper"),
                         identifier: BridgeID.System.news) {
                session.readNewspaper()
            }
            BridgeNotice(symbol: "sparkles", title: model.special == nil ? "No special offer" : "Special", tone: .info,
                         emptyReason: model.special == nil ? "Nobody has a special offer for you in this system" : nil,
                         help: model.special.map { String(localized: SpecialEventText.title($0.type)) } ?? "", identifier: BridgeID.System.special) {
                session.openSpecialEvent()
            }
            BridgeNotice(symbol: "person.badge.plus", title: model.mercenaries.map { "Hire \($0.crewIDs.count)" } ?? "Nobody for hire",
                         emptyReason: model.mercenaries == nil ? "No mercenary is looking for work in this system" : nil,
                         help: model.mercenaries.map { String(localized: $0.text) } ?? "", identifier: BridgeID.System.hire) {
                session.selectedSection = .crew
            }
            BridgeNotice(symbol: "hourglass", title: model.nearestDeadline.map { "Quest \($0) d" } ?? "No deadlines",
                         tone: (model.nearestDeadline ?? 9) <= 2 ? .caution : .neutral,
                         emptyReason: model.nearestDeadline == nil ? "None of your quests has a deadline" : nil,
                         help: model.nearestDeadline.map { String(localized: "Your nearest quest deadline: \(AccessibilityText.deadline(daysLeft: $0))") } ?? "",
                         identifier: BridgeID.System.quest) {
                session.selectedSection = .quests
            }
        }
        .frame(height: PointerTarget.minimum * scale)
    }
}
