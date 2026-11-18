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
