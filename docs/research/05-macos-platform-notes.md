# macOS 27 / Xcode 27 Platform Notes for Parsec Merchant

> Research 2026-11-16. These facts were verified on the build machine or taken from Apple's WWDC26 material. A section that says **[verify]** means check it against the current SDK before relying on it.

## 1. Build machine and toolchain (verified locally)
- **Toolchain:** Xcode **27.2** (27B52), macOS **27.2.1**, Swift **6.4**.
- **Tools available:** `xcodegen`, `swiftlint`, `gh`, `xcrun swift-format`, `xcprojformatter`, `xcrun mcpbridge`.
- **Not installed:** `dotnet` and `mono`, so the C# game cannot be run as a reference.
- **gh:** logged in as `megatih` (keyring), using https.
- **Xcode agent skills:** Xcode ships skills for coding agents ("SwiftUI Specialist", "What's New in SwiftUI"). Export them with:
  ```
  xcrun mcpbridge run-agent skills export --output-dir <dir> [--replace-existing]
  ```
  (`xcrun agent ...` is an alias of `mcpbridge run-agent`.) Export them into `.claude/skills/` so Claude Code finds them automatically, and check what you got with `ls`.
- **Xcode MCP bridge:** `xcrun mcpbridge` is an STDIO MCP server that exposes Xcode's tools (build, tests, previews…) to an agent. It needs a running Xcode. To register it: `claude mcp add xcode -- xcrun mcpbridge` (optional; command-line `xcodebuild` is enough).

## 2. The template project
- **Path:** `/Users/megatih/Documents/XcodeProjects/SpaceTraderMac`. Git branch `main`, one commit, "Initial Commit".
- **Project format:** the new **JSON** `SpaceTraderMac.xcodeproj/project.xcproj` (not `project.pbxproj`). It uses **folder-synchronized** entries: `{ "kind": "folder", "path": "SpaceTraderMac", "target-membership": ["SpaceTraderMac"] }`, and the same for `SpaceTraderMacTests` and `SpaceTraderMacUITests`. Any file placed in those folders joins the target automatically.
- **Targets:** `SpaceTraderMac` (app), `SpaceTraderMacTests` (unit tests, `TEST_HOST` hard-codes `SpaceTraderMac.app/.../SpaceTraderMac`), `SpaceTraderMacUITests`.
- **Notable settings:**
  - `MACOSX_DEPLOYMENT_TARGET 27.2`
  - `SWIFT_VERSION 5.0` → change to **6.0**
  - `SWIFT_DEFAULT_ACTOR_ISOLATION MainActor` (app target only)
  - `SWIFT_APPROACHABLE_CONCURRENCY YES`
  - `ENABLE_APP_SANDBOX YES`
  - `ENABLE_HARDENED_RUNTIME YES`
  - `ENABLE_USER_SELECTED_FILES readonly` → change to **readwrite** so save export works
  - `GENERATE_INFOPLIST_FILE YES`
  - `STRING_CATALOG_GENERATE_SYMBOLS YES`
  - `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS YES`
  - `LOCALIZATION_PREFERS_STRING_CATALOGS YES`
  - `DEVELOPMENT_TEAM FVX2F2KV5M` (free personal team)
  - `PRODUCT_BUNDLE_IDENTIFIER io.github.megatih.SpaceTraderMac`
- **Template code to remove:** the SwiftData `Item` model and the template `ContentView`/`SpaceTraderMacApp`.
- **Adding a local Swift package to the JSON project is undocumented.** `xcprojformatter` has the keys `packages`, `local`, `remote`, `package-product-members` and `package-dependencies`. Follow the fallback ladder in PRD §6.3.

## 3. Swift and concurrency
- **Swift 6.4** ships with Xcode 27. It is a refinement release with no new language mode. New Xcode 27 projects still default to the Swift 5 language mode, so set `SWIFT_VERSION = 6.0` explicitly.
- **App target isolation:** the app target defaults to MainActor isolation. Swift packages do **not** inherit that setting, so engine code compiles nonisolated. That is the main reason the engine lives in a package.
- **Real-time audio:** audio render blocks (`AVAudioSourceNode`) must be `nonisolated`, must not allocate, and must not take locks.
- **`@State` is now a macro** with lazy initialization, back-deployed. Gotcha: giving a property a default value *and* assigning it in `init` is now an error ("used before being initialized"). Fix it by removing the default value (TN3211).
- **`ContentBuilder`** unifies `ViewBuilder`, `CommandsBuilder`, `ToolbarContentBuilder` and the rest. It type-checks faster.

