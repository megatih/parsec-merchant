// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The New Game wizard (UI-SHELL-022…030): six steps over a `NewGameDraft`.
struct NewGameWizard: View {
    @Environment(GameSession.self) private var session
    @State private var draft: NewGameDraft?
    @State private var step: NewGameDraft.Step = .commander
    @State private var startError: CommandError?
    @State private var seedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let draft {
                header
                Divider()
                ScrollView {
                    page(draft)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                footer(draft)
            }
        }
        .frame(width: 640, height: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.NewGame.sheet)
        .onAppear {
            if draft == nil {
                let d = NewGameDraft(commanderName: session.lastCommanderName, seed: session.newGameSeed(),
                                     options: OptionsTemplate.load(for: .modern, defaults: session.defaults))
                draft = d
                seedText = String(d.seed)
            }
        }
    }

    private func update(_ change: (inout NewGameDraft) -> Void) {
        guard var d = draft else { return }
        change(&d)
        d.options = OptionsTemplate.load(for: d.ruleset, defaults: session.defaults)
        draft = d
        startError = nil
    }

    // MARK: Header and footer

    private var header: some View {
        // A11Y-026: the steps wrap onto further lines at large Text Sizes (and with long translations) instead of
        // breaking words; the chevrons point forward in either writing direction.
        WrappingHStack(spacing: 6, lineSpacing: 4, leading: true) {
            ForEach(NewGameDraft.Step.allCases, id: \.self) { s in
                HStack(spacing: 6) {
                    Text(s.title)
                        .scaledFont(.callout, weight: s == step ? .bold : .medium)
                        // A11Y-029: the other steps in the readable secondary colour (the system one is too light).
                        .foregroundStyle(s == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.readableSecondary))
                    if s != .summary {
                        Image(systemName: "chevron.forward").scaledFont(.caption2).foregroundStyle(.readableSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(NewGameDraft.Step.allCases.count): \(String(localized: step.title))"))
    }

    private func footer(_ d: NewGameDraft) -> some View {
        // A11Y-026: when the message does not fit beside the buttons, it moves onto its own line above them.
        ViewThatFits(in: .horizontal) {
            HStack {
                cancelButton
                Spacer()
                footerMessages(d).fixedSize()
                navigationButtons(d)
            }
            VStack(alignment: .trailing, spacing: 8) {
                footerMessages(d)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    cancelButton
                    Spacer()
                    navigationButtons(d)
                }
            }
        }
        .padding(16)
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel) { session.cancel() }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(AXID.NewGame.cancel)
    }

    @ViewBuilder
    private func footerMessages(_ d: NewGameDraft) -> some View {
        if let reason = d.canAdvance(from: step).reason {
            Text(reason).scaledFont(.callout).foregroundStyle(.readableSecondary)
        }
        if let startError {
            Text(ReasonText.text(for: startError)).scaledFont(.callout).foregroundStyle(.signalRed)
        }
    }

    @ViewBuilder
    private func navigationButtons(_ d: NewGameDraft) -> some View {
        let availability = d.canAdvance(from: step)
        HStack {
            Button("Back") { if let prev = NewGameDraft.Step(rawValue: step.rawValue - 1) { step = prev } }
                .disabled(step == .commander)
                .accessibilityIdentifier(AXID.NewGame.back)
            if step == .summary {
                Button("Start") { start(d) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!availability.isEnabled)
                    .help(availability.reason.map { Text($0) } ?? Text("Start the game."))
                    .accessibilityIdentifier(AXID.NewGame.start)
            } else {
                Button("Next") { if let next = NewGameDraft.Step(rawValue: step.rawValue + 1) { step = next } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!availability.isEnabled)
                    .help(availability.reason.map { Text($0) } ?? Text("Go to the next step."))
                    .accessibilityIdentifier(AXID.NewGame.next)
            }
        }
    }

    private func start(_ d: NewGameDraft) {
        if let error = session.startNewGame(d.config) {
            startError = error
        } else {
            session.dismissPresentation()
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func page(_ d: NewGameDraft) -> some View {
        switch step {
        case .commander: commanderPage(d)
        case .difficulty: difficultyPage(d)
        case .ruleset: rulesetPage(d)
        case .skills: skillsPage(d)
        case .galaxy: galaxyPage(d)
        case .summary: summaryPage(d)
        }
    }

    private func commanderPage(_ d: NewGameDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's your name, Commander?").scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            TextField("Commander name", text: Binding { d.commanderName } set: { v in update { $0.commanderName = v } })
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .accessibilityLabel(Text("Commander name"))  // A11Y-003
                .accessibilityIdentifier(AXID.NewGame.name)
        }
    }

    private func difficultyPage(_ d: NewGameDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a difficulty").scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            ForEach(Difficulty.allCases, id: \.self) { level in
                choiceRow(selected: d.difficulty == level, title: Names.difficulty(level),
                          detail: WizardText.difficultyDescription(level)) {
                    update { $0.setDifficulty(level) }
                }
                .accessibilityIdentifier(AXID.NewGame.difficulty(level))
            }
        }
    }

    private func rulesetPage(_ d: NewGameDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the rules").scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            ForEach(RulesetID.allCases, id: \.self) { r in
                VStack(alignment: .leading, spacing: 4) {
                    choiceRow(selected: d.ruleset == r, title: Names.ruleset(r), detail: WizardText.rulesetTagline(r)) {
                        update { $0.setRuleset(r) }
                    }
                    .accessibilityIdentifier(AXID.NewGame.ruleset(r))
                    ForEach(WizardText.rulesetBullets(r).indices, id: \.self) { i in
                        Label { Text(WizardText.rulesetBullets(r)[i]) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)) }
                            .scaledFont(.callout)
                            .foregroundStyle(.readableSecondary)
                            .padding(.leading, 28)
                    }
                }
            }
            Text("The rules can't be changed once the game has started.").scaledFont(.callout).foregroundStyle(.readableSecondary)
        }
    }

    private func skillsPage(_ d: NewGameDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distribute your skill points").scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            ForEach(SkillType.allCases, id: \.self) { skill in
                HStack {
                    VStack(alignment: .leading) {
                        Text(Names.skill(skill)).scaledFont(.headline)
                        Text(WizardText.skillDescription(skill)).scaledFont(.callout).foregroundStyle(.readableSecondary)
                    }
                    Spacer()
                    Button { update { $0.decrement(skill) } } label: { Image(systemName: "minus").pointerTarget() }
                        .disabled(!d.canDecrement(skill))
                        .accessibilityLabel(Text("Decrease \(String(localized: Names.skill(skill)))"))
                        .accessibilityIdentifier(AXID.NewGame.skillDecrement(skill))
                    Text(verbatim: "\(d.skills[skill.rawValue])")
                        .fontWeight(.semibold)  // A11Y-029: a one-digit value
                        .monospacedDigit()
                        .frame(width: 28)
                        .accessibilityIdentifier(AXID.NewGame.skillValue(skill))
                    Button { update { $0.increment(skill) } } label: { Image(systemName: "plus").pointerTarget() }
                        .disabled(!d.canIncrement(skill))
                        .accessibilityLabel(Text("Increase \(String(localized: Names.skill(skill)))"))
                        .accessibilityIdentifier(AXID.NewGame.skillIncrement(skill))
                }
            }
            HStack {
                Text("Points remaining: \(d.preview.pointsRemaining)")
                    .monospacedDigit()
                    .accessibilityIdentifier(AXID.NewGame.pointsRemaining)
                Spacer()
                Button("Balanced") { update { $0.balance() } }
                    .accessibilityIdentifier(AXID.NewGame.balanced)
            }
        }
    }

    private func galaxyPage(_ d: NewGameDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Galaxy and extras").scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            LabeledContent("Galaxy code") {
                TextField("Galaxy code", text: Binding { d.galaxyCodeText } set: { v in
                    update { $0.setGalaxyCodeText(v) }
                    if let s = draft?.seed { seedText = String(s) }
                })
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Galaxy code"))  // A11Y-003
                .accessibilityIdentifier(AXID.NewGame.galaxyCode)
            }
            if d.galaxyCodeInvalid {
                Text("Not a valid galaxy code.").scaledFont(.callout).foregroundStyle(.signalRed)
            }
            LabeledContent("Seed") {
                HStack {
                    TextField("Seed", text: Binding { seedText } set: { v in
                        seedText = v
                        if let s = UInt64(v) { update { $0.setSeed(s) } }
                    })
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .accessibilityLabel(Text("Seed"))
                    .accessibilityIdentifier(AXID.NewGame.seed)
                    Button("Randomize") {
                        var g = SystemRandomNumberGenerator()
                        let s = UInt64.random(in: .min ... .max, using: &g)
                        update { $0.setSeed(s) }
                        seedText = String(s)
                    }
                    .accessibilityIdentifier(AXID.NewGame.randomizeSeed)
                }
            }
            Toggle(isOn: Binding { d.ironman } set: { v in update { $0.ironman = v } }) {
                VStack(alignment: .leading) {
                    Text("Ironman")
                    Text("One save, no reloading; your score gets an Ironman badge.").scaledFont(.callout).foregroundStyle(.readableSecondary)
                }
            }
            .accessibilityIdentifier(AXID.NewGame.ironman)
            LabeledContent("Ship name (optional)") {
                TextField("Ship name", text: Binding { d.shipName } set: { v in
                    update { $0.shipName = String(v.prefix(NewGameDraft.maxShipNameLength)) }
                })
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Ship name"))
                .accessibilityIdentifier(AXID.NewGame.shipName)
            }
            LabeledContent("Options") {
                Text(d.options == nil ? "Standard options" : "Your saved defaults")
            }
        }
    }

    private func summaryPage(_ d: NewGameDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready to launch").scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            LabeledContent("Commander") { Text(verbatim: d.commanderName) }
            LabeledContent("Difficulty") { Text(Names.difficulty(d.difficulty)) }
            LabeledContent("Rules") { Text(Names.ruleset(d.ruleset)) }
            LabeledContent("Skills") {
                Text(verbatim: SkillType.allCases.map { "\(String(localized: Names.skill($0))) \(d.skills[$0.rawValue])" }
                    .joined(separator: ", "))
            }
            LabeledContent("Galaxy code") { Text(verbatim: d.galaxyCode).fontWeight(.medium) }  // A11Y-029
            LabeledContent("Ironman") { Text(d.ironman ? "On" : "Off") }
            LabeledContent("Ship name") { Text(verbatim: d.trimmedShipName ?? "—") }
            LabeledContent("Options") { Text(d.options == nil ? "Standard options" : "Your saved defaults") }
            if let failing = d.firstFailingStep {
                Text("Check the \(String(localized: failing.title)) step.").foregroundStyle(.signalRed)
            }
        }
    }

    private func choiceRow(selected: Bool, title: LocalizedStringResource, detail: LocalizedStringResource,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).scaledFont(.headline)
                    Text(detail).scaledFont(.callout).foregroundStyle(.readableSecondary)
                }
            }
            .pointerTarget()  // UI-PTR-002
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wizard copy (localized).
enum WizardText {
    static func difficultyDescription(_ d: Difficulty) -> LocalizedStringResource {
        switch d {
        case .beginner: "Forgiving encounters and generous skills while you learn the ropes."
        case .easy: "Fewer dangers in space and an easier start."
        case .normal: "The classic balance of risk and reward."
        case .hard: "Tougher opponents and stricter police."
        case .impossible: "Space is merciless. For veterans only."
        }
    }

    static func rulesetTagline(_ r: RulesetID) -> LocalizedStringResource {
        switch r {
        case .modern: "Recommended"
        case .windows201: "Classic"
        case .palm122: "The original"
        }
    }

    static func rulesetBullets(_ r: RulesetID) -> [LocalizedStringResource] {
        switch r {
        case .modern:
            ["Fixes the classic bugs and exploits.", "Restores some Palm behaviour the Windows port lost.",
             "All quests, shipyards and the ship designer.", "Best for a first game."]
        case .windows201:
            ["Faithful to the Windows 2.01 port, quirks included.", "All quests, shipyards and the ship designer.",
             "For players who know the classic Windows game."]
        case .palm122:
            ["120 systems, as on the Palm.", "No sculpture or princess quests, no shipyards and no disruptors.",
             "The original quirks are kept."]
        }
    }

    static func skillDescription(_ s: SkillType) -> LocalizedStringResource {
        switch s {
        case .pilot: "Dodging shots and escaping fights."
        case .fighter: "Hitting what you shoot at."
        case .trader: "Better prices for goods and equipment."
        case .engineer: "Repairs in flight and stronger shields."
        }
    }
}
