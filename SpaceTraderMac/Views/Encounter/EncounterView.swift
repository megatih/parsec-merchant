// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// The Encounter view (UI-ENC-015…036): header with badge, the two ship panes, the tactical readout, the combat log and
/// the action bar. It replaces the M7 interim panel; no sheet is used for the encounter itself.
struct EncounterView: View {
    @Environment(GameSession.self) private var session
    /// ART-043/044: the effects of the last step; a new step's plan replaces (cancels) a running one.
    @State private var effectPlan: [CombatEffect] = []
    @State private var effectStart: Date?

    var body: some View {
        Group {
            if let engine = session.engine, let preview = engine.encounterPreview,
               let opponent = ShipPaneModel.opponent(state: engine.state, preview: preview) {
                // A11Y-025: at large Text Sizes the view scrolls instead of growing past the window.
                ViewThatFits(in: .vertical) {
                    content(engine: engine, preview: preview, opponent: opponent)
                    ScrollView { content(engine: engine, preview: preview, opponent: opponent).frame(minHeight: 0) }
                }
            } else {
                Text("Encounter").foregroundStyle(.readableSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: session.stateGeneration) {
            effectPlan = CombatEffectPlanner.plan(record: session.lastStep)
            effectStart = effectPlan.isEmpty ? nil : .now
        }
        .sheet(item: makeRoomBinding) { request in
            EncounterMakeRoomSheet(item: request.item)
                .environment(session)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Encounter.view)
    }

    private func content(engine: GameEngine, preview: EncounterPreview, opponent: ShipPaneModel) -> some View {
        let state = engine.state
        let player = ShipPaneModel.player(state: state, preview: preview, cloaked: session.lastStep?.encounterStarted?.playerCloaked ?? false)
        return VStack(spacing: 16) {
            EncounterHeader(intro: session.encounterUI.intro, badge: EncounterBadgeModel(badge: preview.badge))
            ZStack {
                EncounterStage(player: player, opponent: opponent, plan: effectPlan, planStart: effectStart)
                TribbleOverlay(state: state)
            }
            if session.showsTacticalReadout, let readout = engine.tacticalReadout {
                TacticalReadoutPanel(readout: readout, ruleset: state.ruleset,
                                     metBefore: TacticalText.metBefore(MetBefore.make(opponent: readout.opponentType, journal: session.journal)))
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
                    Text(verbatim: intro.headline).scaledFont(.title3)
                    Text(verbatim: intro.action).foregroundStyle(.readableSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Encounter.intro)
            Label {
                Text(verbatim: badge.word)
            } icon: {
                EncounterBadgeGlyph(badge: badge.glyph)
                    .frame(width: 16, height: 16)
            }
            .scaledFont(.callout, weight: .bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badge.isSpecial ? Color.yellow.opacity(0.35) : Color.secondary.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(badge.isSpecial ? Color.yellow : Color.clear, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: badge.word))
            .accessibilityAddTraits(.isImage)  // a glyph with its word; the label stays the word
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
                        .scaledFont(.callout)
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
        .accessibilityLabel(Text("Combat log"))  // A11Y-003
        .accessibilityIdentifier(AXID.Encounter.log)
    }
}

/// UI-ENC-026, ART-035: drawn tribble sprites; clicking one wiggles it.
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
    @Environment(GameSession.self) private var session
    @State private var wiggleStart: Date?
    @Environment(\.accessibilityPreferences) private var a11yPrefs
    private var reduceMotion: Bool { a11yPrefs.reduceMotion }

    var body: some View {
        Button {
            session.tribbleClicked()  // AUD-030: the squeak; the wiggle is its visual twin
            wiggleStart = .now
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: wiggleStart == nil)) { timeline in
                TribbleSprite(index: index, phase: wiggleStart.map { timeline.date.timeIntervalSince($0) } ?? -1, reduceMotion: reduceMotion)
            }
            .frame(width: 22, height: 22)
            .pointerTarget()  // UI-PTR-015: the sprite keeps its size inside a 36 pt target
        }
        .buttonStyle(.plain)
        .task(id: wiggleStart) {
            guard wiggleStart != nil else { return }
            try? await Task.sleep(for: .milliseconds(250))
            wiggleStart = nil
        }
        .accessibilityLabel(Text("Tribble"))
        .accessibilityIdentifier(AXID.Encounter.tribble(index))
    }
}

/// UI-ENC-043: the tactical readout before the first action (public information only).
private struct TacticalReadoutPanel: View {
    let readout: TacticalReadout
    let ruleset: Ruleset
    /// INT-039: the one intel line.
    var metBefore: String?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Class").foregroundStyle(.readableSecondary)
                Text(verbatim: TacticalText.shipClass(readout, ruleset: ruleset))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Encounter.tacticalClass)
            GridRow {
                Text("Equipment").foregroundStyle(.readableSecondary)
                Text(verbatim: TacticalText.equipment(readout))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Encounter.tacticalEquipment)
            if let odds = TacticalText.fleeOdds(readout) {
                GridRow {
                    Text("Flee odds").foregroundStyle(.readableSecondary)
                    Text(verbatim: odds)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AXID.Encounter.tacticalFleeOdds)
            }
            if let metBefore {
                GridRow {
                    Text("History").foregroundStyle(.readableSecondary)
                    Text(verbatim: metBefore)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .scaledFont(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .help(Text("An estimate from public information: the opponent's class, visible equipment and your flee odds."))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Encounter.tactical)
    }
}
