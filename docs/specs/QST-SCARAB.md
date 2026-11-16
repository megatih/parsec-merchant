# QST-SCARAB: The stolen Scarab and the hull upgrade

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern, plus anything shared with Palm. `{M5}` is a Palm-only variant or a Modern-only fix that needs a ruleset flag.
>
> **Sources.** C# 2.01: `/Users/megatih/Downloads/SpaceTraderSource201` (`File.cs:line`). Palm 1.2.2: `docs/reference/palm-src/Src`. Re-read in the source on 2026-11-17. Research 01 §10 was the checklist. Its "first click after arriving by wormhole" means click 20, the first click of the 21-click trip (ENC-010).
>
> **Shared rules.** `specialEventAvailable`, `Command.specialEvent`, the two-phase consent and the `.noSpecialEvent` and `.insufficientFunds` rejections are defined in QST-INDEX. A handled event emits `GameEvent.specialEventCompleted(type)`.
>
> **Ownership.** GAL owns placement (GAL-034, GAL-037, GAL-042). ENC owns the encounter trigger and persistence (ENC-010…014, ENC-153). CMB owns Scarab weapon vulnerability and hull hardening (CMB-018, CMB-031, CMB-032). SHP owns hull strength and the reset on purchase (SHP-018, SHP-048). NEWS owns headlines (NEWS-034).

## 1. Statuses, events and table rows

- **QST-SCARAB-001** {M4} [M][W][P] `quests.scarab` takes the values of `QuestStatus.Scarab`: 0 `notStarted`, 1 `hunting`, 2 `destroyed`, 3 `done` (hull upgraded). A new game starts at 0. (source: SpecialEvent.cs:89-92; Palm: Src/Global.c:638)
- **QST-SCARAB-002** {M4} [M][W][P] Events: `scarab` on one random system (occurrence 1, GAL-037); `scarabDestroyed` on the Scarab's end-point wormhole system (GAL-034; Palm GAL-042); `scarabUpgradeHull`, which is never placed and replaces `scarabDestroyed` (QST-SCARAB-007). Table rows (price, occurrence, message-only): `scarab` 0/1/yes, `scarabDestroyed` 0/0/yes, `scarabUpgradeHull` 0/0/no. Only the upgrade needs `.acceptSpecialEvent` (amounts `[0]`). (source: Consts.cs:328-330, Game.cs:2903-2909; Palm: Src/Global.c:519-521)

## 2. When the button shows

- **QST-SCARAB-003** {M4} [M][W][P] `scarab` needs `scarab == 0` and reputation ≥ 40 (Average). `scarabDestroyed` and `scarabUpgradeHull` both need `scarab == 2`. (source: StarSystem.cs:257-264; Palm: Src/SystemInfoEvent.c:290-292)
- **QST-SCARAB-004** {M5} [P] Palm hides the `scarab` start while more than 3 quests are open (RUL-141). If Palm placement found no free wormhole, no `scarab` event exists (GAL-042, GAL-047). (source: Palm: Src/SystemInfoEvent.c:302-311, Src/Traveler.c:1583-1598)

## 3. Handler effects