## 4. SwiftUI on macOS 27 (WWDC26 session 269, "What's new in SwiftUI")
- **Liquid Glass** comes automatically when you build with the 2027 SDKs. It responds to the system tint slider. Inactive windows dim automatically; `@Environment(\.appearsActive)` lets custom views do the same. Custom controls can opt into "interactive" glass. The 2025 API is `.glassEffect(.regular.interactive())` [verify the name on 27].
- **Menus:** menu items show text only by default. Add `.labelStyle(.titleAndIcon)` to show icons.
- **Toolbars:** `visibilityPriority(.high)`, `ToolbarOverflowMenu { }`, and `toolbarMinimizeBehavior`. (`.topBarPinnedTrailing` is iOS only.)
- **Alerts and dialogs:** `alert(_:item:)` and `confirmationDialog(_:item:)` now work like `sheet(item:)`, and can be presented from an optional item or an error.
- **Reordering:** `reorderable()` together with `reorderContainer(for:)`.
- **Swipe actions:** `swipeActionsContainer()` enables swipe actions on any view.
- **Documents:** new `ReadableDocument`/`WritableDocument`/`DocumentWriter`, `DocumentGroupLaunchScene`, `NewDocumentButton(source:)` and direct URL access. **We don't use these.** Parsec Merchant uses shoebox saves (see PRD).
- **Other APIs:** `CrossFadeNavigationTransition`; `TextRenderer` on `Text`; `AsyncImage` caching (not needed).
- **Known macOS 27 bugs (community reports, Michael Tsai blog 2026-06-19):**
  - **Showing a popover more than once crashes** (August). → **Do not use `.popover` anywhere.** Use overlays, sheets or the inspector instead.
  - `reorderable()` crashes when the content contains `if #available` or a popover.
  - The app menu is computed once, so dynamic app-menu items don't refresh. Put dynamic items in `CommandMenu`s whose views observe state.
  - Submenus can't be built lazily when their parent menu opens.
  - Auto-sizing a window to fit its content is unreliable. Set explicit `defaultSize` / `windowResizability(.contentMinSize)` instead.
  - `TextEditor` can't turn off smart quotes; this doesn't matter for us.
  - Instruments sometimes reports "Trace file had no SwiftUI data".
- **macOS-native patterns to use:**
  - `NavigationSplitView` (sidebar, detail)
  - `.inspector(isPresented:)`
  - `Window` / `WindowGroup`, `Settings`, `.commands` with `CommandMenu`/`CommandGroup`
  - `openWindow`
  - `Table` with sort comparators
  - `Canvas` + `TimelineView`; `onContinuousHover`; `MagnifyGesture`
  - `.focusable()` with `.onKeyPress`, `.keyboardShortcut`
  - `fileImporter`/`fileExporter`
  - `ImageRenderer` (icon generation and snapshot tests)
  - Swift Charts (sparklines; `BarMark`/`LineMark`; `.chartXSelection`)
  - `sensoryFeedback` (on macOS it maps to trackpad haptics) or `NSHapticFeedbackManager.defaultPerformer`

## 5. HIG and design guidance (macOS)
- **Glass is for navigation and controls.** It belongs on toolbars, sidebars, inspectors and floating controls, never behind dense content such as tables. Let the system provide it. Don't hand-roll blurs or skin the toolbar.
- **Windows and controls:** windows with toolbars get larger, concentric corner radii. Mini, small and medium control sizes suit dense inspectors.
- **Sidebar:** standard source-list sidebar; content may extend under it.
- **Behaviors every Mac app should have:**
  - A full menu bar with standard items and shortcuts. Avoid shortcuts that clash with system ones: ⌘C, ⌘A, ⌘H, ⌘Q, ⌘W, ⌘M.
  - Settings opened with ⌘,
  - An About panel
  - Help
  - Restore window size and position
  - Full Keyboard Access
  - VoiceOver
  - Respect for Reduce Motion, Increase Contrast and Reduce Transparency
  - Dark and light appearances
  - Dynamic text sizes via text styles
