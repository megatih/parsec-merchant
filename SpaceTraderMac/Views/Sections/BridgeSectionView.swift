// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Bridge (⌘1, UI-SHELL §7): the system card, dock services, offers and the target card, in two columns.
struct BridgeSectionView: View {
    @Environment(GameSession.self) private var session
    /// The visit (game, day, system) whose special event was declined; the card stays hidden until the next arrival.
    @SceneStorage("bridge.declinedSpecial") private var declinedSpecial = ""

    var body: some View {
        if let state = session.state {
            ScrollView {
                if let report = session.arrivalCard {
                    // UI-ENC-055: the arrival card sits at the top of Bridge.
                    ArrivalCardView(report: report)
                        .padding([.horizontal, .top], 20)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        leftColumn(state).frame(minWidth: 320, maxWidth: .infinity)
                        rightColumn(state).frame(minWidth: 300, maxWidth: .infinity)
                    }
                    VStack(spacing: 16) {
                        leftColumn(state)
                        rightColumn(state)
                    }
                }
                .padding(20)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AXID.SectionRoot.root(.bridge))
        }
    }

    @ViewBuilder
    private func leftColumn(_ state: GameState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SystemCard(model: .make(state: state, system: state.commander.currentSystem), galaxyCode: GalaxyCodeCard.code(state: state))
            DockServiceCard(model: .fuel(state: state))
            DockServiceCard(model: .hull(state: state))
        }
    }

    @ViewBuilder
    private func rightColumn(_ state: GameState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                MiniChartView()
            } label: {
                Label("Short-Range Chart", systemImage: "map")
            }
            TargetCard(model: TargetCardModel.make(state: state, isModal: session.isModal))
            if let special = SpecialEventCardModel.visible(state: state, gameID: session.gameID, declinedToken: declinedSpecial) {
                SpecialEventCardView(model: special) {
                    declinedSpecial = SpecialEventCardModel.visitToken(gameID: session.gameID, state: state)
                }
            }
            if let mercs = MercenaryCardModel.make(state: state) {
                MercenaryCard(model: mercs)
            }
            NewspaperCardView(model: .make(state: state))
        }
    }
}

// MARK: - System card (UI-SHELL-054, -103)

private struct SystemCard: View {
    let model: SystemCardModel
    let galaxyCode: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    PlanetPlaceholder(model: model)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: model.name).font(.title2.bold())
                        if let pressure = model.pressure, let tag = SystemText.pressure(pressure) {
                            PressureTag(text: tag, description: SystemText.pressureDescription(pressure))
                        }
                    }
                }
                SystemFacts(model: model)
                Divider()
                HStack {
                    LabeledContent("Galaxy code") {
                        Text(verbatim: galaxyCode).font(.body.monospaced()).textSelection(.enabled)
                    }
                    .accessibilityIdentifier(AXID.Bridge.galaxyCode)
                    Spacer()
                    Button {
                        GalaxyCodeCard.copy(galaxyCode)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help(Text("Copy the galaxy code so a friend can play the same galaxy."))
                    .accessibilityIdentifier(AXID.Bridge.galaxyCodeCopy)
                }
            }
        } label: {
            Label("Current System", systemImage: "globe")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Bridge.systemCard)
    }
}

/// The facts shared by the system and target cards.
private struct SystemFacts: View {
    let model: SystemCardModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Size") { Text(Names.size(model.size)) }
            row("Tech level") { Text(SystemText.techLevel(model.techLevel)) }
            row("Government") { Text(SystemText.government(model.government)) }
            row("Resource") { Text(SystemText.resource(model.resource)) }
            row("Police") { ActivityDots(activity: model.police) }
            row("Pirates") { ActivityDots(activity: model.pirates) }
        }
    }

    private func row(_ title: LocalizedStringResource, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            value()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityDots: View {
    let activity: Activity

    var body: some View {
        let filled = SystemCardModel.dots(activity)
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<SystemCardModel.maxActivityDots, id: \.self) { i in
                    Image(systemName: i < filled ? "circle.fill" : "circle")
                        .font(.system(size: 7))
                        .foregroundStyle(i < filled ? Color.primary : Color.secondary)
                }
            }
            .accessibilityHidden(true)
            Text(SystemText.activity(activity))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(SystemText.activity(activity)))
    }
}

private struct PressureTag: View {
    let text: LocalizedStringResource
    let description: LocalizedStringResource

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.2)))
            .help(Text(description))
            .accessibilityLabel(Text(description))
    }
}

