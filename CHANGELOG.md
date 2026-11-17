# Changelog

All notable changes to Parsec Merchant are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/) and versions follow [Semantic Versioning](https://semver.org/).

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