- **Games category:** set `LSApplicationCategoryType = public.app-category.games` (role-playing or simulation sub-genres are optional).
- **Naming (WWDC26 "Craft clear names"):** use plain labels. "Warp" and "Market" are fine; avoid cryptic abbreviations such as "Int." for interrupt.

## 6. Foundation Models (on-device Apple Intelligence)
- **Framework:** `import FoundationModels`. Use `SystemLanguageModel.default` and check `.availability` (it reports a reason when unavailable: device not eligible, Apple Intelligence off, model not ready).
- **Sessions:** create `LanguageModelSession(instructions:)` and call `respond(to:)` (async) or `streamResponse`. Guided generation uses `@Generable` / `@Guide` structs.
- **WWDC26 additions:** provider protocol, Dynamic Profiles, the Evaluations framework, and Private Cloud Compute access for small developers. **We use only the on-device default model**, with no network and no account.
- **Requirements:** it must be strictly optional. Wrap it in `if #available` and an availability check, add a timeout (≈4 s), and fall back to deterministic templates. Generated text is cosmetic only: never feed it back into game state. Cache the result per log entry.
- **Entitlements:** none needed for on-device use [verify].

## 7. Audio and haptics
- **Engine:** `AVAudioEngine` with `AVAudioSourceNode` for synthesis, or pre-rendered `AVAudioPCMBuffer` played through `AVAudioPlayerNode`. A sandboxed app needs no entitlement for output.
- **Procedural SFX:** laser = frequency-swept square or saw wave; explosion = filtered noise burst with an envelope; warp = rising sweep plus reverb (`AVAudioUnitReverb`); UI ticks; a "cash" chime from FM bells. Ambient music = slow generative pads.
- **Haptics:** `NSHapticFeedbackManager.defaultPerformer.perform(.alignment / .levelChange / .generic, performanceTime: .now)`. They only fire on Force Touch trackpads. Never rely on haptics alone to convey information.

## 8. Signing and distribution without a paid Apple Developer Program
- **The free personal team** (`FVX2F2KV5M`) can sign for local development but **cannot create Developer ID certificates and cannot notarize**. Game Center, iCloud/CloudKit, push and App Groups all require the paid program, so leave them out.
- **Release build:** archive or build Release, then ad-hoc sign: `codesign --force --deep --options runtime --entitlements <ent> -s - "Parsec Merchant.app"`. Verify with `codesign --verify --deep --strict`. Zip with `ditto -c -k --keepParent`.
- **Gatekeeper on macOS 15 and later:** the Control-click → Open bypass was removed in Sequoia. Users must:
  1. Try to open the app once.
  2. Go to **System Settings › Privacy & Security** and click **Open Anyway**.
  3. Authenticate.
  
  Approval is per app. The README must explain this step by step and offer build-from-source instructions. The `xattr -dr com.apple.quarantine` command is an advanced alternative; mention it only with a caveat. Reference: https://support.apple.com/102445
- **Homebrew:** Homebrew casks now require notarized apps, so skip Homebrew.

## 9. Claude Code `/goal` facts (https://code.claude.com/docs/en/goal)
- **What it is:** `/goal <condition>` (up to **4,000 chars**) keeps Claude working turn after turn. After each turn a small, fast model judges, **from the transcript only**, whether the condition holds. It runs no commands and reads no files. So the condition must be something Claude's own output can *show*, for example "`scripts/verify.sh` prints ALL GATES PASSED".
- **Clears when:** the condition is met, the evaluator judges it impossible, or an error that only you can fix occurs (auth, credits, context overflow).
- **Session lifetime:** the goal survives a resume. Running `/clear` removes it.
- **Bounding:** you can add "or stop after N turns" to bound a run.
- **Permissions:** `/goal` does not change the permission mode. Run it in **auto mode** so turns proceed unattended.
- **Background work:** background subagents defer evaluation; there are check-ins every 30 minutes and up to 3 idle check-ins.