- **QST-SCARAB-005** {M4} [M][W][P] `scarab` sets `scarab = 1` and removes the event. (source: Game.cs:2477-2479; Palm: Src/SpecialEvent.c:130-132)
- **QST-SCARAB-006** {M4} [M][W][P] The Scarab is met only under the ENC-010(b) conditions: the trip arrives through a real wormhole (`arrivedViaWormhole`), at click 20, at the system whose event is still `scarabDestroyed`, while `scarab == 1`. A normal warp to that system, or a trip anywhere else, never meets it. The opponent is the persistent `specialShips.scarab` (hull 400, 2 military lasers, crew 5+D/6+D/1/6+D, ENC-014). In Windows, Beam and Military lasers and the Photon disruptor do not count against it (CMB-018, RUL-091). Surrendering to it is a pirate raid (ENC-153). (source: Game.cs:790-798; Palm: Src/Traveler.c:1825-1840)
- **QST-SCARAB-007** {M4} [M][W] Destroying or disabling the Scarab sets `scarab = 2` and adds `pirateKills += 1`, record +1 and `reputation += 13/2 + 1 = 7` (the Scarab's ship type is 13), with no bounty and no scoop (CMB-045, CMB-070). Escaping, being escaped from, or ignoring it while cloaked leaves `scarab == 1` and keeps its damage (ENC-012). (source: Game.cs:1108-1113, :1195-1217, :2008-2010, :2028)
- **QST-SCARAB-008** {M4} [M][W][P] `scarabDestroyed` (message-only) sets `scarab = 2`, which it already was. It replaces the system's event with `scarabUpgradeHull` instead of removing it, and the upgrade is then offered at once. (source: Game.cs:2480-2484; Palm: Src/SpecialEvent.c:134-138)
- **QST-SCARAB-009** {M4} [M][W] `scarabUpgradeHull` without consent returns `needsConfirmation(Confirmation(.acceptSpecialEvent, amounts: [0]))`. With it: `ship.hullUpgraded = true`, `ship.hull += 50` (`HullUpgrade`), `scarab = 3`. The event is **not** removed (C# sets `remove = false`), but it stays hidden because its condition needs status 2. Hull strength becomes spec + 50 (SHP-018), so the current hull rises by 50 whatever the damage: 60/100 becomes 110/150. The step needs no slot and cannot be refused. (source: Game.cs:2485-2491, Consts.cs:74, ShipSpec.cs:282-288)
- **QST-SCARAB-010** {M5} [P] Palm `GETHULLUPGRADED` does `Ship.Hull += 50` and `ScarabStatus = 3` with no stored flag. Hull strength is spec + 50 while `ScarabStatus == 3` (SHP-019), and the event is likewise kept. (source: Palm: Src/SpecialEvent.c:140-145, Src/Shipyard.c:117-123)

## 4. Living with the upgrade, and losing it

- **QST-SCARAB-011** {M4} [W] While `scarab == 3`, hull damage after the cap is halved for **every** defender, opponents included (CMB-031). (source: Game.cs:1367-1368)
- **QST-SCARAB-012** {M5} [M][P] `hullHardeningScope` (RUL-104, MOD-004; engine flag `hardenedHullProtectsPlayerOnly`): Modern halves damage only when the player's ship is the defender (CMB-032). Palm never halves; it caps damage against the upgraded hull instead (CMB-030). (source: PRD MOD-004; Palm: Src/Encounter.c:860-866)
- **QST-SCARAB-013** {M4} [M][W] Any successful ship purchase or custom build resets `scarab` from 3 to 0, and the new ship has `hullUpgraded == false` (SHP-044, SHP-048, SHP-075). The quest cannot be repeated: the `scarab` start was removed, and the kept `scarabUpgradeHull` needs status 2. (source: Form_ShipList.cs:892-895, Form_Shipyard.cs:1185-1190)
- **QST-SCARAB-014** {M4} [M][W] The escape pod and a ship sold to pay an arrest fine replace the ship with a new Flea (`hullUpgraded == false`, base hull) but leave `scarab == 3`. The halving rule of QST-SCARAB-011/012 therefore keeps protecting the Flea (RUL-099, POL-106). (source: Game.cs:735-741, :2031-2101, :285-292)
- **QST-SCARAB-015** {M5} [P] Palm's escape pod resets `ScarabStatus` 3 → 0 (`escapePodLosesHullUpgrade`, RUL-099, POL-107), and so does a ship purchase (SHP-045). (source: Palm: Src/Encounter.c:589-590, Src/BuyShipEvent.c:80-81)
- **QST-SCARAB-016** {M5} [P] Palm's Scarab starts every meeting undamaged with reset crew skills (ENC-013), and only Pulse and Morgan's lasers hurt it (RUL-091, CMB-019). Palm cannot disable it (RUL-015). (source: Palm: Src/Traveler.c:1825-1840, Src/Encounter.c:810-821)

## 5. News

- **QST-SCARAB-017** {M4} [M][W] Arrival headlines (NEWS-034): the `scarab` start system gives `scarab` while that event is unhandled. The end-point system gives `scarabHarass` at status 1 and `scarabDestroyed` at status ≥ 2 while its event is still `scarabDestroyed`. Once that event has become `scarabUpgradeHull`, the system gives nothing. Palm: NEWS-038/041 {M5}. (source: Game.cs:2803-2811)

## 6. Scenarios

- **QST-SCARAB-018** {M4} [M][W] Scenario (happy path): with reputation 40, accept `scarab` (status 1). Travel through the wormhole into the end-point system: a `scarabAttack` encounter starts at click 20. Destroy it with pulse lasers: status 2, +7 reputation. Dock: news `scarabDestroyed`. Take the message: the event becomes `scarabUpgradeHull`. Consent: `hullUpgraded`, hull and hull strength +50, status 3, no further button. In Windows, a later hit on an opponent is halved. Buy any ship: status 0, no upgrade, and no Scarab button anywhere.
- **QST-SCARAB-019** {M4} [M][W] Scenario (failures): (a) with reputation 39 the start is hidden. (b) At status 1, a normal (non-wormhole) warp to the end-point system has no Scarab encounter; docking there shows no button and the news holds `scarabHarass`. (c) Damage the Scarab, then escape: the status stays 1, and the next wormhole arrival meets it with the reduced hull. (d) After the upgrade, use the escape pod: the Flea has base hull, `hullUpgraded == false` and `scarab == 3`.
