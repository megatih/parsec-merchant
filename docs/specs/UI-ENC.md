# UI-ENC: Encounter, transit and event UX

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement (source)`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests that need a window (`SpaceTraderMacTests` hosted in the app) or by XCUITest (`SpaceTraderMacUITests`). Bullets without `[UI]` are pure logic: app-target functions over Sendable values, unit-tested in `SpaceTraderMacTests` without a window, or the engine additions of §15, unit-tested in `ParsecEngineTests`. `[manual]` = a QA-REPORT row.
> Milestones: everything here is {M9} (PRD §9 M9: "Encounter mode, transit (Dock tile progress), auto-repeat, combat log, tactical readout, plunder/trade/consent sheets, the arrival report card, event feed, newspaper, special-event sheets, game over with the career card, high scores"; exit: `--ui` flow 2 green and "every `PendingDecision` and ALR mapping has a presentation (test)"). Later items are listed in §16 with their own tag: Logbook, statistics, achievements and flavor {M10} (LOG, STAT, ACH, LLM, INT); ship art, animation, audio and haptics {M11} (ART, AUD); accessibility audit, Text Size, keyboard and localization completeness {M12} (A11Y, UI-KEYS).
> Normative inputs: docs/design/UX-VISION.md §1.2, §3, §4.1, §5.1–5.6, §6, §7, §9, §10, §10.1; PRD §6.5, §6.6 (tactical readout, fairness), §8.2 (routing test, flow 2), §8.3. Classic behaviour: research 02 §3 (encounter buttons) and §4 (alerts), with their QA ERRATA. C# sources are relative to `/Users/megatih/Downloads/SpaceTraderSource201` (read with `iconv -f cp1252 -t utf-8`); Palm sources are `docs/reference/palm-src/Src/…`. Line numbers were re-read on 2026-11-17.
> **Ownership (do not restate, reference).** Encounter rules, action sets, default actions, badges, the preview and auto-repeat semantics: ENC (ENC-112, ENC-113, ENC-130…132, ENC-180…191). Combat rounds, escapes, scoop and plunder effects: CMB. Police consequences: POL. The transit click loop and arrival pipeline: TRV-040…045, TRV-082. Which presentation each classic alert gets: the "New presentation" column of ALR §4. Newspaper composition and strings tables: NEWS-014…046; NEWS-047 is implemented here. Special-event rules and texts: QST-016/017. Score, endings and the high-score table: SCORE-015, SCORE-024/025, SCORE-036…039. Menu structure, shortcuts and enablement: MENU (MENU-036/037 detailed here). GameSession, `send`, the presentation queue, `PresentationRouter`, the text functions, the feed and the interim surfaces this spec replaces: UI-SHELL-001…012, UI-SHELL-044, UI-SHELL-057/058, UI-SHELL-097. Launch arguments: CHEAT-047…051; developer tester: CHEAT-038. Settings keys `settings.fastTravel`, `settings.arrivalReportStyle`, `settings.tacticalReadout`: UI-SHELL-100.

## Conventions (normative for every bullet below)

- **UI-SHELL conventions apply**: localization through `Localizable.xcstrings` (plural variants for "day(s)" and "credit(s)"), no `.popover`, an `.accessibilityIdentifier` on every interactive element (scheme `<scope>.<element>[.<qualifier>]`, constants in `AXID`, mirrored in `SpaceTraderMacUITests/AXID.swift`), inline reasons for rejections, destructive roles from the ALR "(destructive)" marking.
- **Pure core, thin views.** Every model in this spec (detail routing, transit playback, combat log, auto-repeat machine, tactical readout text, arrival report, feed classification, newspaper text, narrative pages, career card, high-score rows, presentation coverage) is a pure function or value type in `SpaceTraderMac/Session/` or `SpaceTraderMac/Text/`, importing Foundation and ParsecEngine only, never `GameSession` or SwiftUI. Views wire them up.
- **Commands only through the session.** Every action is a `Command` sent with `GameSession.send(_:acknowledging:)` (UI-SHELL-003/004). No view mutates `GameState`. Timing (playback, auto-repeat) lives in the app and never changes engine results or RNG draws (ENC-188, CHEAT-050).
- **Step records.** Builders that need "before and after" read a `StepRecord` (UI-ENC-005), never a stored `GameState` outside a render.
- **Color is never the only signal** (UX-VISION §1.7): every bar, badge and severity pairs color with a symbol, a sign or text.
- **Identifiers of the M7 interim surfaces are reused** where the element survives (`encounter.action.<EncounterAction>`, `decision.*`, `gameOver.*`), as UI-SHELL §19 allows.

## 1. Presentation model and routing

- **UI-ENC-001** {M9} [M][W][P] `DetailMode.derive(state: GameState?, playback: TransitPlayback?, selected: Section) -> DetailMode` (pure) decides the main window's detail area: `.transit(playback)` while a playback runs (§2); else `.encounter` when `state.phase` is `.encounter`; else `.gameOver(end)` for `.gameOver(end)`; else `.section(selected)`. A resting `.inTransit` phase (only reachable from a hand-edited save) yields `.transit` with a static playback at `20 − clicksRemaining` (UI-ENC-013). Unit test over every `GamePhase` with and without a playback. Replaces the phase switch of `MainShellView` and retires `InterimEncounterPanel`/`GameOverCard`. (source: UX-VISION §5.1, §5.2 "the detail area becomes the Encounter view", §5.5; UI-SHELL-009)
- **UI-ENC-002** {M9} [M][W][P] `SheetRoute` loses `encounterInterim` and `decision(_)` and gains `tradeInOrbit(OrbitTradeOffer)`, `plunder(PlunderSheetContext)` (`victimCargo: [Int]`, `source: .opponent | .marieCeleste`), `newspaper(Newspaper)`, `narrative(NarrativePage)` (UI-ENC-074), `report(ReportSheet)` (UI-ENC-058) and `developerTester` (UI-ENC-092); `Presentation` gains `scoop(TradeItemType)`, a `confirmationDialog`. Each new case has a stable `key`/`id` as in UI-SHELL-005, so the FIFO queue and `dismissPresentation(ifCurrent:)` keep working. (source: UI-SHELL-005, UI-SHELL-011; UX-VISION §5.2 "Sub-flows")
- **UI-ENC-003** {M9} [M][W][P] `PresentationRouter.route` (UI-SHELL-006) maps, with an exhaustive `switch` and no `default`: `.tradeInOrbit(o)` → `.sheet(.tradeInOrbit(o))`; `.plunder(c)` → `.sheet(.plunder(…))`, with source `.marieCeleste` when the command was `.encounter(.board)`; `.scoop(i)` → `.scoop(i)`; `.newspaper(p)` → `.sheet(.newspaper(p))`; `.confirm(c)` as UI-SHELL-006, except `.acceptSpecialEvent` → `.sheet(.narrative(.offer(type)))` (the narrative sheet is that warning's consent, UI-ENC-076). Unit test with one value of every `PendingDecision` case and every `WarningID`. (source: PRD §8.2 "routing for every PendingDecision"; ALR-052, ALR-070, ALR-071)
- **UI-ENC-004** {M9} [M][W][P] **Exhaustive presentation coverage (PRD §9 M9 exit).** `ALRCatalog.rows: [ALRRow]` holds the 188 rows of ALR §4 in `Enums.cs` order, each `{number, alertType: String, presentation: ALRPresentation}`, where `ALRPresentation` is one of `.inlineReason(CommandError)`, `.previewNote(PreviewNote)`, `.confirmation(WarningID)`, `.transferOption`, `.decision(PendingDecisionKind)`, `.appConfirmation(AppConfirmationKind)`, `.event(GameEventKind, surfaces: Set<EventSurface>)`, `.narrative(NarrativeKey)`, `.highScoreOutcome(HighScoreOutcomeKind)`, `.systemAlert(SystemAlertKind)` or `.removed(replacement: ALRReplacement)`. One unit test checks, without UI:
  1. there are 188 rows numbered 1…188, `alertType` names are unique, and each row's number, name and class equal the ALR §4 table (the test reads `docs/specs/ALR.md` relative to `#filePath`);
  2. **every `PendingDecision` case** routes (UI-ENC-003) to a `Presentation` whose view exists (`SheetRouteView`/`PresentationHost` switch without `default`);
  3. **every `WarningID`** has `ConfirmationText.content` with non-empty strings, its route, and `isDestructive` equal to the ALR marking;
  4. **every `CommandError`** has a non-empty `ReasonText`;
  5. **every `GameEvent` case** (one fixture per case) has a non-empty `EventText`, a feed classification (UI-ENC-064) and `EventSurfaces.surfaces(for:)` ⊇ the surfaces its ALR rows list (combat log, feed, arrival-report section, report-sheet section, game-over card, narrative result, transit banner, comm);
  6. every `.narrative` row has a page from `NarrativeText` (UI-ENC-078) or a comm line (UI-ENC-066); every `HighScoreOutcome` and `RecordedScore` case has outcome text (UI-ENC-084); every `SystemAlert` and `AppConfirmation` case has text;
  7. every `.removed` row names a replacement that exists (an `AXID`, a route or a command), and no `GameEvent`, `WarningID`, `CommandError` or `PendingDecision` case is mapped from a removed row.
  
  The switches that produce these values have no `default`, so a new engine case fails to compile until it is presented. (source: PRD §8.2 "every PendingDecision and every ALR mapping, with an exhaustive switch and a test", §9 M9; ALR §1 "Presentation side", §6; UI-SHELL-006, UI-SHELL-007)
- **UI-ENC-005** {M9} [M][W][P] `GameSession.send` keeps the last accepted step as `lastStep: StepRecord {command, acknowledged, before: GameState, result: StepResult, after: GameState}` (a value, replaced on each accepted step, cleared on load, new game and close). The combat log (UI-ENC-022), trip accumulator (UI-ENC-053) and report sheets (UI-ENC-058) consume it in `apply` in that order, before the presentation queue runs. A unit test drives a warp with an encounter and checks the three consumers saw the same record. (source: ALR notes 2026-11-17 "derived by the app from the state before and after the step"; UI-SHELL-003)
- **UI-ENC-006** {M9} [M][W][P] `GameSession.isInputLocked` is `isModal || transitPlayback != nil`. While it is true no command is sent from the action bar, the Encounter menu, Return, Esc, the toolbar or the sidebar, and `MenuContext.phase` (MENU-002) reports `.inTransit`. MENU-006/009 then disable the File, View, Game and Encounter items as specified there. Unit test on `MenuContext.make` with a running playback. (source: UX-VISION §9 "Encounter lock"; MENU-002, MENU-006, MENU-009)

