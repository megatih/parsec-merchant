# Changelog

All notable changes to Parsec Merchant are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/) and versions follow [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-11-20
A new interface built around one screen. The rules, formulas, data, saves and scores are unchanged; the game shows only what it showed before.

### Changed
- **The Bridge is the whole trade loop.** System Information, the Cargo market, the Short-Range Chart and the Target System are on screen together at every window size, with no scrolling and nothing collapsed. Selling a hold, buying, refuelling, comparing two destinations and warping take six clicks on one page.
  - Cargo: one row per good with what you hold and paid, the prices here and at the target, and the profit per unit; a Quantity field with Buy, Max, Sell and All; Sell All Cargo; Price Details… for any good.
  - The target's prices are the game's own estimates or prices you remember, shown with their age.
- **Dock bar and status bar** replace the sidebar, the toolbar and the inspector. The dock bar opens Bridge, Shipyard, Equipment, Personnel, Bank, Commander Status, Quests, Galactic Chart, Logbook and Options; the status bar always shows the system, day, cash, debt, bays, fuel, hull, shields and the latest event. Esc returns to the Bridge.
- **Every page is rebuilt** on one dark console design with shared components: Shipyard, Equipment (was Outfitter), Personnel (was Crew), Bank, Commander Status (was the inspector), Quests, Logbook and Options (now a page).
- **Galactic Chart:** a Selected System panel beside the chart shows a system's facts and known prices with Set as Target, Track and Plot Route. Find System is the one search; ⌘0 fits the range.
- **Encounters:** two large ship panels, a role badge (Police, Pirate, Trader, Alien, Special), a full-width action bar with key caps above the combat log. Plunder, Trade in Orbit and Make Room list one good per row with Quantity, Max and All.
- **Ships:** ten class designs, each with its own silhouette and shaped by its statistics; police, pirate and trader liveries; visible weapons, shields and gadgets; an opponent never looks like your own ship.
- **Portraits:** illustrated faces for the commander, every mercenary and the famous captains replace the helmet avatars.
- **Endings:** the four ending scenes are redrawn: your own ship in orbit at sunset, on the landing pad of your moon base (with a second ship and a second lit window when the princess is with you), or broken up among its debris.
- **Menu bar:** a Trade menu (Buy, Buy Maximum, Sell, Sell All, Sell All Cargo, Dump…, Price Details…, Buy Fuel…, Fill Tank, Repair…, Repair Hull); Options and Recent Events (⌘E) in View; Find System… is ⌘F.
- **Keyboard:** the whole trade loop works without the pointer (arrows, B, S, ⇧B, ⇧S, ⌥⌘S, ⇧⌘F, ⌘[ ⌘], ⌘J). Buttons show their keys.
- **Window:** the minimum is 1200 × 680 points; the interface scales with the window, and the Text Size setting raises the scale in five steps.
- **Words** follow the original game: Equipment, Personnel, Galactic Chart, Commander Status, Fill Tank.
- Help pages are rewritten for the new screens.

### Removed
- The sidebar, the toolbar, the inspector, the separate Market page, the System Intel sheet, the chart's inline search field and all Liquid Glass surfaces in the game area.

## [1.1.0] - 2026-11-19
Realistic art and a pointer- and touch-first interface. The rules, saves and scores are unchanged.

### Changed
- **Planets** are no longer flat drawings. Each world is baked from seeded noise and projected onto a sphere, with a day and night side, an atmosphere, clouds with shadows, an ocean glint, city lights and, for some, rings.
  - Ten classes: terran, ocean, desert, ice, jungle, rocky, barren, volcanic, toxic and gas giant. A known special resource decides the class, so the picture is truthful.
  - The Bridge planet is a large hero that turns live (one turn per 24 seconds) in front of the system's star; it is a still picture under Reduce Motion.
- **Ships** are generated from their statistics instead of drawn after their names: cargo bays, weapon, shield and gadget slots, crew quarters, fuel, hull strength, price and tech level shape the hull. Freighters carry containers, warships show hardpoints, expensive ships are sleeker, and installed weapons and shields are visible. No ship looks like an insect any more.
  - Ship pictures use the room they have: Shipyard cards, the inspector, the designer, the purchase sheet, the comparison, encounters and transit.
- **Endings** are scenes lit by a sun: an orbital sunset for retirement, a cratered moon with a glass dome, and your own ship tumbling among hull plates.
- **The app icon's** freighter is the generated one.
- **Pointer and touch first.** Every action is discoverable and quick with a pointer or a finger; the keyboard is still a complete second path and no shortcut changed.
  - Market: quantity chips (1, 5, 20, Max) with Buy and Sell on every row, a visible Jettison or Dump button and a full context menu. In a narrow table Stock and P/L move under the buy price and the held count, so the actions stay on screen.
  - Shipyard: a Compare toggle on each card; double-click opens the purchase review.
  - Outfitter: drag an item onto a free slot to buy it, or an installed item onto the sell well.
  - Galaxy chart: a click pins a card with Set Target, Track and Plot Route; a plain mouse wheel zooms, two fingers pan, pinch zooms; larger hit areas.
  - Encounters: larger buttons; quantity chips in the Plunder, Trade and Make Room sheets.
  - Every push button and custom control is at least a 36-point target without growing on screen; cards and rows react to the pointer; context menus on cargo, ships, equipment, crew, quests and systems.
- The Bridge mini chart's wormholes no longer animate; an idle Bridge now uses about half the CPU it did.

## [1.0.0] - 2026-11-17
The first release.

### Added
- **Rulesets:** three, chosen at New Game.
  - **Modern** (default): the Windows 2.01 rules with their bugs fixed.
  - **Windows 2.01**: checked bit-exact against differential-harness fixtures.
  - **Original Palm 1.2.2**: Palm tables, events, police, tribbles, newspaper and scoring.
- **Engine:** a pure, deterministic Swift engine. It covers trading, travel, encounters and combat, all 46 Windows and 37 Palm special events, the endings and high scores.
- **Interface:** a single-window SwiftUI interface.
  - Sections: Bridge, Market, Shipyard (with the ship designer), Outfitter, Crew, Bank, Galaxy chart, Quests and Logbook, plus a ship inspector.
  - Encounter mode, arrival reports, a styled newspaper and an event feed.
- **Galaxy chart:** zoomable, with heatmaps, hover cards, a route planner and a detachable window.
- **Records:** trade intelligence, Captain's Log, statistics and achievements.
- **Flavor text:** optional on-device text from Foundation Models, with a deterministic template fallback.
- **Art and sound:** new vector art and a code-drawn app icon, plus synthesized audio and haptics.
- **Saves:** slots with autosave, rotating backups, import/export and Ironman mode.
- **Keyboard:** a full keyboard map with a single Esc handler per window.
- **Accessibility:**
  - VoiceOver labels, values, actions, announcements and rotors.
  - Text Size.
  - Support for Reduce Motion, Increase Contrast, Reduce Transparency and Differentiate Without Color.
- **Localization:** a localization-ready string catalog, checked with pseudo-localization.
