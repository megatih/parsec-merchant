# ADR-0003: The game journal (log + intel) is saved beside `state`, not inside `GameState`

- Status: accepted (2026-11-17, M10)
- Refines: PRD §6.2 (which listed "event log, player intel" as part of `GameState`), SAV-001, SAV §15 open question.
- Specs: LOG-001…003, INT (IntelBook), LLM (flavor cache).

## Context
The log caches flavor text (LLM), and PRD §6.4/LLM require that flavor never changes game state and that
`-PMFlavor template` makes the app behave identically. The engine must stay string-free, and every M1–M9 harness fixture,
golden test and state hash must stay valid. The rules never read the log or the player's trade intel.

## Decision
`SaveEnvelope` gains one top-level key, `journal` (`GameJournal`: log entries, next entry id, the `IntelBook`, and any
open encounter ledger), next to `state`. `GameState` is unchanged. The journal uses only structs, enums, arrays, `Int`,
`Bool` and `String`, so sorted-key JSON round trips stay byte-identical. Save schema v1 is unreleased, so `journal` joins
v1 and the v1 fixtures are regenerated; a save without `journal` still loads (the app rebuilds a fresh journal).
Revert to Autosave rewinds the journal with the game.

## Consequences
- Engine determinism, replays, fuzzing and state hashes are unaffected by log length or flavor.
- ParsecPersistence depends on ParsecInsights for the journal types.
- Any future rule that needs history must add it to `GameState` explicitly, never read the journal.