## 2. Transit

- **UI-ENC-007** {M9} [M][W][P] `TransitPlayback.make(step: StepRecord, fast: Bool) -> TransitPlayback?` (pure) is non-nil for a step whose events contain `departed(…)`, or that ends an encounter while the trip continues. It holds `destination`, `viaWormhole`, `fromClick`, `toClick` and `end: .arrival | .encounter | .gameOver | .report`. For a warp, `fromClick = 20`. `toClick` is the `clicks` of the step's `encounterStarted`, or 0 when the step docks or ends the game. After an encounter that ends mid-trip, `fromClick` is that encounter's click − 1 (TRV-042). Ticks run every 60 ms, so a full trip takes 1.2 s. With `fast` (Settings › Fast travel, `-PMFastTravel` or `accessibilityReduceMotion`), the playback has zero duration and is skipped. Unit tests cover an uneventful warp, an encounter at click 7, a resumed trip, a fabric rip and a fast playback. (source: UX-VISION §5.1 "20-tick progress track … ≈1.2 s total; instant with Reduce Motion or the Fast travel setting"; TRV-040…042; CHEAT-050)
- **UI-ENC-008** {M9} [UI] [M][W][P] The Transit view (`transit.view`) shows "En route to <destination>" (with "via wormhole" when it applies), a 20-segment progress track (`transit.progress`, accessibility value "Click N of 20") and a ship-silhouette placeholder that moves along it, plus Skip (`transit.skip`). Skip, Return and Esc all end the playback at once. Ending the playback, or skipping it, shows the next detail mode (UI-ENC-001). The engine state is already final, so skipping changes nothing. The animated silhouette and starfield are {M11}. (source: UX-VISION §5.1)
- **UI-ENC-009** {M9} [UI] [M][W][P] During a playback, the sidebar rows, the toolbar Warp button and the Galaxy window's Warp are disabled, and the sidebar shows "In transit" (`sidebar.phaseLabel`). The step's events are already in the feed, but the arrival card and report sheets appear only when the playback ends. (source: UX-VISION §5.1, §9 "Encounter lock")
- **UI-ENC-010** {M9} [M][W][P] Dock tile progress: `DockTileProgress.fraction(playback:tick:)` (pure) returns `(20 − click) / 20` at each tick, or nil when there is no playback. The app sets `NSApp.dockTile.contentView` to the app icon with a thin progress bar, calls `display()` on every tick, and restores the plain icon when the playback ends or is skipped. Unit test on the fraction sequence. A QA-REPORT row with a screenshot is `[manual]`. (source: PRD §9 M9 "transit (Dock tile progress)")
- **UI-ENC-011** {M9} [M][W][P] While an encounter waits for the player and the app is not active, the Dock tile badge is "!" and the app requests informational attention once per encounter. The badge clears when the app becomes active or the encounter ends. `DockAttention.badge(phase:isActive:)` is pure and unit-tested. QA row `[manual]`. (source: UX-VISION §5.2; research 05 §3 "NSDockTile")
- **UI-ENC-012** {M9} [UI] [M][W][P] A `fabricRip(newDestination:)` in the step shows a banner in the Transit view ("A fracture in the space-time fabric pulls you to <system>!", `transit.fabricRip`), and the playback's destination becomes the new system. The same item is the first entry of the arrival report (ALR-165). (source: ALR-165; TRV-082)
- **UI-ENC-013** {M9} [UI] [M][W][P] A game loaded in a resting `.inTransit` phase shows the Transit view frozen at its click, with the text "Transit interrupted" and no actions other than the menus' File items. This state is unreachable through play (TRV-042) and exists so that no save can show a blank window. (source: TRV-042; UI-SHELL-009)
- **UI-ENC-014** {M9} [UI] [M][W][P] When an encounter ends and the trip continues, the detail goes Encounter → Transit (the rest of the trip) → the next encounter, arrival or report sheet, in the same order as the step's events. Two encounters in one trip each get their own Encounter view and combat log (UI-ENC-024). (source: TRV-041/042; UX-VISION §5.1, §5.2)

## 3. Encounter view

