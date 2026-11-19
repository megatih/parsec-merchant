# UI-NAV: navigation, pages and fair information

> Format (PRD §7): `- **ID** {Mn} [UI] [M][W][P] statement`. `[M]` Modern, `[W]` Windows 2.01, `[P]` Palm 1.2.2. `[UI]` = verified by app tests hosted in the app or by XCUITest.
> Milestones: M18–M28 (`docs/PRD-UI-Revamp.md` §7). The first number on the PROGRESS status line is the last finished milestone; an ID becomes due when its milestone is finished.
> Normative input: `docs/PRD-UI-Revamp.md` §4.1, §4.4–4.16, which holds the wireframes, tables and reasons. These bullets are the testable statements; where a bullet and the PRD differ, fix the bullet.

## UI-NAV

- **UI-NAV-001** {M21} [UI] [M][W][P] The shell is `dock bar / status bar / game area` in a plain `VStack`; nothing is pinned to the bottom edge of the window. `NavigationSplitView`, the sidebar, the inspector and the toolbar are removed. `Section` has the cases `bridge, shipyard, outfitter, crew, bank, status, quests, galaxy, logbook` in dock order: the 1.x case names and raw values are kept (they are stored in scene state and are part of the accessibility identifiers), and the page titles carry the game's vocabulary (Equipment, Personnel, Galactic Chart; UI-PG). Options is the dock bar's last button and opens the options (it is not a `Section`). A stored `market`, or anything unknown, restores to `bridge`.
- **UI-NAV-002** {M21} [UI] [M][W][P] The dock bar shows all ten buttons at every window size, each with symbol, label and key cap on one line; the current page's button is marked by `accent` underline **and** a filled symbol (not colour alone). Badges: Personnel shows the number of mercenaries for hire here; Quests shows the number of open quests with a deadline of 5 days or less.
- **UI-NAV-003** {M21} [UI] [M][W][P] Esc on a secondary page returns to the Bridge (after the existing Esc router levels: clear a field, close an overlay). Every secondary page has a visible "Bridge" back button at the left of its title row with help tag "Return to the Bridge (Esc)".
- **UI-NAV-004** {M21} [UI] [M][W][P] After a warp ends (arrival), after a game loads and after New Game, the page is the Bridge. This replaces UI-ENC-055.
- **UI-NAV-005** {M21} [UI] [M][W][P] During transit and encounters every dock button is disabled with the help tag "Unavailable in transit" / "Unavailable during an encounter"; the status bar stays live.
- **UI-NAV-006** {M21} [UI] [M][W][P] A page never opens another page except through: the dock bar, a menu command, Back, or a control whose label or help tag names the destination page (for example "Insurance in Bank…", or the Bridge's Hire notice, which opens the Crew page). A link changes the page; it never also changes the target or other game state, except "Show on Galactic Chart", which selects that system on the chart.
- **UI-NAV-007** {M23} [UI] [M][W][P] The window title is "Cmdr. ‹name›" and the subtitle is the page name (the HIG says not to title a window with the app name). Cash, day and system are no longer in the subtitle (they are in the status bar).
- **UI-NAV-008** {M24} [UI] [M][W][P] The separate Galactic Chart window (⇧⌘M) stays, with the same content as the page.
- **UI-NAV-009** {M21} [UI] [M][W][P] With no game loaded the window shows the Welcome view with no status bar or dock bar.
- **UI-NAV-010** {M23} [UI] [M][W][P] A dock button whose page has nothing to offer here is still enabled and the page says why (for example Shipyard in a system that sells no ships shows the escape pod, the designer if a yard is present, and a `PMEmptyState` "No ships for sale in this system"). Content availability comes from the engine previews and `Ruleset` tables.

## UI-PG

- **UI-PG-001** {M23} [UI] [M][W][P] Every secondary page is a `PMPage`: Back button, title in `title` style, optional page actions at the right, then panels. Content width is capped at 1400 × `s` and centred. A page's content may scroll vertically as a whole only if its content cannot fit (lists such as the Logbook); panels themselves do not scroll, except list panels named below.
- **UI-PG-002** {M23} [UI] [M][W][P] Each page opens with keyboard focus on its first control, restores its last selection during a session, and has an identifier `page.‹name›`.
- **UI-PG-003** {M23} [UI] [M][W][P] Every page reads its content from the existing `…Model.make(state:)` types; a page shows only what its engine preview offers under the active ruleset (for example the Designer panel appears only when `designQuote` is available here).
- **UI-PG-010** {M23} [UI] [M][W][P] Selecting is one click; buying is the button; double-click is only an accelerator. The Compare toggle is removed (the comparison is always shown).
- **UI-PG-020** {M23} [UI] [M][W][P] Buy and Sell are buttons; drag and drop stays as an accelerator. The 280 pt detail form is removed; item details are in each row and its help tag.
- **UI-PG-030** {M23} [UI] [M][W][P] Police Record, Reputation and kills are removed from this page (they are on Commander Status).
- **UI-PG-040** {M23} [UI] [M][W][P] The page shows every field the 1.1.0 inspector showed (a test compares against `InspectorModel`). The "Show Commander Status" App Intent opens this page.
- **UI-PG-050** {M23} [UI] [M][W][P] Options that a ruleset does not have are not shown; the list comes from the ruleset's option flags.
- **UI-PG-060** {M24} [UI] [M][W][P] Clicking a system selects it and fills the Selected System panel, including the ten average prices from `TradeIntel.quote` with their tags (this replaces the "Find Prices" sheet and the pinned card). **Set as Target** changes the Target System; selecting alone does not. (This differs from the Short-Range Chart, where one click sets the target, because the Galactic Chart is for looking around.)
- **UI-PG-061** {M24} [UI] [M][W][P] One search: the Find System sheet (⌘F everywhere, ⌥⌘F kept as an alias). The inline map search is removed; the filters stay in the left panel. The cheat-code entry through Find stays.
- **UI-PG-062** {M24} [UI] [M][W][P] Wormholes, tracking (Track / Stop Tracking button, and ⌥-click as an accelerator), Plot Route, heatmaps, legend, zoom, the singularity **Jump…** button (only where the engine offers it) and the keyboard map keys keep their behaviour.
- **UI-PG-063** {M24} [UI] [M][W][P] MAP-097 and the intel fairness tests stay green unchanged.
- **UI-PG-070** {M26} [UI] [M][W][P] After M26 no view under `APP/Views/` uses a pre-revamp container or style (the audits UI-DS-021…023 enforce this at M27; M26 removes the last users).

## UI-NAV

- **UI-NAV-011** {M27} [UI] [M][W][P] The menu bar matches this table; single-letter Trade keys act only when no text field has focus and the Bridge is the page. `KeyAudit` finds no conflict. The Help "Keyboard Shortcuts" page is generated from `KeyBindingTable` as today.
- **UI-NAV-012** {M27} [UI] [M][W][P] Help pages (`APP/Resources/Help/*.md`) are rewritten for the new screens and vocabulary; `l10n-check.sh` still requires one page per `HelpTopic`.

## UI-FAIR

- **UI-FAIR-001** {M22} [M][W][P] Source audit over `APP/Views/`, `APP/Design/` and `APP/Session/*Models.swift`: for systems other than the current one, views read only through `IntelSnapshot`, `IntelBook`, `TradeIntel`, `warpTargetPreview`, `dailyCosts(to:)` and the existing map snapshot. The identifiers `.pressure`, `.specialResource`, `.tradeItems`, `.countDown`, `.specialEvent` and `.newspaper` (as opposed to `newspaperPreview`) do not appear in those files except on `currentSystem` in an allowlist kept in the test.
- **UI-FAIR-002** {M22} [M][W][P] The existing fairness tests (INT-001…023, MAP-097) stay unchanged and green.
