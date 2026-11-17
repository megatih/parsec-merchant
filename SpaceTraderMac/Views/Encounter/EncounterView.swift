// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The Encounter view (UI-ENC-015…036): header with badge, the two ship panes, the tactical readout, the combat log and
/// the action bar. It replaces the M7 interim panel; no sheet is used for the encounter itself.
struct EncounterView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        Group {
            if let engine = session.engine, let preview = engine.encounterPreview,
               let opponent = ShipPaneModel.opponent(state: engine.state, preview: preview) {
                content(engine: engine, preview: preview, opponent: opponent)
            } else {
                Text("Encounter").foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { session.stopEncounter() }
        .sheet(item: makeRoomBinding) { request in
            EncounterMakeRoomSheet(item: request.item)
                .environment(session)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Encounter.view)
    }

    private func content(engine: GameEngine, preview: EncounterPreview, opponent: ShipPaneModel) -> some View {
        let state = engine.state
        let player = ShipPaneModel.player(state: state, preview: preview)
        return VStack(spacing: 16) {
            EncounterHeader(intro: session.encounterUI.intro, badge: EncounterBadgeModel(badge: preview.badge))
            ZStack {
                HStack(alignment: .top, spacing: 24) {
                    ShipPaneView(model: player, identifiers: .player)
                    ShipPaneView(model: opponent, identifiers: .opponent)
                }
                TribbleOverlay(state: state)
            }
            if session.showsTacticalReadout, let readout = engine.tacticalReadout {
                TacticalReadoutPanel(readout: readout, ruleset: state.ruleset)
            }
            EncounterLogView(lines: session.encounterUI.log)
            if let resume = session.encounterResumePresentation {
                Button("Continue Decision") { session.present(resume) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .accessibilityIdentifier(AXID.Encounter.resumeDecision)
            } else if let menu = EncounterMenuState.make(engine: engine, autoRepeatOn: session.encounterUI.autoRepeatEnabled) {
                EncounterActionBar(model: .make(preview: preview, menu: menu, inputLocked: session.isInputLocked))
            }
        }
    }

    private struct MakeRoomRequest: Identifiable {
        let item: TradeItemType
        var id: String { "\(item)" }
    }

    private var makeRoomBinding: Binding<MakeRoomRequest?> {
        Binding {
            session.encounterUI.makeRoomItem.map(MakeRoomRequest.init)
        } set: { newValue in
            if newValue == nil { session.endMakeRoom() }
        }
    }
}

/// UI-ENC-016/017: the two intro lines and the badge.
private struct EncounterHeader: View {
    let intro: EncounterIntro?
    let badge: EncounterBadgeModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let intro {
                    Text(verbatim: intro.headline).font(.title3)
                    Text(verbatim: intro.action).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Encounter.intro)
            Label {
                Text(verbatim: badge.word)
            } icon: {
                Image(systemName: badge.symbol)
            }
            .font(.callout.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badge.isSpecial ? Color.yellow.opacity(0.35) : Color.secondary.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(badge.isSpecial ? Color.yellow : Color.clear, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: badge.word))
            .accessibilityIdentifier(AXID.Encounter.badge)
        }
    }
}

/// UI-ENC-021: the scrolling combat log; newest at the bottom, auto-scroll unless scrolled up, ⌘C copies the selection.
private struct EncounterLogView: View {
    let lines: [CombatLogLine]
    @State private var selection: Set<Int> = []
    @State private var pinnedToBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(verbatim: line.display)
                        .font(.callout)
                        .textSelection(.enabled)
                        .id(index)
                        .accessibilityIdentifier(AXID.Encounter.logRow(index))
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 24
            } action: { _, atBottom in
                pinnedToBottom = atBottom
            }
            .onChange(of: lines.count) { _, count in
                guard pinnedToBottom, count > 0 else { return }
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
            .onCopyCommand {
                let text = lines.enumerated().filter { selection.contains($0.offset) }.map(\.element.display).joined(separator: "\n")
                return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
            }
        }
        .frame(minHeight: 140)
        .accessibilityIdentifier(AXID.Encounter.log)
    }
}

/// UI-ENC-026: tribble placeholders; clicking one wiggles it (the squeak and sprite are M11).
private struct TribbleOverlay: View {
    let state: GameState

    var body: some View {
        let count = TribbleLayout.count(tribbles: state.commander.ship.tribbles)
        if count > 0, case let .encounter(enc) = state.phase {
            let points = TribbleLayout.positions(seed: state.seed, days: state.commander.days, clicks: enc.clicks, count: count)
            GeometryReader { geo in
                ForEach(Array(points.enumerated()), id: \.offset) { index, p in
                    TribbleButton(index: index)
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                }
            }
        }
    }
}

private struct TribbleButton: View {
    let index: Int
    @State private var wiggle = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.1).repeatCount(2, autoreverses: true)) { wiggle.toggle() }
        } label: {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(.brown)
                .rotationEffect(.degrees(wiggle ? 12 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Tribble"))
        .accessibilityIdentifier(AXID.Encounter.tribble(index))
    }
}

/// UI-ENC-043: the tactical readout before the first action (public information only).
private struct TacticalReadoutPanel: View {
    let readout: TacticalReadout
    let ruleset: Ruleset

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Class").foregroundStyle(.secondary)
                Text(verbatim: TacticalText.shipClass(readout, ruleset: ruleset))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Encounter.tacticalClass)
            GridRow {
                Text("Equipment").foregroundStyle(.secondary)
                Text(verbatim: TacticalText.equipment(readout))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Encounter.tacticalEquipment)
            if let odds = TacticalText.fleeOdds(readout) {
                GridRow {
                    Text("Flee odds").foregroundStyle(.secondary)
                    Text(verbatim: odds)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AXID.Encounter.tacticalFleeOdds)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .help(Text("An estimate from public information: the opponent's class, visible equipment and your flee odds."))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Encounter.tactical)
    }
}

/// Posts VoiceOver announcements for new combat-log rows (UI-ENC-025).
struct VoiceOverAnnouncer: EncounterAnnouncer {
    func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
