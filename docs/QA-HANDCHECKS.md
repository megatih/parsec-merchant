# Owner hand checks (M13)

These five QA-REPORT rows need a person: they involve VoiceOver, listening, or system-wide settings the agent does not change.
Use the published v1.0.0 app (`gh release download v1.0.0 --repo megatih/parsec-merchant --pattern 'Parsec-Merchant-1.0.0.zip'`, unzip, then `open -n "Parsec Merchant.app"`). If macOS blocks it: System Settings › Privacy & Security › Open Anyway. Start a New Game or Quick Start.

## (a) A11Y-013 / A11Y-015 VoiceOver
1. ⌘F5 turns VoiceOver on.
2. Focus (013): open a sheet (New Game…, Options…): the cursor lands on its title or first control; Esc returns it to the invoking control. Warp (pick a target on the Galaxy chart, ⌘J): the arrival card is announced but does not take focus. After an encounter ends, focus is in the detail area.
3. Rotors (015): in each section press VO-U (⌃⌥U) and ←/→. Headings, Links, Tables and Landmarks work everywhere; custom rotors Market "In Hold" / "Profitable at Target", Quests "Deadlines", Logbook "Log days" and the map rotors on Galaxy move the cursor to their entries; flavor text is read after the log row.
4. ⌘F5 turns VoiceOver off.

## (b) AUD-052 sound
1. Settings… › Sound: sound on, master volume up, music on.
2. Play about 2 minutes: trade in the Market, warp until an encounter, open the Newspaper.
3. Switch the output device during play (Control Center › Sound); sound continues on the new device.
4. Each sound lines up with its visual cue.
5. Right after: `log show --last 3m --predicate 'process == "Parsec Merchant" AND (messageType == error OR messageType == fault)'` shows no audio or AVAudioEngine errors (generic `CFBundle` / `BaseBoard` lines are fine).

## (c) UI-KEYS-016 keyboard layouts
1. System Settings › Keyboard › Text Input › Edit: add German and French.
2. With German active: Previous/Next Target (⌘[ ⌘] on US; select a system first), Zoom In on the Galaxy chart (⌘+) and Parsec Merchant Help (⌘?) work from the keyboard, and the menus show the remapped glyphs.
3. Repeat with French; switch back afterwards.

## (d) ART-058 icon styles
1. System Settings › Appearance › Icon & widget style: Dark, then Tinted, then Clear.
2. Each time, check the Dock icon and the Finder icon in small/list view (~16 px): ring and ship legible, silhouette recognisable.
3. Restore your style.

## (e) LLM-031 Apple Intelligence off
1. Settings… › Intelligence: turn on "Write log entries with Apple Intelligence" (status "Available").
2. Quit, turn Apple Intelligence off (System Settings › Apple Intelligence & Siri), relaunch.
3. Settings… › Intelligence: the status line says Apple Intelligence is unavailable or off.
4. Warp once: new Logbook entries are template lines without the Apple Intelligence mark.
5. Turn Apple Intelligence back on if you wish.

Report pass/fail per letter (with a note or screenshot for any failure) to the agent.

# Owner hand checks (1.1.0, M17)

These rows cannot be judged by the agent: they are about how the app looks and feels in use, and about touch hardware.
They do not block the 1.1.0 release (`docs/PRD-1.1.md` §7). Use the published v1.1.0 app, or run the Debug build from Xcode.

## (f) Look of planets, ships and endings (PRD-1.1 §1, §6 M14/M15)
1. Bridge: the planet is a lit sphere in front of its star; within two seconds the surface and the clouds visibly turn. Warp a few times: the worlds differ (seas, deserts, ice, jungle, rock, lava, gas giants, rings), and a visited system's picture matches its special resource.
2. System Settings › Accessibility › Display › Reduce Motion: the planet is a still picture; turn it off again.
3. Shipyard, inspector, designer, an encounter and a warp: no ship looks like an insect; a freighter (Beetle, Termite) is visibly a freighter and a three-weapon ship (Hornet, Wasp) a warship; the ships fill their panels; beams start and end on the ships.
4. Endings: retire (Game › Retire…), buy the moon, or lose a ship without an escape pod: the scene is lit by a sun and has depth, not flat shapes.

## (g) ART-058 icon at 16 px (the hauler is the generated freighter now)
1. Finder list view or the Dock at its smallest size: the ring and the freighter are still recognisable, in the Default, Dark, Tinted and Clear icon styles.

## (h) UI-PTR-018 touch (a touch-display Mac, or an iPad through Sidecar)
1. Start a game with taps only: Quick Start; Market: a quantity chip, then Buy.
2. Galaxy: tap a system; its card appears with Set Target, Track and Plot Route; tap Warp.
3. An encounter: its buttons are easy to hit; play it to the end by touch.
4. Market: the Max chip, then Sell.
5. Touch and hold a Market row and a map system: the context menu opens with the same actions.
6. Pinch zooms the map and a one-finger slide pans it; lists scroll with a slide.
7. Outfitter: touch and hold an item, then drag it onto a free slot; drag an installed item onto the sell well.
8. Nothing was too small to hit and nothing needed the keyboard or a hover.

## (i) Idle CPU on a quiet machine (ART-052)
1. `scripts/release.sh` then `scripts/idle-cpu.sh`: both samples are at most 5% (2.3–2.6% were measured on 2026-11-18 while the machine was busy installing updates).
