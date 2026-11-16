# QST-SCULPTURE: The stolen sculpture

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. `{M4}` is C# 2.01 behaviour, kept in Modern. The chain does not exist in Palm (RUL-013): no bullet here carries `[P]`.
> Sources: C# 2.01 at `/Users/megatih/Downloads/SpaceTraderSource201`, re-read on 2026-11-17. Shared rules are QST-INDEX §3. Placement: the `Sculpture` start goes to the closest free system at least 70 parsecs from Endor (GAL-036) and `SculptureDelivered` sits at Endor (25) (GAL §10.1).
> Status constants: `QuestStatus.Sculpture` = notStarted 0, inTransit 1, delivered 2, done 3. `sculptureOnBoard` ⇔ `sculpture == 1` (C# `Ship.SculptureOnBoard`, Ship.cs:1173-1179).

## 1. Taking the job

- **QST-SCULPTURE-001** {M4} [M][W] `Sculpture` is shown iff `sculpture == 0 && rec < −5 && rep >= 40`; it is a question with price −2000 (`Confirmation(.acceptSpecialEvent, amounts: [−2000])`), so the price check only fails when `cashToSpend < −2000` (QST-007). (source: StarSystem.cs:265-268; Consts.cs:338)
- **QST-SCULPTURE-002** {M4} [M][W] Accepting sets `sculpture = 1`, adds 2000 to cash (paid up front) and removes the event. The sculpture uses no cargo bay, quarter or slot. While the event is in place, arriving at its system adds `NewsEvent.sculptureStolen` (NEWS-034). (source: Game.cs:2492-2494, :2577-2581; Ship.cs:959-972; Game.cs:2812-2814)
- **QST-SCULPTURE-003** {M4} [M][W] Every arrival at Endor while its event is `SculptureDelivered` adds `NewsEvent.sculptureTracked`, whatever the quest status (even 0) (NEWS-034). (source: Game.cs:2815-2817)

## 2. While aboard

- **QST-SCULPTURE-004** {M4} [M][W] The sculpture is illegal special cargo (POL-051): with it aboard, submitting to an inspection ends in arrest (POL-055/059), the bribe uses the ×2/×3 multiplier (POL-066, RUL-140), yielding to the Marie Celeste police needs `surrenderToPolice` and arrests (POL-071, ENC-156), and the surrender confirmation lists it. (source: Ship.cs:1131-1137, :640-662; Game.cs:1741, :1942-1948)
- **QST-SCULPTURE-005** {M4} [M][W] Surrendering to pirates (or the Scarab) with it aboard: with hidden cargo bays fitted it is kept and `GameEvent.preciousHidden` is emitted; otherwise `sculpture = 0` with `GameEvent.sculptureTaken` (POL-078, ALR-059), before the cargo theft or blackmail. (source: Game.cs:1866-1886)
- **QST-SCULPTURE-006** {M4} [M][W] Arrest with it aboard sets `sculpture = 0` (POL-093 step 3); hidden cargo bays are removed first (step 1), whatever the sculpture. No separate event: the arrest report derives ALR-135 (`SculptureConfiscated`) from `arrested` and the status change (POL-093). (source: Game.cs:214-232)
- **QST-SCULPTURE-007** {M4} [M][W] The escape pod keeps the sculpture: the status stays 1 (POL-104 step 1; the pod report derives ALR-136 `SculptureSaved` from `escapePodUsed` with the sculpture still aboard); ship trades also keep it. (source: Game.cs:2035-2036; Ship.cs:1173-1179)
- **QST-SCULPTURE-008** {M4} [M][W] Wild boarding while the sculpture is aboard adds the follow-up `wildAdmiresSculpture` narrative (QST-WILD, ALR-184); it changes no state. (source: Game.cs:2556-2557)
- **QST-SCULPTURE-009** {M4} [M][W] Once lost (status 0) the job cannot be taken again: the start event was removed, and `SculptureDelivered` is shown only at status 1. (source: Game.cs:2492-2494; StarSystem.cs:270-272)

## 3. Delivery and reward

- **QST-SCULPTURE-010** {M4} [M][W] `SculptureDelivered` (Endor) is shown iff `sculpture == 1`; it is message-only with price 0. Handling sets `sculpture = 2` and replaces Endor's event with `SculptureHiddenBays`. (source: StarSystem.cs:270-272; Game.cs:2495-2499; Consts.cs:339)
- **QST-SCULPTURE-011** {M4} [M][W] `SculptureHiddenBays` is always shown; it is a question with price 0. The handler first sets `sculpture = 3`; then, with no free gadget slot, the command returns `rejection: nil` with events `[.specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot)]`, committing `sculpture == 3` and keeping the event (the documented exception of QST-010). With a free slot it installs one Hidden Cargo Bays gadget (SHP-062: +5 bays, concealment POL-056/079), and the event is removed with `[.specialEventCompleted(.sculptureHiddenBays)]` (ALR-084). (source: Game.cs:2500-2513; Consts.cs:340)
- **QST-SCULPTURE-012** {M4} [M][W] After a refusal the reward stays claimable: `SculptureHiddenBays` is still offered on every visit to Endor (its condition is "always"), and a later acceptance with a free slot installs the bays. (source: StarSystem.cs:195, :199; Game.cs:2500-2513)

## 4. Scenarios

- **QST-SCULPTURE-013** {M4} [M][W] Success: with `rec = −10`, `rep = 40`, accept `Sculpture` (cash +2000, status 1); fly to Endor; handle `SculptureDelivered` (status 2, event `SculptureHiddenBays`); accept `SculptureHiddenBays` with a free gadget slot (hidden bays installed, status 3, event `nil`). (source: Game.cs:2492-2513)
- **QST-SCULPTURE-014** {M4} [M][W] Gates: `rec = −5` or `rep = 39` → the start is not offered. (source: StarSystem.cs:265-268)
- **QST-SCULPTURE-015** {M4} [M][W] Slot refusal: at Endor with every gadget slot full, accepting `SculptureHiddenBays` returns `specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot)` with `sculpture == 3` committed and the event kept; after selling a gadget, the next acceptance installs the bays. (source: Game.cs:2500-2513)
- **QST-SCULPTURE-016** {M4} [M][W] Pirate failure: surrendering to pirates without hidden bays sets `sculpture = 0` with `.sculptureTaken`; the 2000 already paid is kept; Endor never offers the delivery. (source: Game.cs:1881-1885)
- **QST-SCULPTURE-017** {M4} [M][W] Police failure: an arrest with the sculpture aboard sets `sculpture = 0`; an escape pod instead keeps status 1, and the delivery still works from the Flea. (source: Game.cs:228-232, :2035-2036)
