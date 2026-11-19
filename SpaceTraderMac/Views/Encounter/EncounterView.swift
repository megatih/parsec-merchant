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

    @Environment(\.pmScale) private var scale

    var body: some View {
        GeometryReader { geo in
            if let engine = session.engine, let preview = engine.encounterPreview,
               let opponent = ShipPaneModel.opponent(state: engine.state, preview: preview) {
                // UI-ENC-200: intro and badge, the two ship panels (55% of the height), the action bar across the full
                // width, then the combat log: the controls never sit at the window's bottom edge.
                let state = engine.state
                let player = ShipPaneModel.player(state: state, preview: preview, cloaked: session.lastStep?.encounterStarted?.playerCloaked ?? false)
                VStack(spacing: PMSpace.s * scale) {
                    EncounterHeader(intro: session.encounterUI.intro, badge: EncounterBadgeModel(badge: preview.badge))
                    ZStack {
                        EncounterStage(player: player, opponent: opponent, plan: effectPlan, planStart: effectStart)
                        TribbleOverlay(state: state)
                    }
                    .frame(height: max(180 * scale, geo.size.height * 0.55))
                    .overlay(alignment: .bottomTrailing) { captainPortrait(state) }
                    actions(engine: engine, preview: preview)
                    HStack(alignment: .top, spacing: PMSpace.s * scale) {
                        EncounterLogView(lines: session.encounterUI.log)
                        if session.showsTacticalReadout, let readout = engine.tacticalReadout {
                            TacticalReadoutPanel(readout: readout, ruleset: state.ruleset,
                                                 metBefore: TacticalText.metBefore(MetBefore.make(opponent: readout.opponentType,
                                                                                                    journal: session.journal)))
                                .frame(width: 320 * scale)
                        }
                    }
                }
                .padding(PMSpace.m * scale)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            } else {
                Text("Encounter").pmFont(.body).foregroundStyle(PMColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: session.stateGeneration) {
            effectPlan = CombatEffectPlanner.plan(record: session.lastStep)
            effectStart = effectPlan.isEmpty ? nil : .now
        }
        .sheet(item: makeRoomBinding) { request in
            EncounterMakeRoomSheet(item: request.item)
                .environment(session)
                .pmSheetChrome()  // UI-PTR-002
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Encounter.view)
    }

    /// UI-ENC-204: a famous captain's portrait, in the corner of the opponent's panel. Other opponents have none.
    @ViewBuilder
    private func captainPortrait(_ state: GameState) -> some View {
        if case let .encounter(encounter) = state.phase, let role = EncounterPortrait.role(encounter.type) {
            CharacterPortrait(role: role)
                .frame(width: 84 * scale, height: 84 * scale)
                .clipShape(RoundedRectangle(cornerRadius: PMRadius.control * scale))
                .overlay { RoundedRectangle(cornerRadius: PMRadius.control * scale).strokeBorder(PMColor.accent) }
                .padding(PMSpace.m * scale)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Portrait of \(String(localized: EncounterPortrait.name(role)))"))
                .accessibilityAddTraits(.isImage)
                .probed(AXID.Encounter.captainPortrait)
        }
    }

    @ViewBuilder
    private func actions(engine: GameEngine, preview: EncounterPreview) -> some View {
        if let resume = session.encounterResumePresentation {
            Button("Continue Decision") { session.present(resume) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PMButtonStyle(kind: .primary))
                .buttonStyle(PMButtonStyle(kind: .primary))
                .accessibilityIdentifier(AXID.Encounter.resumeDecision)
        } else if let menu = EncounterMenuState.make(engine: engine, autoRepeatOn: session.encounterUI.autoRepeatEnabled) {
            EncounterActionBar(model: .make(preview: preview, menu: menu, inputLocked: session.isInputLocked))
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

/// UI-ENC-204: which authored portrait an encounter shows.
enum EncounterPortrait {
    static func role(_ type: EncounterType) -> PortraitRole? {
        switch type {
        case .captainAhab: .ahab
        case .captainConrad: .conrad
        case .captainHuie: .huie
        default: nil
        }
    }

    /// ART-FACE-010: the captain's name for the portrait's label.
    static func name(_ role: PortraitRole) -> LocalizedStringResource {
        switch role {
        case .ahab: "Captain Ahab"
        case .conrad: "Captain Conrad"
        case .huie: "Captain Huie"
        default: "the famous captain"
        }
    }
}

/// UI-ENC-202: the colour of an encounter role; the badge always carries its symbol and its word too.
enum EncounterRoleColor {
    static func color(_ badge: EncounterBadge) -> Color {
        switch badge {
        case .police: PMColor.rolePolice
        case .pirate: PMColor.rolePirate
        case .trader: PMColor.roleTrader
        case .alien: PMColor.roleAlien
        case .special: PMColor.accent
        }
    }
}

/// UI-ENC-016/017, UI-ENC-202: the two intro lines and the role badge (a symbol and a word, in the role colour).
private struct EncounterHeader: View {
    let intro: EncounterIntro?
    let badge: EncounterBadgeModel
    @Environment(\.pmScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: PMSpace.m * scale) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                if let intro {
                    Text(verbatim: intro.headline).pmFont(.title).foregroundStyle(PMColor.textPrimary)
                    Text(verbatim: intro.action).pmFont(.body).foregroundStyle(PMColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .probed(AXID.Encounter.intro)
            let color = EncounterRoleColor.color(badge.badge)
            HStack(spacing: PMSpace.xs * scale) {
                EncounterBadgeGlyph(badge: badge.glyph).frame(width: 16 * scale, height: 16 * scale)
                Text(verbatim: badge.word).pmFont(.valueLarge).foregroundStyle(color)
            }
            .padding(.horizontal, PMSpace.m * scale)
            .padding(.vertical, PMSpace.xs * scale)
            .background(PMColor.panelRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(color, lineWidth: 1.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: badge.word))
            .accessibilityAddTraits(.isImage)  // a glyph with its word; the label stays the word
            .probed(AXID.Encounter.badge)
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
                        .pmFont(.body)
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
        .frame(minHeight: 60)
        .scrollContentBackground(.hidden)
        .background(PMColor.panel, in: RoundedRectangle(cornerRadius: PMRadius.panel))
        .accessibilityLabel(Text("Combat log"))  // A11Y-003
        .probed(AXID.Encounter.log)
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
                Text("Class").foregroundStyle(PMColor.textSecondary)
                Text(verbatim: TacticalText.shipClass(readout, ruleset: ruleset))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Encounter.tacticalClass)
            GridRow {
                Text("Equipment").foregroundStyle(PMColor.textSecondary)
                Text(verbatim: TacticalText.equipment(readout))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Encounter.tacticalEquipment)
            if let odds = TacticalText.fleeOdds(readout) {
                GridRow {
                    Text("Flee odds").foregroundStyle(PMColor.textSecondary)
                    Text(verbatim: odds)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AXID.Encounter.tacticalFleeOdds)
            }
            if let metBefore {
                GridRow {
                    Text("History").foregroundStyle(PMColor.textSecondary)
                    Text(verbatim: metBefore)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .pmFont(.body)
        .foregroundStyle(PMColor.textPrimary)
        .padding(PMSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PMColor.panel, in: RoundedRectangle(cornerRadius: PMRadius.panel))
        .help(Text("Estimate the opponent from public facts: class, equipment and flee odds"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Encounter.tactical)
    }
}