- **UI-ENC-015** {M9} [UI] [M][W][P] In `.encounter` the detail area is the Encounter view (`encounter.view`). No sheet is used. The sidebar rows are disabled and the sidebar shows "In encounter" (`sidebar.phaseLabel`). The inspector stays visible and live. The toolbar target picker and Warp are disabled. (source: UX-VISION §5.2 "the sidebar is disabled with a 'In encounter' label. No sheet is used.", §9 "Encounter lock")
- **UI-ENC-016** {M9} [M][W][P] `EncounterIntro.make(started: GameEvent, state: GameState) -> EncounterIntro` (pure) builds the header from `encounterStarted(type:opponent:clicks:playerCloaked:)`. The first line is the C# `EncounterText` "At ^1 from ^2 you encounter ^3 ^4." where ^1 is "N click(s)", ^2 the destination, ^3 the pretext and ^4 the ship name. Pretexts follow `EncounterTextInitial`: "a pirate", "a police", "a trader", "an alien" (Mantis), "a floating" (bottles), "a stolen" (Dragonfly, Scarab), "the famous Captain Ahab/Conrad/Huie in a", "a drifting" (Marie Celeste), "a police" (all police types, including `marieCelestePolice`: C# never uses `EncounterPretextMariePolice`, Game.cs:3731-3737), "the kidnappers in a" (Scorpion) and "a horrifying" (Space Monster). The second line is `EncounterActionInitial` for the type: bottle, famous captain, Marie Celeste, post-Marie police, inspection, police surrender demand, trader offer, "Your opponent attacks.", "Your opponent is fleeing.", "It ignores you.", or "It doesn't notice you." when `playerCloaked` (ENC-112). The English text equals Strings.cs:100-132, checked against fixtures copied into the test. The view shows both lines in `encounter.intro`. This replaces `EncounterText.intro`. (source: Game.cs:3426-3497, Game.cs:3701-3760 `EncounterTextInitial`; Strings.cs:100-132; ENC-112)
- **UI-ENC-017** {M9} [UI] [M][W][P] The badge (`encounter.badge`) shows `EncounterPreview.badge` (ENC-113) as a glyph plus a word: Pirate, Police, Trader, Alien, or Special. Special encounters (bottles, famous captains, Marie Celeste) get a distinct gold capsule and their custom intro (UI-ENC-016). The badge's accessibility label is the word. The vector badge glyphs are {M11}; until then SF Symbols stand in. (source: UX-VISION §5.2 "Very rare encounters … get a distinct 'special' badge", §7 "encounter badges")
- **UI-ENC-018** {M9} [UI] [M][W][P] There are two ship panes. The left one (`encounter.player`) is "You: <ship type> "<ship name>"", or the type alone when the ship is unnamed. The right one (`encounter.opponent`) is "Opponent: <ship type>". Each pane holds a placeholder portrait, `ShipPlaceholder(type:facing:)`: an SF Symbol or plain `Shape` silhouette sized by `ShipSpec.size`, facing right for the player and left for the opponent. ParsecArt replaces it in {M11} (UI-ENC-101). An opponent with `opponentDisabled` shows a "Disabled" tag (`encounter.opponent.disabled`) with a symbol. (source: UX-VISION §5.2 layout; Form_Encounter.cs:1168-1214 `UpdateShipInfo`)
- **UI-ENC-019** {M9} [UI] [M][W][P] Each pane has a hull bar and a shield bar, with the percentages from `EncounterPreview` (`playerHullPercent`, …; Form_Encounter "Hull at N%", "Shields at N%"). Each bar shows text "Hull 78%" or "Shields 40%", or "No shields" when the ship has no shield. Identifiers: `encounter.player.hull`, `encounter.player.shields`, `encounter.opponent.hull`, `encounter.opponent.shields`, with accessibility value "N%". A hull bar at 25% or below adds a warning symbol as well as the red tint. Bars animate their change in at most 0.35 s, or instantly under Reduce Motion. (source: UX-VISION §5.2, §7 "Motion"; Form_Encounter.cs:1168-1214; ENC-186)
- **UI-ENC-020** {M9} [UI] [M][W][P] Accessibility labels of the portraits: "Your <type>, hull N%, shields N%" and "<badge word> <type>, hull N%, shields N%" (plus ", disabled"). They update after every round. (source: UX-VISION §9 "Ship portraits have labels such as 'Your Gnat, hull 78%, shields 40%'")
- **UI-ENC-021** {M9} [UI] [M][W][P] The combat log (`encounter.log`) is a scrolling list. The newest entry is at the bottom, and the list auto-scrolls to it unless the player has scrolled up. Each round row starts with "R<n>" (`encounter.log.row.<index>`, index from 0). Copy (⌘C) copies the selected rows as text. Rows are text only. The log never shows hidden information (opponent crew, RNG). (source: UX-VISION §5.2 "Combat log (scrolls, newest at the bottom, round numbers)")
- **UI-ENC-022** {M9} [M][W][P] `CombatLog.lines(for step: StepRecord) -> [CombatLogLine]` (pure). It needs the `before` encounter state (`cmdrFleeing` is set by the command, `oppFleeingPrev = before.oppFleeing`, CMB-010) and the step's events. For each `combatRound(round:playerHit:opponentHit:playerHull:opponentHull:)` it emits one row "R<round>" with two sentences in C# order:
  1. The player's side: "The <ship> is still following you." if the player fled; else "You hit the <ship>." if `opponentHit`; else "You missed the <ship>.".
  2. The opponent's side: "The <ship> didn't get away." if `oppFleeingPrev`; else "The <ship> hits you." if `playerHit`; else "The <ship> missed you.".
  
  A hull loss is appended as "(−N hull)", computed from the previous hull values (`before` ship hulls, then each round's values). If the encounter continues, a stance line follows (C# `EncounterAction`): "The <ship> has been disabled.", "The <ship> hails that they wish to surrender to you.", "The <ship> is fleeing." or "The <ship> attacks.", taken from the `after` encounter state. "<ship>" is the C# `EncounterShipText` (the ship type name, or "Captain …", the police/trader/pirate noun forms of Game.cs:3639-3670). The English text equals Strings.cs:74-83 (fixture test). (source: Game.cs:3404-3423 `EncounterAction`, Game.cs:3677-3699 `EncounterText`, Game.cs:3639-3670; Strings.cs:74-83; CMB-010)
- **UI-ENC-023** {M9} [M][W][P] `CombatLog.entry(for: GameEvent, …) -> CombatLogEntry?` is an exhaustive `switch` with no `default`. It gives a line for these outcome events and `nil`, listed explicitly, for every other event:
  - `encounterChanged`: the stance text;
  - combat outcomes: `opponentDisabled`, `opponentDestroyed`, `opponentEscaped`, `playerEscaped`, `playerDestroyed`, `bothDestroyed`, `escapePodUsed`, `bountyPaid`;
  - scoop and plunder: `scooped`, `scoopNoRoom`, `plundered`;
  - police: `bribed`, `fined`, `inspectionClean`, `yielded`, `reactorConfiscated`, `arrested`;
  - pirate raids: `looted`, `blackmailed`, `sculptureTaken`, `preciousHidden`, `wildJoinedPirates`, `artifactRelinquished`;
  - very rare encounters: `tonicConsumed`, `captainTraining`;
  - trade: `orbitTradeCompleted`.
  
  The text follows ALR-012, 043, 044, 048, 049, 051, 054…057, 059, 063, 064, 074…078, 125, 166, 181 and 182. The unit test feeds one fixture per `GameEvent` case and checks that the lines are exactly those rows' events. (source: ALR §4 "combat log" rows; CMB-044…052)
- **UI-ENC-024** {M9} [M][W][P] The session keeps `encounterLog: [CombatLogLine]`. It is cleared at each `encounterStarted`, extended by UI-ENC-022/023 after every accepted step in the encounter, and frozen into the trip accumulator (UI-ENC-053) when the phase leaves `.encounter`. The log is not saved. Loading a game mid-encounter starts the log with "Encounter resumed." followed by the intro. (source: UX-VISION §5.2; UI-SHELL-008 "not persisted")
- **UI-ENC-025** {M9} [UI] [M][W][P] Each new combat-log row is announced with `AccessibilityNotification.Announcement(text)`, at most one announcement per step, combining the step's rows. Checked by an app test with an injected announcer. The VoiceOver audit is {M12}. (source: UX-VISION §9 "each new combat round is announced with AccessibilityNotification.Announcement")
- **UI-ENC-026** {M9} [UI] [M][W][P] Tribbles: when `commander.ship.tribbles > 0`, the Encounter view scatters `min(36, Int((Double(tribbles) / 74).squareRoot()))` tribble placeholders (the ENC-087 count) over the ship area. Their positions come from an app-side deterministic hash of `(state.seed, commander.days, encounter.clicks, index)`, never the game RNG (ENC-087 already made the engine's cosmetic draws). Each is a button (`encounter.tribble.<index>`, label "Tribble"); clicking it plays a 0.2 s wiggle as the visual twin of the squeak (ALR-178). The squeak sound and drawn sprite are {M11}. Unit test: the count matches the formula and the positions are stable across renders. (source: UX-VISION §5.2 "Tribbles"; ENC-087; ALR-178; Form_Encounter.cs:141-171, Form_Encounter.cs:1316-1319)

## 4. Actions, keys and the Encounter menu

- **UI-ENC-027** {M9} [UI] [M][W][P] The action bar (`encounter.actions`) holds one button per `EncounterPreview.actions` entry, in table order (ENC-130). Its identifier is `encounter.action.<EncounterAction>`. Each label is the action name followed by its key cap ("Attack  A"). The help tag is "Attack (A)", or the `ReasonText` of the preview's rejection when the button is disabled. After the type buttons come Resolve, Stop and the Auto-repeat toggle (UI-ENC-031…033). The bar is one of the two allowed custom `.glassEffect` surfaces. All buttons are disabled while `isInputLocked`. (source: UX-VISION §5.2 buttons, §7 "Liquid Glass … the Encounter action bar"; ENC-130, ENC-186)
- **UI-ENC-028** {M9} [M][W][P] `EncounterKeys.key(for: EncounterAction) -> KeyEquivalent?` and `modifiers(for:)` are pure:
  - A attack, F flee, S surrender, I ignore, B bribe, U submit, T trade, P plunder, O board, D drink, M meet, Y yield;
  - R resolve, ⌥A auto-repeat (the toggle), Esc stop;
  - `autoRepeat` (the engine tick) has no key.
  
  A unit test checks that the keys are unique, that each one equals the Encounter menu catalog entry (UI-ENC-034), and that none clashes with a ⌘/⌃ shortcut (MENU-005). (source: UX-VISION §5.2 "Keys", §10 "Encounter actions A F S I B U T P O D M Y, R = Resolve, Return = safe default, Esc = stop auto-repeat")
- **UI-ENC-029** {M9} [UI] [M][W][P] Return triggers `EncounterPreview.defaultAction` (ENC-132). Only that button carries `.keyboardShortcut(.defaultAction)`, and only while it is enabled. When the default is nil or disabled, Return does nothing. A unit test over every `EncounterType` checks that the default is never `attack`, `surrender`, `resolve` or `autoRepeat`. When the default's first confirmation is destructive (for example Yield → `surrenderToPolice`, ENC-156), the dialog's default button is Cancel (UI-SHELL Conventions). (source: UX-VISION §5.2 "Return triggers the default action, which is never destructive or illegal"; ENC-132)
- **UI-ENC-030** {M9} [M][W][P] Confirmations raised by encounter actions are presented as their ALR rows say (UI-SHELL-004, UI-SHELL-007). `ConfirmationText` additionally:
  - **Attack on police or traders:** spells out the new record from `amounts[0]` as the `PoliceRecordType` word ("Your police record will drop to Criminal.").
  - **Bribe:** states `amounts[0]` in credits.
  - **Submit (`submitInspection`):** lists what the police will find, from the pure `InspectionFindings.make(state:)`: detectable firearms and narcotics units beyond the hidden bays, Wild, the reactor and the sculpture. It also adds "You will be arrested." when Wild, the reactor or the sculpture is aboard (ENC-155).
  
  Unit tests cover each wording branch. (source: UX-VISION §5.2 "Bribe: confirmation with the amount", "Submit to inspection: confirmation that lists what will be found", "consent dialog with the consequence spelled out"; ENC-142, ENC-143, ENC-155, ENC-157; ALR-041, ALR-042, ALR-060, ALR-066)
- **UI-ENC-031** {M9} [UI] [M][W][P] Resolve (`encounter.action.resolve`, key R) is shown iff `attack` is in the preview's actions. It is enabled iff attack's preview has no rejection, and its help tag is "Attack until the encounter is resolved (R)". It sends `.encounter(.resolve)`. Any confirmation is attack's (ENC-190), and resends carry `.encounter(.resolve)` (UI-SHELL-004). The auto-repeat machine then runs the repeats (§5). (source: UX-VISION §5.2 "Resolve button: runs auto-repeat until the encounter ends (Esc stops it)"; ENC-190)
- **UI-ENC-032** {M9} [UI] [M][W][P] Stop (`encounter.action.stop`, Esc) is enabled iff `EncounterPreview.canStop` (ENC-131). It sends `.encounter(.stop)` and cancels any scheduled repeat. When Stop is unavailable, Esc in the Encounter view does nothing and never closes anything. The label is "Stop", never "Int." (ALR wording). (source: UX-VISION §5.2 "'Interrupt' becomes Stop"; ENC-131)
- **UI-ENC-033** {M9} [UI] [M][W][P] The Auto-repeat toggle (`encounter.autoRepeat`, ⌥A) is a session-only switch, `autoRepeatEnabled` (default on). It gates the app's timer and does not change the engine flags.
  - The toggle is enabled iff `state.options.continuousAttack` or the encounter's `forceContinuous` is set, because only then does the engine set a continue flag (ENC-187/190).
  - Otherwise it is disabled, with the help tag "Turn on Continuous attack in Game › Options…, or use Resolve.".
  - Turning it off cancels a scheduled repeat; the flags stay set and Stop stays available.
  - Turning it on while a flag is set schedules a repeat (UI-ENC-039).
  
  (source: UX-VISION §5.2 "☐ Auto-repeat (⌥A)", "Auto-repeat (classic 'continuous attack/flight')"; OPT-007 "setOptions only docked"; ENC-187)
- **UI-ENC-034** {M9} [UI] [M][W][P] The Encounter menu of MENU-036 adds `MenuName.encounter` and these `MenuItemID` cases:
  - `encounterAttack`, `encounterFlee`, `encounterSurrender`, `encounterIgnore`, `encounterBribe`, `encounterSubmit`, `encounterTrade`, `encounterPlunder`, `encounterBoard`, `encounterDrink`, `encounterMeet`, `encounterYield`;
  - `encounterAutoRepeat`, `encounterResolve`, `encounterStop`.
  
  Each item's identifier is `menu.encounter.<name>`, where `<name>` is the `EncounterAction` raw value or `autoRepeat`/`resolve`/`stop`, and its shortcut comes from `EncounterKeys`. Visibility and enablement are computed from `MenuContext.encounter: EncounterMenuState?` (built from `EncounterPreview` by `MenuContext.make`): an action item is shown iff its action is in the preview, and is enabled iff its rejection is nil and `!isInputLocked`. Resolve, Stop and Auto-repeat follow UI-ENC-031…033. Plain-letter shortcuts live only in this menu (MENU-037). The action-bar buttons show the key caps but register no second shortcut, except Return (UI-ENC-029). Unit tests cover `MenuContext` in each encounter fixture. (source: MENU-036, MENU-037; UX-VISION §10.1 "Encounter: enabled only during encounters. It mirrors the action bar")
- **UI-ENC-035** {M9} [M][W][P] MENU-005's hygiene test is extended. Every shortcut without ⌘ or ⌃ belongs to `MenuName.encounter`, and each Encounter item's shortcut equals `EncounterKeys`. The Encounter menu has milestone 9 and is absent before then (MENU header). (source: MENU-005, MENU-037)
- **UI-ENC-036** {M9} [UI] [M][W][P] If the state holds an unanswered decision but nothing presents it (`pendingOrbitTrade`, `pendingPlunder` or `pendingScoop` after a load, or after a dismissed sheet), the action bar is replaced by "Continue Decision" (`encounter.resumeDecision`, Return). It re-presents that decision through UI-ENC-003, so no encounter can get stuck. (source: UI-SHELL-010; ENC-191)

## 5. Auto-repeat

- **UI-ENC-037** {M9} [M][W][P] `AutoRepeatMachine` is a pure reducer: `reduce(_ state: AutoRepeatState, _ event: AutoRepeatEvent) -> (AutoRepeatState, [AutoRepeatEffect])` (effects in run order).
  - States: `AutoRepeatState.mode` is `.idle`, `.scheduled(token: Int)` or `.suspended`; the state also carries the last token and the facts rule 1 reads (switch, flag, phase, modal, playback).
  - Events: `.stepApplied(canAutoRepeat: Bool, inEncounter: Bool)`, `.presentationChanged(isModal: Bool)`, `.playbackChanged(running: Bool)`, `.toggle(enabled: Bool)`, `.manualAction`, `.escape(canStop: Bool)`, `.tick(token: Int)`.
  - Effects: `.schedule(token:, after: AutoRepeat.interval)`, `.cancel`, `.send(.encounter(.autoRepeat))`, `.send(.encounter(.stop))`.
  
  `AutoRepeat.interval` is `.milliseconds(600)`. The C# timer was 1 s. Unit tests cover every transition. (source: ENC-188; UX-VISION §5.2 "repeats every 0.6 s until the state changes or the player presses Esc"; Form_Encounter.cs:948-951, :1043-1056, :1321-1326)
- **UI-ENC-038** {M9} [M][W][P] `AutoRepeatDriver` (in `GameSession`) runs the machine's effects with an injected `any Clock<Duration>`: `ContinuousClock` in the app, and a manual test clock in tests (`TestClock` in `SpaceTraderMacTests/AutoRepeatTests.swift`). A `.schedule` starts a `Task` that sleeps on that clock and then feeds `.tick(token)`. A tick whose token is not current is ignored, so a cancelled or superseded schedule can never send. No real-time sleeps appear in tests. (source: ENC-188 "Timing is outside the engine"; PRD §6.5)
- **UI-ENC-039** {M9} [M][W][P] The machine's rules:
  1. **Scheduling.** After an accepted encounter step, a repeat is scheduled iff `encounterPreview.canAutoRepeat`, `autoRepeatEnabled`, `!isModal`, no playback is running, and the phase is still `.encounter`.
  2. **Tick.** A tick sends `.encounter(.autoRepeat)` exactly once. Its result re-enters rule 1.
  3. **Cancellation.** Leaving `.encounter`, `canAutoRepeat == false`, a manual action (any other encounter command, which also clears the engine flags, ENC-187), or turning the toggle off cancels the repeat.
  4. **Suspension.** A presentation (a confirmation, scoop, plunder or trade sheet) suspends the machine. When the presentation is dismissed and the flags are still set, the machine resumes with a full interval.
  5. **Rejection.** A rejected auto-repeat (for example `.pendingDecisionFirst`) cancels the repeat and never retries in a loop.
  
  (source: ENC-187, ENC-188, ENC-191)
- **UI-ENC-040** {M9} [M][W][P] Esc while `canStop` emits `.cancel` and `.send(.encounter(.stop))`. Esc otherwise emits nothing. A tick that arrives after Esc never sends (token rule). (source: UX-VISION §5.2 "Esc stops it", §10 "Esc = stop auto-repeat"; ENC-131)
- **UI-ENC-041** {M9} [M][W][P] Determinism test. From an encounter fixture, the test drives Resolve through the session with a `TestClock`, advancing 600 ms per tick until the phase leaves `.encounter`. The final `GameState` and the sequence of sent commands must equal a direct engine loop of `.resolve` followed by `.autoRepeat` while `canAutoRepeat` (ENC-190). A second run with Esc after the second tick must end with both flags clear and the phase still `.encounter`. (source: ENC-188 "never changes the RNG sequence", ENC-190)

## 6. Tactical readout

- **UI-ENC-042** {M9} [M][W][P] The readout comes from the engine (§15, UI-ENC-104): `GameEngine.tacticalReadout: TacticalReadout?` gives `opponentType`, its visible `weapons: [WeaponType]` and `shields: [ShieldType]` (installed equipment, which the classic opponent info shows), and `fleeOdds: FleeOdds?`. `fleeOdds` is nil when Flee is not among the actions. The app maps them with the pure `TacticalText`: the class is "<ship type> (<size>)", the equipment is "2 × Pulse laser, Energy shield" or "Unarmed", and the odds are the word "Good", "Fair" or "Poor". (source: PRD §6.6 "A tactical readout before combat shows public information only: the opponent's class and visible equipment, and your flee odds as a word"; UX-VISION §5.2)
- **UI-ENC-043** {M9} [UI] [M][W][P] The readout panel (`encounter.tactical`, with rows `encounter.tactical.class`, `.equipment` and `.fleeOdds`) is shown iff `settings.tacticalReadout` is on (UI-SHELL-100) and the player has sent no action in this encounter (encounter `round == 0` and no accepted encounter step since `encounterStarted`). It disappears after the first accepted action. Its help tag says that the odds are an estimate from public information. (source: UX-VISION §5.2 "before your first action, a small panel shows public information only"; PRD §6.6 "It is a QoL option and can be turned off")
- **UI-ENC-044** {M9} [M][W][P] The fairness test checks that `tacticalReadout` is identical for two encounter states that differ only in the opponent's crew skills, its cargo, `state.rng` or the news RNG seed. The test also checks that the readout makes no RNG draw: the state hash is unchanged. (source: PRD §6.6 "Fairness"; ENC-186 "exposes no RNG state and no opponent crew skills")

## 7. Sub-flow sheets and dialogs

- **UI-ENC-045** {M9} [UI] [M][W][P] The plunder sheet (`decision.plunder.sheet`) is titled "Plunder the <ship>", or "Marie Celeste" for a boarding. It lists the victim's non-empty cargo rows (`decision.plunder.row.<TradeItemType>`) with available units, a quantity stepper (`decision.plunder.quantity.<TradeItemType>`), Take (`decision.plunder.take.<TradeItemType>`) and Take All (`decision.plunder.takeAll.<TradeItemType>`). It shows "Free bays N" (`decision.plunder.freeBays`), and Done (`decision.plunder.done`, the default button). Take is disabled, with an inline reason, when no bay is free. Each Take sends `.plunderTake(item, quantity:)`; Done sends `.plunderDone`. The sheet stays open after each Take and updates from the new state. An empty hold shows "The hold is empty." and only Done. (source: UX-VISION §5.2 "Plunder: a sheet with the victim's cargo and quantity steppers"; ENC-158, ENC-161; Form_Plunder.cs; ALR-052, ALR-057)
- **UI-ENC-046** {M9} [M][W][P] `PlunderSheetModel.make(context:state:)` (pure, replacing `InterimDecisionModel.Plunder`) returns the rows, each with `maxTake = min(available, freeBays)`, plus the free bays and the commands. A stepper value is clamped to `1…maxTake`. Unit tests cover a full hold, partial takes and the Marie Celeste narcotics case (ENC-161). (source: ENC-158, ENC-161; CMB plunder rules)
- **UI-ENC-047** {M9} [UI] [M][W][P] The trade-in-orbit sheet (`decision.trade.sheet`) is a compact offer. It shows "The trader offers to sell/buy <item>", the unit price, the units available or held, a quantity stepper (`decision.trade.quantity`, 0…`maxQuantity`), Max (`decision.trade.max`) and the total. When the trader buys, it also shows the profit against your cost basis, per unit and in total, with a sign and ▲/▼. When the trader sells, it shows the cash after the trade. Trade (`decision.trade.accept`, the default, disabled at 0) sends `.resolveTradeInOrbit(quantity:)`; Decline (`decision.trade.decline`, Esc) sends quantity 0 (ECO-081). (source: UX-VISION §1.3 "Show the money", §5.2 "Trade in orbit: a compact offer sheet"; ECO-081; ALR-076)
- **UI-ENC-048** {M9} [M][W][P] `TradeOfferModel.make(offer:state:)` (pure, replacing `InterimDecisionModel.Trade`) gives the range, initial quantity (`maxQuantity`), total, profit per unit (`unitPrice − costBasisPerUnit`, trader-buys only) and commands. Unit tests cover both directions, a zero maximum and the profit sign. (source: ECO-081; `OrbitTradeOffer`)
- **UI-ENC-049** {M9} [UI] [M][W][P] Scoop (`Presentation.scoop(item)`) is a `confirmationDialog`: "A canister of <item> floats by." with Pick It Up (`decision.scoop.accept`, default) and Leave It (`decision.scoop.decline`), which send `.resolveScoop(accept:)` (ALR-070). When `freeCargoBays == 0`, the dialog says the hold is full and offers Make Room (`decision.scoop.makeRoom`) and Leave It (ALR-071). Make Room opens the jettison sheet (the Market disposal sheet `market.disposal.*`, presented over the Encounter view). When the jettison completes with a free bay, the scoop dialog comes back with Pick It Up. (source: ALR-070, ALR-071; UX-VISION §5.2)
- **UI-ENC-050** {M9} [UI] [M][W][P] Board (`marieCeleste`): the `boardMarieCeleste` dialog (Take Cargo / Leave It, ALR-052) and then the plunder sheet with source `.marieCeleste`. Drink and Meet: their ALR dialogs (Drink / Leave It; Trade Shield or Trade Laser / Decline, ALR-119…121). After any of these, the outcome line appears in the combat log (UI-ENC-023). (source: ENC-161…163; ALR-052, ALR-119…121)

## 8. Arrival report

- **UI-ENC-051** {M9} [M][W][P] Before sending `.warp` or `.jump`, the session captures `departureCosts: DailyCosts` from `warpTargetPreview(target).costs` (or `jumpPreview`), together with a `before` snapshot. These are the "costs paid at departure", because the engine charges exactly that preview (TRV). They are not recomputed afterwards. (source: UX-VISION §5.3 "costs paid at departure"; UX-VISION §3 "costs breakdown"; TRV-086…088)
- **UI-ENC-052** {M9} [M][W][P] `EncounterOutcome.derive(events: [GameEvent], endedBy: Command?) -> EncounterOutcome` (pure, exhaustive) summarizes one finished encounter as one of:
  - combat: `destroyed(ShipType, bounty: Int?)`, `disabled`, `escaped(wasHit:)`, `opponentEscaped`;
  - plunder and trade: `plundered([TradeItemType: Int])`, `traded(direction:item:quantity:total:)`;
  - police: `bribed(Int)`, `fined(Int)`, `inspectedClean`, `yielded`, `arrested`;
  - pirates and aliens: `raided(units:)`, `artifactSurrendered`;
  - very rare: `drank(good:)`, `trained(SkillType)`;
  - endings: `escapePod`, `killed`;
  - none of the above: `passed` (Ignore, or the opponent ignored you).
  
  Unit tests cover one fixture event sequence per case. (source: UX-VISION §5.3 "the encounters summary"; ENC-158…163, CMB-044…052, POL)
- **UI-ENC-053** {M9} [M][W][P] `TripAccumulator` is a pure fold over `StepRecord`s.
  - It starts at a step containing `departed(from:to:viaWormhole:)`, keeping `departureCosts`, the `before` state, `viaWormhole` and any `fabricRip`.
  - For each encounter it records `EncounterSummary {opponent: ShipType, badge, clicks, outcome, log: [CombatLogLine]}`.
  - It collects every non-encounter event of the trip.
  - It finishes as an `ArrivalReport` at `arrived(system:)`. An arrest, an escape pod or a game end finishes it as a report sheet or the game-over card instead.
  
  Each fixture-driven test (uneventful trip, two encounters, arrest, pod, killed) checks the fold. (source: UX-VISION §5.3; TRV-045 "`.arrived(system:)` is the last event")
- **UI-ENC-054** {M9} [M][W][P] `ArrivalReport.make(trip:after:)` builds the sections in UX order and omits empty ones:
  1. **Encounters:** one line per `EncounterSummary`, or "Uneventful trip." (ALR-168).
  2. **News:** the teaser, UI-ENC-063.
  3. **Departure costs:** mercenaries, insurance, interest and wormhole tax, each when non-zero, plus the total.
  4. **Automatic repairs and fuel:** `boughtFuel`/`repairedHull` emitted by the arrival pipeline, `autoFuelFailed` and `autoRepairFailed` (ALR-007, ALR-008, ALR-010).
  5. **Tribbles:** `tribblesChanged`, `tribblesDied`, `tribblesAteFood`, `tribbleInspectorWarning` (ALR-169, 170, 172, 174, 177).
  6. **Reactor:** `reactorWarning` (ALR-131, ALR-132).
  7. **Debt:** `debtWarning`, `debtReminder` (ALR-029, ALR-033).
  8. **Police record:** the `PoliceRecordType` word before and after the trip when it changed, `caughtLittering`, and the reputation word when it changed.
  9. **Quest progress:** quest events of the trip (`gemulonInvaded`, `experimentPerformed`, `wildLeftShip`, `easterEgg`/`easterEggNoShieldSlot` ALR-034, `passengerConcerned`/`passengerImpatient`), plus the `questLog` difference between `before` and `after` (entries added and removed, UI-SHELL-121).
  
  A fabric rip (ALR-165) is the first line of the report. Unit tests check the section order and each event's section. (source: UX-VISION §5.3 list "in order"; ALR §4 "arrival report" rows)
- **UI-ENC-055** {M9} [UI] [M][W][P] By default the report is a non-modal, expanding card at the top of Bridge (`arrival.card`).
  - **Contents:** a one-line summary ("Arrived at Rhymus · 1 encounter · −120 cr"), expanded to show the sections (`arrival.section.<encounters|news|costs|service|tribbles|reactor|debt|police|quests>`) and the encounter rows (`arrival.encounter.<index>`). Each encounter row expands to its frozen combat log.
  - **Controls:** a disclosure (`arrival.card.toggle`) and Dismiss (`arrival.card.dismiss`).
  - **Lifetime:** the card stays until dismissed or until the next departure.
  - **Selected section:** arrival never changes it. When the selected section is not Bridge, the status bar shows an "Arrival report" chip (`status.arrivalReport`) that selects Bridge.
  
  (source: UX-VISION §5.3 "By default this is a non-modal expanding card at the top of Bridge")
- **UI-ENC-056** {M9} [M][W][P] `ArrivalPresentation.decide(trip:style:)` (pure) chooses the form. It is the **report sheet** when the trip contains a critical event: `arrested`, `escapePodUsed` (which includes the insurance payoff, ALR-106), `reactorMeltdown`, or `reactorWarning` at the temperature status (ALR-133). It is also the report sheet whenever `settings.arrivalReportStyle == sheet`. It is the **game-over card** when the trip ended the game (UI-ENC-082). Otherwise it is the card. Unit test over fixtures. (source: UX-VISION §5.3 "A sheet is used only when the report contains a decision or a critical event: arrest, escape pod, insurance payoff, reactor meltdown warning or game over"; ALR §2 "GameEvent (critical)")
- **UI-ENC-057** {M9} [UI] [M][W][P] The arrival sheet (`report.sheet`, kind `arrival`) shows the same sections as the card, with Continue (`report.continue`, the default). A critical step's sheet puts its critical section first (UI-ENC-058…060), then the arrival sections. Continue dismisses it, and the card is not shown again for that trip. (source: UX-VISION §5.3; ALR §2)
- **UI-ENC-058** {M9} [M][W][P] `ReportSheet` cases are `arrival(ArrivalReport)`, `arrest(ArrestReport)`, `escapePod(EscapePodReport)` and `reactorMeltdown(ReactorReport)`. Each is built by a pure `make(before:after:events:)`. The sheet title, symbol and identifier are `report.sheet` with an accessibility value of the kind. (source: ALR-036, ALR-050, ALR-130, ALR-133)
- **UI-ENC-059** {M9} [M][W][P] `ArrestReport.make` derives one section per arrest-sequence ALR row that applies:
  - from the event: conviction with term and fine (ALR-036, ALR-108), and the ship sold for a Flea (ALR-114, ALR-093, `shipSold`);
  - from the before/after state difference (POL-093): hidden compartments removed (ALR-110), illegal goods impounded (ALR-111), insurance lost (ALR-112), mercenaries leave (ALR-113), Jarek or the Princess taken home (ALR-115, ALR-126), Wild arrested (ALR-180), the antidote taken (ALR-004), the reactor or sculpture confiscated (ALR-127, ALR-135), and tribbles removed (ALR-176).
  
  Unit tests use a fixture per section. (source: ALR-004, 036, 093, 108, 110…115, 126, 127, 135, 176, 180; POL-093)
- **UI-ENC-060** {M9} [M][W][P] `EscapePodReport.make` derives the sections: pod activated (ALR-050), the insurance payoff with its amount when > 0 (ALR-106), the Flea built (ALR-093). From the before/after state it adds: antidote destroyed (ALR-003), artifact lost (ALR-011), Jarek, the Princess or Wild taken home or arrested (ALR-115, ALR-126, ALR-180), the reactor destroyed (ALR-128), the sculpture saved (ALR-136) and tribbles killed (ALR-173). `ReactorReport` shows the meltdown (ALR-130) and then either the escape-pod sections or "Your ship was destroyed." when the game ended (handed to the game-over card). Unit tests use fixtures. (source: ALR-003, 011, 050, 093, 106, 115, 126, 128, 130, 136, 173, 180; POL-104)
- **UI-ENC-061** {M9} [UI] [M][W][P] The arrival form appears when the playback ends (UI-ENC-009), after any report sheet, and before the auto-show newspaper (UI-ENC-062). Every item is also in the feed (UI-SHELL-008), and in the Captain's Log from {M10} (UI-ENC-099). (source: UX-VISION §5.3 "Each item is also posted to the log")
- **UI-ENC-062** {M9} [UI] [M][W] Newspaper auto-show (NEWS-012). When `options.newsAutoShow` is on and the step ended with `arrived(system:)`, the session sends `.readNewspaper` after the arrival form is shown. A new game also triggers it. NEWS-004…008 apply unchanged: a rejection is shown as the status reason, a `.buyNewspaper` confirmation is the offer, and the paper opens the styled sheet. It is not available in Palm (`newsAutoShowAvailable`, NEWS-013). (source: NEWS-012, NEWS-013; Form_SpaceTrader.cs:3702-3703)
- **UI-ENC-063** {M9} [UI] [M][W][P] News teaser (`arrival.news`). When the paper for this visit is paid (`newspaperPreview != nil`), the teaser shows the first headline's text and Read (`arrival.news.read`). Otherwise it shows "The local paper costs N cr." and Read, which sends `.readNewspaper` (NEWS-007). The teaser never reveals headlines of an unpaid paper. (source: UX-VISION §5.3 "news headline teaser"; NEWS-002, NEWS-009)

## 9. Event feed

- **UI-ENC-064** {M9} [M][W][P] `FeedStyle.classify(_ entry: FeedItem.Entry) -> FeedStyle {category, severity, symbol}` (pure, exhaustive over every `GameEvent` case and `FeedNote`).
  - Categories: `trade`, `travel`, `encounter`, `combat`, `police`, `quest`, `comm`, `finance`, `crew`, `ship`, `news`, `system`.
  - Severities: `info`, `notice`, `warning`, `critical`.
  - `critical` is exactly the ALR "GameEvent (critical)" rows: `arrested`, `escapePodUsed`, `reactorMeltdown`, `reactorWarning` (temperature), `playerDestroyed`, `bothDestroyed` and `gameEnded`.
  
  Unit test: one fixture per case, and the critical set equals the ALR list. (source: UX-VISION §1.2, §6 "Outcome / info … Rare, important ones … get a dedicated report sheet"; ALR §2)
- **UI-ENC-065** {M9} [UI] [M][W][P] The feed overlay (`status.feed.list`, UI-SHELL-044) gains three behaviours:
  - Items are grouped under "Day N · <system>" headers (`status.feed.group.<day>.<systemIndex>`).
  - Consecutive `combatRound` items of one encounter collapse into one expandable row, "N rounds against the <ship>" (`status.feed.rounds.<feedID>`).
  - Each row shows its category symbol. `warning` rows add a warning symbol, and `critical` rows are bold with an exclamation symbol, so color is never the only signal.
  
  The status-bar line (`status.feed`) shows the newest item with its symbol. (source: UX-VISION §3 "Event feed: latest item", §1.7)
- **UI-ENC-066** {M9} [M][W][P] Passenger chatter (`passengerConcerned`/`passengerImpatient` for Jarek, the Princess and Wild, ALR-156…161) is posted as category `comm` with the text "Ship's comm — <name>: …". The text equals the C# alert texts (Form_Alert.cs for those types) with the names filled in. The fixture test checks all six. (source: ALR-156…161; UX-VISION §6 "passenger chatter")
- **UI-ENC-067** {M9} [UI] [M][W][P] While the Encounter or Transit view is shown, new feed items never open the overlay or take focus. The overlay can still be opened by clicking `status.feed`. (source: UX-VISION §1.2 "Never stack modal dialogs")

## 10. Newspaper

- **UI-ENC-068** {M9} [M][W][P] `NewspaperText` (replacing the interim lines) formats every `Headline` case and the masthead from the C# tables:
  - mastheads: `NewsMastheads[government][index]` with ^1 = system (Strings.cs:500-516);
  - events: `NewsEvent[rawValue]` with ^1 = commander, ^2 = current system, ^3 = ship type (Strings.cs:425-470);
  - internal pressure: Strings.cs:568-575;
  - villain and hero: Strings.cs:532-535 and 523-525, with ^1/^2;
  - moon for sale, shipyard and tribble buyer: Strings.cs:154-156;
  - external pressure: the template (Strings.cs:540-549) and pressure word (Strings.cs:552-563);
  - canned: `NewsHeadlines[government][index]` (Strings.cs:475-495).
  
  It is a `switch` without `default`. Unit tests compare every English string with the C# text, copied into the test as fixtures. (source: NEWS-014…016; Strings.cs:154-156, :425-575)
- **UI-ENC-069** {M9} [P] NEWS-047 override. Palm's distant-story template 3 reads "Sources say" where C# reads "Sources report". The choice comes from ruleset content, `ruleset.content.newsWording` (`.csharp` or `.palm`, §15 UI-ENC-106), never from the ruleset id. A unit test formats `.externalPressure(template: 3, …)` under each ruleset and checks Palm's "Sources say" and the others' "Sources report". It also checks that templates 0…2, 4 and 5 are identical across rulesets. (source: NEWS-047; Palm: Src/SystemInfoEvent.c:707-728; Strings.cs:545; CLAUDE.md "Never write `if ruleset.id == …`")
- **UI-ENC-070** {M9} [manual] [P] The NEWS-047 equality check: the Palm `Rsc` masthead lists (3 per government) and canned stories (4 per government) equal the C# arrays used by `NewspaperText`. It is checked once against the gitignored Palm source (`docs/reference/palm-src`), and the result is recorded in QA-REPORT under Accepted assumptions. Any difference becomes a `newsWording` entry. (source: NEWS-047; CLAUDE.md "Palm content")
- **UI-ENC-071** {M9} [UI] [M][W][P] The newspaper sheet (`newspaper.sheet`) is a styled broadsheet:
  - **Masthead:** the masthead in New York serif (`newspaper.masthead`), with a rule and the date line "Day N · <system> · <price> cr.".
  - **Headlines:** in serif (`newspaper.headline.<index>`), in two balanced columns when there are 4 or more, else one column.
  - **Close:** `decision.newspaper.close`, the default button and Esc.
  - **Palm:** the headlines shown are `newspaperHeadlines(measure:)` with the app's measure function (NEWS-046).
  
  The sheet reads only the `Newspaper` value it was given. The page-rustle sound is {M11}. (source: UX-VISION §4.1 "a styled broadsheet with masthead, serif headlines and columns", §7 "Newspaper headlines use New York (serif)"; NEWS-046)
- **UI-ENC-072** {M9} [UI] [M][W][P] The Bridge newspaper card (replacing the interim card of UI-SHELL-058, `bridge.newspaper`) shows the masthead when the paper is paid, else "Local newspaper" and the price. Read (`bridge.newspaper.read`) sends `.readNewspaper`. Game › Newspaper ⇧⌘N (MENU-024) does the same. The card and the menu are disabled with the reason when unaffordable (ALR-009). (source: UX-VISION §4.1; MENU-024; ALR-006, ALR-009)

## 11. Special-event narrative sheets

- **UI-ENC-073** {M9} [UI] [M][W][P] The Bridge special-event card (UI-SHELL-057, `bridge.special`) shows the title, an excerpt and the price. The excerpt is the first sentence of the story, or its first 160 characters followed by "…". The card has two buttons:
  - Read… or Accept (`bridge.special.accept`) opens the narrative sheet's offer page, Continue for a message-only event.
  - Decline (`bridge.special.decline`) hides the card until the next arrival, as in UI-SHELL-057.
  
  (source: UX-VISION §4.1 "Special event card … Opens the full narrative sheet"; UI-SHELL-057)
- **UI-ENC-074** {M9} [M][W][P] `NarrativePage` is `.offer(SpecialEventType)` or `.result(NarrativeResult)`. `NarrativeModel.offer(type:state:preview:)` (pure) returns:
  - the title (`SpecialEventText.title`) and the full story (`SpecialEventText.story`, the QST-017 C# strings, also used for Palm);
  - the price line: "Costs N cr." for a positive price, "You receive N cr." for a negative one, none for 0;
  - `messageOnly`, and a vignette kind (`planet` or `ship`, from the event's chain);
  - the Accept availability from `specialEventPreview.blocker` (UI-ENC-105).
  
  Unit test over all 46 types for Modern and the Palm subset. (source: UX-VISION §5.4 "title, illustration (procedural vignette: planet or ship), the full story text from the classic strings, price"; QST-017)
- **UI-ENC-075** {M9} [UI] [M][W][P] The offer page (`narrative.sheet`) shows:
  - the title (`narrative.title`) and the vignette placeholder (`narrative.vignette`; the procedural vignette is {M11});
  - the story in a scroll view (`narrative.story`) and the price;
  - Accept (`narrative.accept`, the default) and Decline (`narrative.decline`, Esc), or a single Continue (`narrative.continue`) for a message-only event.
  
  Accept is disabled when the preview blocker is set (insufficient funds, no free quarters, or the four rows ALR §4 marks "Accept disabled in the narrative sheet", among them ALR-152 and ALR-154). The reason appears inline under the price and in the help tag. (source: UX-VISION §5.4 "Accept / Decline. Pure messages have just Continue"; ALR §4 "inline reason (Accept disabled in the narrative sheet)")
- **UI-ENC-076** {M9} [M][W][P] Accept or Continue first dismisses the sheet, then sends `.specialEvent` with `acknowledging: [.acceptSpecialEvent]`, or with no acknowledgement for a message-only event. The sheet itself is that warning's consent, so no second dialog appears. Follow-up confirmations (Wild or reactor warnings, QST-REACTOR, QST-WILD) are presented as dialogs per UI-SHELL-004, and the acknowledged set includes `.acceptSpecialEvent`. A rejection shows the status reason. A `.confirm(.acceptSpecialEvent)` raised by any other path routes to this sheet (UI-ENC-003). A unit test runs Accept on a priced event and on Jarek with Wild aboard. (source: QST-016, QST-019; UI-SHELL-004; UX-VISION §1.2)
- **UI-ENC-077** {M9} [UI] [M][W][P] After an accepted step whose events include `specialEventCompleted(type)`, `sealedCanisters(item)` or `specialEventRefused(type, reason:)`, the result page (`narrative.sheet`, Continue `narrative.continue`) is presented when `NarrativeText.result` returns one. Otherwise the event goes only to the feed. MoonRetirement goes straight to the game-over card (UI-ENC-082, QST-015). (source: ALR §4 "narrative sheet (result page) + log"; QST-015, QST-016)
- **UI-ENC-078** {M9} [M][W][P] `NarrativeText.result(for events: [GameEvent], before: GameState, after: GameState) -> NarrativeResult?` (pure, exhaustive over `SpecialEventType`) returns a title and message for the ALR narrative rows, worded as the C# alerts with their parameters:
  - ALR-002 antidote aboard; ALR-083/084/086/087/089 equipment received;
  - ALR-129 reactor aboard; ALR-149 hull upgraded; ALR-150 record cleaned;
  - ALR-153 moon bought; ALR-162 passenger aboard;
  - ALR-163 sealed canisters, with the item; ALR-164 skill increase, naming the skill from the before/after difference;
  - ALR-171 tribbles gone; ALR-175 tribbles bought; ALR-184 Wild and the sculpture;
  - `specialEventRefused`, which names the reason (QST-SCULPTURE-011).
  
  It returns nil for every other type, and the test lists those explicitly. (source: ALR-002, 083, 084, 086, 087, 089, 129, 149, 150, 153, 162…164, 171, 175, 184; Form_Alert.cs; QST-016)
- **UI-ENC-079** {M9} [M][W][P] Coverage test: for every `SpecialEventType` in each ruleset's content, the offer page has a non-empty title and story, and `messageOnly` matches `specialEventSpec(_:).messageOnly`. For every type, `NarrativeText.result` is either a page or listed as feed-only. (source: QST-017; PRD §8.2)
- **UI-ENC-080** {M9} [UI] [M][W] Narrative content in quest flows (QST-INDEX [UI] items) comes from the QST chain events. Every chain step that the QST specs say is presented "as a narrative" reaches the result page or a comm line through UI-ENC-066/078. No chain-specific view code exists. (source: QST-016, QST-017; QST-INDEX)

## 12. Game over and the career card

- **UI-ENC-081** {M9} [M][W][P] `ScoreText.tenths(_ t: Int, ruleset: Ruleset) -> String` is the single score formatter, used by the game-over card, the retire sheet, the career card and the high-score rows. It follows SCORE-024: the integer part is grouped and both parts carry the C# sign ("-596.-9%", "0.-5%"). It follows SCORE-025 for Palm, which prints the integer part ungrouped. It replaces `GameOverModel.scoreText` and `ConfirmationText.tenths`, which used `abs`. Golden values come from SCORE-027/028. (source: SCORE-024, SCORE-025, SCORE-027, SCORE-028)
- **UI-ENC-082** {M9} [UI] [M][W][P] In `.gameOver(end)` the detail area is a full-window card (`gameOver.card`). Its content, in the SCORE-015 order:
  1. A vignette placeholder per ending (`gameOver.vignette`): destroyed, retired, moon, or moon-girl (Modern only, `.boughtMoonGirl`). The animations are {M11}.
  2. The ending title (`Names.ending`) and, for `killed`, the cause line from the final combat log entry ("Your ship was destroyed by the pirate Hornet.").
  3. "You achieved a score of X.Y%" (`gameOver.score`).
  4. The high-score outcome (`gameOver.highScore`, UI-ENC-084) with the Ironman badge and ↺ marker.
  5. The career card (`gameOver.career`, UI-ENC-083).
  6. The actions New Game… (`gameOver.newGame`, the default), Main Menu (`gameOver.mainMenu`, Close Game), High Scores (`gameOver.highScores`, which opens the scores window at the game's ruleset with the new rank highlighted) and Share (`gameOver.share`).
  
  The sidebar and toolbar are disabled (SCORE-013). (source: UX-VISION §5.5; SCORE-015; ALR-096…103; UI-SHELL-097)
- **UI-ENC-083** {M9} [M][W][P] `CareerCard.make(state: GameState, end: GameEndType, recorded: RecordedScore?) -> CareerCard` (pure, from state only, so a reopened ended save shows the same card) lists:
  - the commander and the ship type plus name;
  - the ruleset, difficulty and galaxy code (`GalaxyCode(state).string`);
  - the ending, days and worth (`GameState.worth`, RUL-119);
  - the score tenths;
  - the police record and reputation words;
  - kills of pirates, police and traders, and their total;
  - the cash and debt at the end;
  - badges: "Ironman", "↺ reloaded" (`reloadCount > 0`) and "Cheats used" (`cheatsUsed`).
  
  Unit tests per ending and ruleset. Feed- or log-based totals (encounters won, best trade) are {M10} (UI-ENC-099). (source: UX-VISION §5.5 "a career summary card"; SCORE-029; PRD §8.3)
- **UI-ENC-084** {M9} [M][W][P] `HighScoreOutcomeText.text(for: RecordedScore?, entry: HighScoreEntry)` (exhaustive) gives:
  - "You entered the high-score table at rank N." (ALR-098);
  - "Your score didn't make the high-score table." (ALR-100);
  - the cheats exclusion (ALR-099), the Palm reload exclusion (SCORE-035), "already recorded" and "couldn't be updated".
  
  It appends "Ironman" and "↺" when the entry carries them. `.alreadyRecorded` (a reopened ended save, SCORE-037) shows the rank if the entry is still in the table. (source: ALR-098…100; SCORE-035…037)
- **UI-ENC-085** {M9} [UI] [M][W][P] Share uses `ShareLink` with a `Transferable` PNG of the career card. The image is rendered by `ImageRenderer` at scale 2 from the same `CareerCardView`, with no window chrome, and the preview title is "Parsec Merchant — <commander>". An app test renders the image and checks it is non-empty and deterministic for a fixture state. (source: UX-VISION §5.5 "can be shared with ShareLink as an image")
- **UI-ENC-086** {M9} [UI] [M][W][P] A game that ends during an encounter (`playerDestroyed` or `bothDestroyed`) shows the round's combat-log line first, then the game-over card without a playback. A reactor meltdown with no pod goes to the reactor report (UI-ENC-060) and then the card. A moon retirement from the narrative flow goes straight to the card. Every path records the high score once (SCORE-037). (source: ALR-043, ALR-077, ALR-128, ALR-130; SCORE-012, SCORE-037)

## 13. High scores window

- **UI-ENC-087** {M9} [UI] [M][W][P] `Window(id: "scores")` (`scores.window`) has a default size of 560×520 and is opened by Window › High Scores (MENU-038) and by `gameOver.highScores`. It works with no game loaded. A segmented picker chooses the ruleset (`scores.ruleset.<RulesetID>`). It defaults to the current or just-ended game's ruleset, else the last one viewed (`UserDefaults` key `scores.ruleset`). (source: UX-VISION §2 "High Scores | Window(id: "scores") | Top 10 per ruleset"; UI-SHELL-014; SCORE-030)
- **UI-ENC-088** {M9} [M][W][P] `HighScoreRowModel.rows(table: HighScoreTable, ruleset: Ruleset) -> [HighScoreRow]` (pure) always returns `HighScoreTable.capacity` (10) rows, one per rank. Each filled row has the rank, the name, `ScoreText.tenths` and the SCORE-039 line: "<ending> in <N day(s)>, worth <N credit(s)> on <difficulty> level.", with "Was killed", "Retired", "Claimed moon", or the Modern moon-girl string. It also carries the Ironman and ↺ flags. Empty ranks read "Empty". Unit tests cover plural variants, a negative score (SCORE-024) and a Palm row (SCORE-025). (source: SCORE-039; Form_ViewHighScores.cs:64-79; Strings.cs:141, :404-410)
- **UI-ENC-089** {M9} [UI] [M][W][P] Each table row (`scores.row.<rank>`) shows the rank, name, score and line, plus the Ironman badge (`scores.row.<rank>.ironman`) and ↺ marker as symbol and text. The rank just entered by the current game is highlighted, by accent and an accessibility value "new". The window reloads from `HighScoreStore` when it opens, after each recording and after Settings › Clear High Scores (UI-SHELL-101). (source: SCORE-037…039; UX-VISION §5.5 "with Ironman and ↺ markers")

## 14. Developer tester, scenario and UI flow 2

- **UI-ENC-090** {M9} [M] `PirateAmbushScenario.make() -> GameEngine` (pure, app target) builds the `-PMScenario pirateAmbush` state by play.
  1. It starts with `GameEngine(config: NewGameConfig(commanderName: "Ambush", difficulty: .normal, skills: [5, 5, 5, 5], ruleset: .modern, seed: UITestFixtures.ambushSeed))`.
  2. It performs `.cheat(.enable)` and `.cheat(.iron(slot: 0, weapon: 2))` (a military laser; CHEAT-026). Neither draws RNG (CHEAT-006).
  3. It performs `.selectTarget(UITestFixtures.ambushTarget)`.
  
  The scenario runner then installs the engine and sends `.warp` through `GameSession.send`, so the encounter, playback and log follow the normal path. The game has `cheatsUsed = true` (CHEAT-049). (source: PRD §8.2 flow 2 "`-PMScenario pirateAmbush`, attack until resolved"; CHEAT-006, CHEAT-026, CHEAT-049)
- **UI-ENC-091** {M9} [M] The constants are valid. An app unit test (`PirateAmbushScenarioTests`) checks that from `PirateAmbushScenario.make()`:
  - `.warp` ends in `.encounter` with type `.pirateAttack`, `badge == .pirate` (not a Mantis), and the step's first `encounterStarted`;
  - repeating `.encounter(.attack)`, with no acknowledgements needed, ends the encounter within `UITestFixtures.ambushMaxAttacks` (≤ 30) commands with `opponentDestroyed`, never with `playerDestroyed`, `escapePodUsed` or a `.scoop` decision;
  - the step that ends the encounter docks at `ambushTarget` with `arrived` and no further encounter;
  - the exact attack count equals `UITestFixtures.ambushExpectedAttacks`.
  
  The constants are found once by a search over seeds and targets, and recorded in `UITestFixtures` and in the PROGRESS decisions log. Combat draws depend only on state, so the UI flow takes the same path. (source: PRD §8.2 flow 2; UI-SHELL-129 pattern; MAP-100)
- **UI-ENC-092** {M9} [UI] [M][W] Developer tester (CHEAT-038). In Debug builds `.cheat(.test)` opens `SheetRoute.developerTester` (`devTester.sheet`). It lists every `ALRCatalog` row (`devTester.alr.<number>`) and every special-event narrative page (`devTester.narrative.<SpecialEventType>`). Choosing one presents that presentation with fixture values (`ALRCatalog.sample(for:)`, the same fixtures as UI-ENC-004), without touching the game state. In Release builds it only shows the cheat console. (source: CHEAT-038; Form_Test.cs:263-292)
- **UI-ENC-093** {M9} [UI] [M][W][P] `ScenarioRunner.run` gains non-exiting scenarios: `pirateAmbush` returns nil (the app keeps running) after installing the game. `smoke` and unknown names keep their exit codes (CHEAT-049). Scenarios are Debug-only except `smoke` (CHEAT-047). `-PMSeed` is ignored by named scenarios, and `-PMResetState` runs first (CHEAT-051). The scenario game is written by the normal persistence triggers. (source: CHEAT-047…051; AppDelegate.swift `ScenarioRunner`)
- **UI-ENC-094** {M9} [UI] [M] **Flow 2: `-PMScenario pirateAmbush`, attack until resolved.** Steps:
  1. Launch with `-PMResetState -PMScenario pirateAmbush -PMFastTravel -PMAudio off`. `encounter.view` appears with no interaction.
  2. `encounter.badge`'s label is "Pirate". `encounter.intro` contains "pirate". `encounter.player.hull` and `encounter.opponent.hull` exist with "%" values. `encounter.action.attack`, `encounter.action.flee`, `encounter.action.surrender` and `encounter.action.resolve` exist. `encounter.tactical` exists and contains "Flee". `sidebar.phaseLabel` reads "In encounter", and `sidebar.market` is disabled.
  3. The Encounter menu item `menu.encounter.attack` exists and is enabled.
  4. Press the key A. Row `encounter.log.row.0` appears and starts with "R1", and `encounter.tactical` disappears.
  5. Click `encounter.action.attack` while `encounter.view` exists, at most `ambushMaxAttacks` times in total.
  6. `encounter.view` disappears. `arrival.card` appears, and `arrival.encounter.0` contains "destroyed". The window subtitle shows the target's name and "Day 1".
  7. `menu.encounter.attack` is disabled or absent, and `sidebar.market` is enabled again.
  
  Run by `verify.sh --ui`. (source: PRD §8.2 flow 2, §9 M9 "--ui flow 2 green")
- **UI-ENC-095** {M9} [UI] [M][W][P] Flows 1, 3 and 5 stay green with the M9 surfaces: with `-PMFastTravel` the playback is instant, and an uneventful arrival shows `arrival.card` without changing the selected section (UI-ENC-055). Flow 5's check of `galaxy.system.<target>` after ⌘J still runs on the Galaxy section. (source: UI-SHELL-124, UI-SHELL-125, MAP-101)
- **UI-ENC-096** {M9} [UI] [M][W][P] The identifier walk (UI-SHELL-127, MAP-104) is extended to the Encounter view, the Transit view, the plunder, trade, newspaper, narrative and report sheets, the arrival card, the game-over card and the High Scores window. The flow-2 scenario reaches the encounter and arrival surfaces. The other sheets are reached by Debug-only fixture scenarios (`-PMScenario encounter:<EncounterType>`, `-PMScenario specialEvent`) and the Transit view by a warp without `-PMFastTravel` and with `-PMSlowTravel 20` (24 s instead of 1.2 s, so the snapshot does not race the playback, CHEAT-050); SwiftUI builds no accessibility tree for a view hosted in a unit-test window, so the walk runs under UI automation. Every interactive element must have an identifier matching the scheme. (source: PRD §6.5; UI-SHELL-127)
- **UI-ENC-097** {M9} [M][W][P] Every new identifier of §17 is an `AXID` constant, unique, and matches `^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$` (UI-SHELL-128 test over `AXID.all`). The UI-test target mirrors those used by flow 2. (source: UI-SHELL-128)

## 15. Engine additions (pure; package tests)

- **UI-ENC-104** {M9} [M][W][P] `GameEngine.tacticalReadout: TacticalReadout?` is nil outside `.encounter`.
  - **Fields:** `opponentType`, `weapons` and `shields` (the opponent's installed `WeaponType`/`ShieldType` in slot order) and `fleeOdds`.
  - **Odds:** `fleeOdds` is the CMB-049 escape probability for one Flee round. With `D == Beginner` it is 1. Otherwise it is the exact fraction of `(a, b)` pairs, `a ∈ 0..<7` and `b ∈ 0..<P_opp`, with `(a + P_player/3) × 2 ≥ b × (2 + D)`. Here `P_player` is the player's effective pilot skill (CRW-011/013), and `P_opp` is averaged over the opponent's possible pilot values: the fixed table value for famous captains, quest ships and bottles (ENC-080…082), else uniform `1…10` (ENC-070…073). Each value goes through the same effective-skill function with the opponent's visible gadgets.
  - **Word:** `FleeOdds` is `.good` (≥ 2/3), `.fair` (≥ 1/3) or `.poor`. It is nil when Flee is not offered.
  - **Purity:** the query makes no RNG draw and never reads the opponent's actual crew.
  
  Tests: brute-force enumeration equals the closed form for all pilot values and difficulties, the Beginner case gives `.good`, and the readout is pure (state unchanged). (source: PRD §6.6 "tactical readout … your flee odds as a word"; CMB-049; ENC-186)
- **UI-ENC-105** {M9} [M][W][P] `GameEngine.specialEventPreview: SpecialEventPreview?` returns `{type, price, messageOnly, blocker: CommandError?}` for `state.specialEventAvailable`. `blocker` is the rejection `perform(.specialEvent, acknowledging: [.acceptSpecialEvent])` would return (insufficient funds, no free slot, quarters or bays, Wild's refusals, QST-010), computed on a copy. The Reactor and Wild follow-up consents are not blockers. Test: for fixture states triggering each refusal, `blocker` equals the command's rejection, and the state is unchanged. (source: QST-007, QST-010, QST-016; UI-SHELL-115 pattern)
- **UI-ENC-106** {M9} [M][W][P] `ContentPacks.newsWording: NewsWording` (`.csharp` for Modern and Windows 2.01, `.palm` for Palm 1.2.2) selects the NEWS-047 wording. It is content data with no behaviour in the engine, so the app's formatter (UI-ENC-069) never tests `ruleset.id`. A test checks the value per ruleset. (source: NEWS-047; PRD §4.1 "content packs"; RUL-001)

## 16. Later milestones (listed so nothing is lost; not M9 exit criteria)

- **UI-ENC-098** {M11} [UI] [M][W][P] ParsecArt and motion in encounters:
  - vector ship portraits (`ShipArt`) replace `ShipPlaceholder`, with a shield bubble whose opacity tracks the shield percentage and a live scorch mask whose coverage equals the hull loss;
  - laser beams, shield ripples, hull sparks and screen shake on heavy hits (a hull loss ≥ 15% in one round), each replaced by a 0.2 s color flash under Reduce Motion;
  - the vector badge glyphs, the transit silhouette with starfield, the narrative vignettes, the game-over cinematics (wreck, sunset, moon villa, moon-girl) and the drawn tribble sprites.
  
  (source: UX-VISION §5.1, §5.2 "Animation", §5.4, §5.5, §7 "Art"; ART)
- **UI-ENC-099** {M10} [M][W][P] Logbook integration: every arrival-report item, encounter summary, combat outcome, narrative result, newspaper read and game end is written to the Captain's Log (LOG). The feed overlay gains "Show Logbook". The career card adds STAT totals (encounters won, fled and surrendered, best trade, systems visited). Achievements observe these events (ACH, disabled for cheated games, CHEAT-004). Arrival summaries may use template or Foundation Models flavor (LLM; identical behaviour under `-PMFlavor template`). INT may extend the tactical readout with intel. (source: UX-VISION §4.9, §4.10, §5.3 "Each item is also posted to the log"; PRD §6.6)
- **UI-ENC-100** {M11} [M][W][P] Audio and haptics through `ParsecAudio` and `SessionHaptics`:
  - pulse, beam and military laser timbres; shield hit; hull hit; explosion; the low-hull alarm (≤ 25%); the arrest siren; the newspaper page rustle; the transit whoosh; the tribble squeak;
  - `.levelChange` haptics on heavy hits.
  
  Each cue has the visual twin specified here (bars, flash, report sheet, wiggle). (source: UX-VISION §8, §9 "Audio cues … have a visual twin"; AUD)
- **UI-ENC-101** {M11} [UI] [M][W][P] `ShipPlaceholder` is removed, and an art test renders every `ShipType` portrait in both facings via `ImageRenderer` with non-empty, deterministic output (PRD §8.2 "Art"). (source: PRD §8.2; ART)
- **UI-ENC-102** {M12} [UI] [M][W][P] Accessibility and polish of the M9 surfaces:
  - Flow 6 walks the Encounter view, sheets, game-over card and High Scores window with `performAccessibilityAudit()`. Flow 7 checks them at the largest Text Size and minimum window size without clipping.
  - Full keyboard traversal with visible focus rings.
  - Increase Contrast bar strokes, Differentiate Without Color shapes on bars and badges, and Reduce Transparency on the action-bar glass.
  - VoiceOver announcement wording review (UI-ENC-025), the UI-KEYS audit of the encounter keys, and localization completeness of every string added here.
  
  (source: PRD §9 M12; UX-VISION §9; A11Y, UI-KEYS)
- **UI-ENC-103** {M12} [manual] [M][W][P] README screenshots of an encounter, the arrival card, the newspaper and the game-over card (`PM_EXPORT_SCREENSHOTS=1`, using the pirateAmbush scenario). (source: PRD §9 M12)

## 17. Identifier catalog (extend, never rename)

| Area | Identifiers |
|---|---|
| Shell | `sidebar.phaseLabel`, `status.arrivalReport`, `status.feed.group.<day>.<systemIndex>`, `status.feed.rounds.<feedID>` |
| Transit | `transit.view`, `transit.progress`, `transit.skip`, `transit.fabricRip` |
| Encounter | `encounter.view`, `encounter.intro`, `encounter.badge`, `encounter.player`, `encounter.player.hull`, `encounter.player.shields`, `encounter.opponent`, `encounter.opponent.hull`, `encounter.opponent.shields`, `encounter.opponent.disabled`, `encounter.log`, `encounter.log.row.<index>`, `encounter.actions`, `encounter.action.<EncounterAction>` (incl. `resolve`, `stop`), `encounter.autoRepeat`, `encounter.resumeDecision`, `encounter.tactical`, `encounter.tactical.class`, `encounter.tactical.equipment`, `encounter.tactical.fleeOdds`, `encounter.tribble.<index>` |
| Encounter menu | `menu.encounter.<attack/flee/surrender/ignore/bribe/submit/trade/plunder/board/drink/meet/yield>`, `menu.encounter.autoRepeat`, `menu.encounter.resolve`, `menu.encounter.stop` |
| Decisions | `decision.plunder.sheet`, `decision.plunder.row.<TradeItemType>`, `decision.plunder.quantity.<TradeItemType>`, `decision.plunder.take.<TradeItemType>`, `decision.plunder.takeAll.<TradeItemType>`, `decision.plunder.freeBays`, `decision.plunder.done`, `decision.trade.sheet`, `decision.trade.quantity`, `decision.trade.max`, `decision.trade.accept`, `decision.trade.decline`, `decision.scoop.accept`, `decision.scoop.decline`, `decision.scoop.makeRoom` |
| Arrival, reports | `arrival.card`, `arrival.card.toggle`, `arrival.card.dismiss`, `arrival.section.<encounters/news/costs/service/tribbles/reactor/debt/police/quests>`, `arrival.encounter.<index>`, `arrival.news`, `arrival.news.read`, `report.sheet`, `report.continue` |
| Newspaper | `newspaper.sheet`, `newspaper.masthead`, `newspaper.headline.<index>`, `decision.newspaper.close`, `bridge.newspaper`, `bridge.newspaper.read` |
| Narrative | `narrative.sheet`, `narrative.title`, `narrative.vignette`, `narrative.story`, `narrative.accept`, `narrative.decline`, `narrative.continue`, `bridge.special`, `bridge.special.accept`, `bridge.special.decline` |
| Game over | `gameOver.card`, `gameOver.vignette`, `gameOver.score`, `gameOver.highScore`, `gameOver.career`, `gameOver.newGame`, `gameOver.mainMenu`, `gameOver.highScores`, `gameOver.share` |
| High scores | `scores.window`, `scores.ruleset.<RulesetID>`, `scores.row.<rank>`, `scores.row.<rank>.ironman` |
| Developer | `devTester.sheet`, `devTester.alr.<number>`, `devTester.narrative.<SpecialEventType>` |

Retired with the interim surfaces: `encounter.panel` (UI-SHELL-010). `AXID.Interim` is split into `AXID.Encounter`, `AXID.Decision` and `AXID.Transit`; the kept strings are unchanged.

## 18. Notes and open questions

- **Replaces** UI-SHELL-010 and UI-SHELL-011 (interim encounter panel and decision sheets), the interim newspaper card of UI-SHELL-058, and the minimal game-over card of UI-SHELL-097. UI-SHELL-005/006 gain the cases of UI-ENC-002/003, and `SheetRoute.encounterInterim` is removed.
- **Interval**: the auto-repeat interval is 0.6 s (UX-VISION) against 1 s in C# (Form_Encounter.cs:950). ENC-188 already records this deviation. It is timing only.
- **Auto-repeat toggle semantics** (UI-ENC-033). Options are docked-only (OPT-007), so ⌥A cannot switch the engine's `continuousAttack` during an encounter. It gates the app timer instead and is disabled when the engine will never set a continue flag. *Open question for the owner*: should ⌥A instead be removed, leaving Resolve plus Game › Options as the only controls?
- **Flee-odds estimate** (UI-ENC-104). The opponent's real pilot skill is hidden information (ENC-186), so the odds average over the generator's distribution. *Open question*: are the word thresholds of 1/3 and 2/3 right, and should famous captains (whose fixed 10/10/10/10 crew is table data, not hidden) use the exact value, as specified?
- **Combat-log wording** reuses the C# encounter strings (Strings.cs:74-132) instead of the UX-VISION mock ("The Hornet fires — hit! −18 hull"). The mock's hull-delta suffix is kept as "(−N hull)".
- **Narrative consent**: the narrative sheet acts as the `acceptSpecialEvent` consent (UI-ENC-076), so Accept never stacks a second dialog. A follow-up Wild or reactor warning is still a dialog, after the sheet closes.
- **Arrival and section**: the arrival card never changes the selected section (UI-ENC-055), so map-driven travel (flow 5) is not interrupted. The status-bar chip leads to Bridge.
- **Scenario constants**: `ambushSeed`, `ambushTarget`, `ambushExpectedAttacks` and `ambushMaxAttacks` are found at implementation time by a search (UI-ENC-091) and recorded in `UITestFixtures` and PROGRESS. They are not hand-picked here, because the military-laser cheat changes worth and therefore the opponent generation.
- **Score display fix**: UI-ENC-081 replaces two `abs`-based formatters that disagreed with SCORE-024's negative-score quirk.
- **ID ranges**: §15 uses UI-ENC-104…106 and §16 uses UI-ENC-098…103. IDs were assigned per section and are not renumbered.