/// The planet portrait stand-in until ParsecArt (M11).
private struct PlanetPlaceholder: View {
    let model: SystemCardModel

    var body: some View {
        Image(systemName: "globe.americas.fill")
            .font(.system(size: 44))
            .foregroundStyle(.tint)
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
    }
}

// MARK: - Dock services (UI-SHELL-055, -056)

private struct DockServiceCard: View {
    @Environment(GameSession.self) private var session
    let model: DockServiceModel
    @State private var amount = 0

    private var isFuel: Bool { model.kind == .fuel }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Gauge(value: Double(model.current), in: 0...Double(max(1, model.maximum))) {
                    EmptyView()
                } currentValueLabel: {
                    gaugeText
                }
                .gaugeStyle(.linearCapacity)
                .accessibilityLabel(gaugeText)
                if model.isComplete {
                    Text(isFuel ? "Tank full" : "No repairs needed").foregroundStyle(.secondary)
                } else {
                    controls
                }
            }
        } label: {
            Label(isFuel ? "Fuel" : "Hull", systemImage: isFuel ? "fuelpump" : "wrench.adjustable")
        }
        .onAppear { amount = model.defaultAmount }
        .onChange(of: model) { _, new in amount = new.defaultAmount }
    }

    private var gaugeText: Text {
        isFuel ? Text("Fuel \(model.current)/\(model.maximum) parsecs") : Text("Hull \(model.percent)%")
    }

    @ViewBuilder
    private var controls: some View {
        let reason = model.blocker.map { ReasonText.text(for: $0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    session.send(model.fullCommand)
                } label: {
                    Text(isFuel ? "Fill Up (\(model.fullCost.formatted()) cr.)" : "Repair (\(model.fullCost.formatted()) cr.)")
                }
                .disabled(model.blocker != nil)
                .help(reason.map { Text($0) } ?? Text(isFuel ? "Buy a full tank." : "Repair the hull completely."))
                .accessibilityIdentifier(isFuel ? AXID.Bridge.fuelFillUp : AXID.Bridge.repairFull)
                Spacer()
            }
            if let range = model.amountRange {
                HStack {
                    if range.lowerBound < range.upperBound {
                        Slider(value: sliderBinding(range), in: Double(range.lowerBound)...Double(range.upperBound))
                            .frame(minWidth: 100)
                            .accessibilityLabel(Text(isFuel ? "Fuel amount in credits" : "Repair amount in credits"))
                    }
                    TextField(value: $amount, format: .number) {
                        Text("Credits")
                    }
                    .frame(width: 80)
                    .monospacedDigit()
                    .accessibilityIdentifier(isFuel ? AXID.Bridge.fuelAmount : AXID.Bridge.repairAmount)
                    Button("Buy") { partialBuy() }
                        .disabled(model.partialCommand(credits: amount) == nil)
                        .help(Text(isFuel ? "Buy fuel for this many credits." : "Repair the hull for this many credits."))
                        .accessibilityIdentifier(isFuel ? AXID.Bridge.fuelBuy : AXID.Bridge.repairBuy)
                }
            } else if let reason {
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func sliderBinding(_ range: ClosedRange<Int>) -> Binding<Double> {
        Binding {
            Double(min(max(amount, range.lowerBound), range.upperBound))
        } set: {
            amount = Int($0.rounded())
        }
    }

    private func partialBuy() {
        if let command = model.partialCommand(credits: amount) { session.send(command) }
    }
}

// MARK: - Offers (UI-SHELL-058; the special-event and newspaper cards are UI-ENC-072/073 views)

private struct MercenaryCard: View {
    @Environment(GameSession.self) private var session
    let model: MercenaryCardModel

    var body: some View {
        GroupBox {
            HStack {
                Text(model.text)
                Spacer()
                Button("Go to Crew") { session.selectedSection = .crew }
                    .help(Text("Show the mercenaries in Crew."))
                    .accessibilityIdentifier(AXID.Bridge.mercenaries)
            }
        } label: {
            Label("Mercenaries", systemImage: "person.badge.plus")
        }
    }
}

// MARK: - Target card (UI-SHELL-059, -060)

private struct TargetCard: View {
    @Environment(GameSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    let model: TargetCardModel?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let model, model.system.index != session.state?.commander.currentSystem {
                    details(model)
                } else {
                    Text("No target selected. Use ‹ › or the toolbar to choose one.").foregroundStyle(.secondary)
                }
                if let jump = model?.jump, jump.rejection == nil, let state = session.state {
                    Label { Text("Singularity destination: \(Names.system(jump.destination, in: state))") } icon: {
                        Image(systemName: "sparkle")
                    }
                }
                HStack {
                    Button {
                        session.send(.selectNextTarget(forward: false))
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!(model?.canCycle ?? canCycle))
                    .help(Text("Previous system in range"))
                    .accessibilityLabel(Text("Previous target"))
                    .accessibilityIdentifier(AXID.Bridge.targetPrevious)
                    Button {
                        session.send(.selectNextTarget(forward: true))
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!(model?.canCycle ?? canCycle))
                    .help(Text("Next system in range"))
                    .accessibilityLabel(Text("Next target"))
                    .accessibilityIdentifier(AXID.Bridge.targetNext)
                    Spacer()
                    if let jump = model?.jump { jumpButton(jump) }
                    if let model, model.system.index != session.state?.commander.currentSystem {
                        Button("Warp") { session.send(.warp) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!model.warp.isEnabled)
                            .help(model.warp.help)
                            .accessibilityIdentifier(AXID.Bridge.targetWarp)
                    }
                }
            }
        } label: {
            Label("Target", systemImage: "scope")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Bridge.targetCard)
    }

    private var canCycle: Bool { !(session.state?.destinations.isEmpty ?? true) }

    @ViewBuilder
    private func details(_ model: TargetCardModel) -> some View {
        Text(verbatim: model.system.name).font(.title3.bold())
        if model.viaWormhole, let state = session.state {
            Label { Text("Wormhole to \(Names.system(model.system.index, in: state))") } icon: { Image(systemName: "tornado") }
        }
        SystemFacts(model: model.system)
        Divider()
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Distance").foregroundStyle(.secondary)
                Text("\(model.preview.distance) parsecs").monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            if model.preview.inRange {
                GridRow {
                    Text("Fuel after the jump").foregroundStyle(.secondary)
                    Text("\(model.preview.fuelAfter) parsecs").monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                costRows(model.preview.costs)
            }
        }
        if !model.preview.inRange {
            Text("Out of range").foregroundStyle(.red).bold()
        }
        HStack {
            if model.showsTrack {
                Button(model.isTracked ? "Untrack" : "Track") { session.send(model.trackCommand) }
                    .help(Text(model.isTracked ? "Stop tracking this system." : "Track this system on the way."))
                    .accessibilityIdentifier(AXID.Bridge.targetTrack)
            }
            let plot = MenuRules.availability(of: .plotRoute, in: MenuContext.make(state: session.state, isModal: session.isModal))
            Button("Plot Route…") { session.plotRouteToTarget() }
                .disabled(!plot.isEnabled)
                .help(Text("Plan a multi-jump route to this system on the galaxy chart."))
                .accessibilityIdentifier(AXID.Galaxy.bridgePlotRoute)
            Button("Show on Map") {
                if session.map.galaxyWindowOpen { openWindow(id: GalaxyWindowMetrics.id) }
                session.showOnMap(model.system.index)
            }
            .help(Text("Centre the galaxy chart on this system."))
            .accessibilityIdentifier(AXID.Galaxy.bridgeShowOnMap)
        }
    }

    @ViewBuilder
    private func costRows(_ c: DailyCosts) -> some View {
        costRow("Mercenaries", c.mercenaries)
        costRow("Insurance", c.insurance)
        costRow("Interest", c.interest)
        costRow("Wormhole tax", c.wormholeTax)
        costRow("Total costs", c.total)
    }

    private func costRow(_ title: LocalizedStringResource, _ value: Int) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text("\(value.formatted()) cr.").monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func jumpButton(_ jump: TargetCardModel.Jump) -> some View {
        let help: Text = if let rejection = jump.rejection {
            Text(ReasonText.text(for: rejection))
        } else if let blocking = jump.blocking {
            Text("The singularity will be used up, but you can't leave: \(ReasonText.string(for: blocking))")
        } else if let state = session.state {
            Text("Jump to \(Names.system(jump.destination, in: state)) with the portable singularity.")
        } else {
            Text(verbatim: "")
        }
        return Button("Use Singularity") { session.send(.jump) }
            .disabled(!jump.enabled)
            .help(help)
            .accessibilityIdentifier(AXID.Bridge.targetJump)
    }
}
