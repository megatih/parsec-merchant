// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecArt
import ParsecEngine
import ParsecInsights
import ParsecPersistence
import SwiftUI
import Testing
@testable import ParsecMerchant

/// A11Y §1–§7: preferences, launch arguments, values, rows, surfaces, announcements, rotors and display styles.
@MainActor
struct AccessibilityTests {
    // MARK: §1 Foundations

    @Test("A11Y-001 AccessibilityPreferences.resolve ORs the system with the override, per setting")
    func resolveTruthTable() {
        for s in 0..<16 {
            for o in 0..<16 {
                let system = AccessibilityPreferences(reduceMotion: s & 1 != 0, increaseContrast: s & 2 != 0,
                                                      reduceTransparency: s & 4 != 0, differentiateWithoutColor: s & 8 != 0)
                let override = AccessibilityPreferences(reduceMotion: o & 1 != 0, increaseContrast: o & 2 != 0,
                                                        reduceTransparency: o & 4 != 0, differentiateWithoutColor: o & 8 != 0)
                let r = AccessibilityPreferences.resolve(system: system, override: override)
                let bits = s | o
                #expect(r.reduceMotion == (bits & 1 != 0))
                #expect(r.increaseContrast == (bits & 2 != 0))
                #expect(r.reduceTransparency == (bits & 4 != 0))
                #expect(r.differentiateWithoutColor == (bits & 8 != 0))
                #expect(r.art.reduceMotion == r.reduceMotion && r.art.increaseContrast == r.increaseContrast)
            }
        }
        #expect(EnvironmentValues().accessibilityPreferences == .standard)
    }

    @Test("A11Y-002 -PMA11y, -PMTips and -PMWindowSize parse in Debug, are ignored in Release and tolerate bad values")
    func launchArguments() {
        let all = LaunchOptions.parse(["app", "-PMA11y", "reduceMotion,increaseContrast,reduceTransparency,differentiateWithoutColor"],
                                      isDebug: true)
        #expect(all.accessibility == AccessibilityPreferences(reduceMotion: true, increaseContrast: true, reduceTransparency: true,
                                                              differentiateWithoutColor: true))
        let one = LaunchOptions.parse(["app", "-PMA11y", "reduceMotion", "-PMSeed", "11"], isDebug: true)
        #expect(one.accessibility == AccessibilityPreferences(reduceMotion: true))
        #expect(one.seed == 11)
        let bad = LaunchOptions.parse(["app", "-PMA11y", "bogus, ,increaseContrast"], isDebug: true)
        #expect(bad.accessibility == AccessibilityPreferences(increaseContrast: true))
        let missing = LaunchOptions.parse(["app", "-PMA11y", "-PMFastTravel"], isDebug: true)
        #expect(missing.accessibility == .standard && missing.fastTravel)
        #expect(LaunchOptions.parse(["app", "-PMTips", "off"], isDebug: true).tips == .off)
        #expect(LaunchOptions.parse(["app", "-PMTips", "all"], isDebug: true).tips == .all)
        #expect(LaunchOptions.parse(["app", "-PMTips", "sometimes"], isDebug: true).tips == nil)
        #expect(LaunchOptions.parse(["app", "-PMWindowSize", "min"], isDebug: true).minimumWindow)
        #expect(!LaunchOptions.parse(["app", "-PMWindowSize", "max"], isDebug: true).minimumWindow)
        #expect(LaunchOptions.parse(["app", "-PMAppearance", "light"], isDebug: true).appearance == .light)
        #expect(LaunchOptions.parse(["app", "-PMAppearance", "dark"], isDebug: true).appearance == .dark)
        #expect(LaunchOptions.parse(["app", "-PMAppearance", "sepia"], isDebug: true).appearance == nil)
        #expect(LaunchOptions.parse(["app", "-PMAppearance", "dark"], isDebug: false).appearance == nil)
        #expect(LaunchOptions.parse(["app", "-PMWindowSize", "max"], isDebug: true).windowSize == nil)
        #expect(LaunchOptions.parse(["app", "-PMWindowSize", "default"], isDebug: true).windowSize == .standard)
        #expect(LaunchOptions.parse(["app", "-PMWindowPoints", "1728x1050"], isDebug: true).windowPoints == CGSize(width: 1728, height: 1050))
        #expect(LaunchOptions.parse(["app", "-PMWindowPoints", "big"], isDebug: true).windowPoints == nil)
        let release = LaunchOptions.parse(["app", "-PMA11y", "reduceMotion", "-PMTips", "off", "-PMWindowSize", "min"], isDebug: false)
        #expect(release == LaunchOptions())
    }

    // MARK: §2 Values and rows

    @Test("A11Y-004 AccessibilityText values per row of the table")
    func values() {
        #expect(AccessibilityText.percent(78) == "78 percent")
        #expect(AccessibilityText.noShields == "No shields")
        #expect(AccessibilityText.of(11, 14) == "11 of 14")
        #expect(AccessibilityText.deadline(daysLeft: 3) == "3 days left")
        #expect(AccessibilityText.deadline(daysLeft: 1) == "due tomorrow")
        #expect(AccessibilityText.deadline(daysLeft: 0) == "due today")
        #expect(AccessibilityText.transitClick(7) == "Click 7 of 20")
        #expect(AccessibilityText.units(5) == "5 units")
        #expect(AccessibilityText.units(1) == "1 unit")
        #expect(AccessibilityText.fuelSlider(units: 6, credits: 120) == "6 units, 120 credits")
        #expect(AccessibilityText.repairSlider(points: 40, credits: 200) == "40 hull points, 200 credits")
        #expect(AccessibilityText.textSize(.accessibility3) == "Accessibility 3")
        #expect(AccessibilityText.bridgeSpecialBadge == "Special offer here")
        #expect(AccessibilityText.crewBadge(mercenaries: 3) == "3 mercenaries for hire")
        #expect(AccessibilityText.bankDebtBadge == "Debt warning")
        #expect(AccessibilityText.skills([5, 3, 7, 2]) == "Pilot 5, Fighter 3, Trader 7, Engineer 2")
    }

    @Test("A11Y-007 compound rows: Market, ship card, crew, save slot and high score read as one element with actions")
    func compoundRows() throws {
        let s = try TestSessions.playing(seed: 11)
        let st = try #require(s.state)
        let rows = MarketRowModel.rows(state: st)
        let water = try #require(rows.first { $0.item == .water })
        let m = MarketRowAccessibility.make(water, target: 40)
        #expect(m.label == "Water")
        #expect(m.value.hasPrefix("Buy \(water.buyPrice ?? 0) credits, sell "))
        #expect(m.value.hasSuffix("held 0, target 40 credits (estimate)"))
        #expect(m.actions.map(\.name) == ["Buy 1", "Sell 1", "Buy Max", "Sell All", "Why This Price"])

        let yard = ShipyardModel.make(state: st)
        if let card = yard.cards.first(where: { !$0.isYours }) {
            let a = ShipCardAccessibility.make(card)
            #expect(a.label == String(localized: Names.ship(card.type)))
            #expect(a.actions.map(\.kind) == [.buy, .compare])
        }
        if let mine = yard.cards.first(where: \.isYours) {
            #expect(ShipCardAccessibility.make(mine).value.localizedCaseInsensitiveContains("current ship"))
        }

        let merc = CrewRowAccessibility.make(name: "Alyssa", skills: [5, 3, 7, 2], dailyWage: 24, action: .hire)
        #expect(merc.label == "Alyssa")
        #expect(merc.value == "Pilot 5, Fighter 3, Trader 7, Engineer 2, 24 credits per day")
        #expect(merc.actions.map(\.name) == ["Hire"])
        let seat = CrewModel.Seat(index: 0, occupant: .commander(name: "Jameson", skills: [5, 5, 5, 5]), fireBlocker: nil)
        #expect(CrewRowAccessibility.make(seat)?.actions.isEmpty == true)

        s.save()
        let slot = try #require(try s.slotStore.list().first)
        let slotRow = SaveSlotAccessibility.make(slot)
        #expect(slotRow.label.contains(slot.summary.commander) && slotRow.label.contains("day \(slot.summary.day)"))
        #expect(slotRow.actions.map(\.kind) == [.open, .delete])

        let score = HighScoreRow(rank: 2, entry: .init(name: "Kim", scoreText: "1,234", line: "Retired.", ironman: true, reloaded: true))
        let h = HighScoreRowAccessibility.make(score)
        #expect(h.label == "Rank 2, Kim, score 1,234. Ironman. Reloaded.")
        #expect(HighScoreRowAccessibility.make(HighScoreRow(rank: 3, entry: nil)).label == "Rank 3, empty")
    }

    // MARK: §3 Custom-drawn surfaces

    @Test("A11Y-009 every ArtSurface has its representation")
    func artSurfaces() {
        for surface in ArtSurface.samples {
            switch surface {
            case .galaxyMap, .miniChart: #expect(surface.accessibility == .children)
            case .starfield, .nebula, .welcomeScene, .transitScene, .combatEffects, .gameOverScene, .engineGlow, .crewAvatar:
                #expect(surface.accessibility == .hidden)
            case .glyph(nil): #expect(surface.accessibility == .hidden)
            case .glyph: #expect(surface.accessibility == .label("Water"))
            case .wordmark: #expect(surface.accessibility == .label("Parsec Merchant", header: true))
            case .tribbles: #expect(surface.accessibility == .labelWithAction("12 tribbles aboard", action: "Pet a tribble"))
            case .playerPortrait: #expect(surface.label == "Your Gnat, hull 78%, shields 40%")
            case .opponentPortrait: #expect(surface.label == "Pirate Mosquito, hull 100%, no shields")
            case .bridgePlanet: #expect(surface.label == "Castor, Renaissance, Democracy")
            case let .careerCard(summary), let .chart(summary): #expect(surface.label == summary)
            }
        }
    }

    @Test("A11Y-010 the Encounter portraits of the pirateAmbush fixture carry their labels and update after one Attack")
    func encounterPortraits() throws {
        let s = try TestSessions.make()
        s.install(PirateAmbushScenario.make(), gameID: "ambush", slotID: nil)
        s.send(.warp)
        func labels() throws -> (String, String) {
            let engine = try #require(s.engine)
            let preview = try #require(engine.encounterPreview)
            let player = ShipPaneModel.player(state: engine.state, preview: preview)
            let opponent = try #require(ShipPaneModel.opponent(state: engine.state, preview: preview))
            #expect(player.accessibilityLabel.hasPrefix("Your Gnat, hull \(preview.playerHullPercent)%"))
            #expect(opponent.accessibilityLabel.hasPrefix("Pirate "))
            #expect(opponent.accessibilityLabel.contains("hull \(preview.opponentHullPercent)%"))
            return (player.accessibilityLabel, opponent.accessibilityLabel)
        }
        let before = try labels()
        s.send(.encounter(.attack))
        let after = try labels()
        #expect(before != after, "a hit changes a percentage")
    }

    // MARK: §4 Announcements

    @Test("A11Y-011 one announcement per step, joined, with high priority for combat outcomes and game over")
    func announcementText() throws {
        let s = try TestSessions.playing(seed: 11)
        let recorder = RecordingAnnouncer()
        s.announcer = recorder
        s.sendFromKeyboard(.buyCargo(.water, quantity: 2))
        #expect(recorder.texts.count == 1 && recorder.priorities == [.normal])
        s.send(.retire)
        TestSessions.resolvePresentation(s)
        #expect(recorder.priorities.last == .high)
        #expect(recorder.texts.count == 2)
        let st = try #require(s.state)
        let step = StepRecord(command: .warp, acknowledged: [], before: st, result: StepResult(events: [.uneventfulTrip]), after: st)
        #expect(AnnouncementText.make(step: step, before: st, after: st, context: .init()) == nil)
        let joined = AnnouncementText.make(step: step, before: st, after: st,
                                           context: .init(combat: "R1  You hit.", extras: ["Achievement unlocked: X."]))
        #expect(joined == Announcement(text: "R1  You hit. Achievement unlocked: X.", priority: .normal))
    }

    @Test("A11Y-012 announcement inventory: keyboard trades, fuel, repair, rejections, arrival, save, achievements, game over")
    func announcementInventory() throws {
        let s = try TestSessions.playing(seed: 11)
        let r = RecordingAnnouncer()
        s.announcer = r
        // Clicked buttons whose result shows in place do not announce.
        s.send(.buyCargo(.water, quantity: 1))
        #expect(r.texts.isEmpty)
        let st = try #require(s.state)
        let price = try #require(st.marketRows.first { $0.item == .water }).buyPrice
        s.sendFromKeyboard(.buyCargo(.water, quantity: 5))
        #expect(r.texts.last == "Bought 5 Water for \(price * 5) credits.")
        s.sendFromKeyboard(.sellCargo(.water, quantity: 3))
        #expect(r.texts.last?.hasPrefix("Sold 3 Water for ") == true)
        s.sendFromKeyboard(.sellCargo(.robots, quantity: 1))
        #expect(r.texts.last == ReasonText.string(for: try #require(s.lastRejection)))
        try TestSessions.edit(s) { $0.commander.ship.fuel = 2 }
        s.sendFromKeyboard(.buyFuel(credits: try #require(s.state).fullTankCost))
        let fuelState = try #require(s.state)
        #expect(r.texts.last == "Refuelled, \(fuelState.fuelCapacity) of \(fuelState.fuelCapacity).")
        try TestSessions.edit(s) { $0.commander.ship.hull = 10 }
        s.sendFromKeyboard(.repairHull(credits: try #require(s.state).fullRepairCost))
        #expect(r.texts.last == "Hull repaired, 100 percent.")
        s.save()
        #expect(r.texts.last == "Game saved.")
        #expect(AnnouncementText.exported == "Game exported.")
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        let arrived = try #require(s.state)
        #expect(r.texts.last?.hasPrefix("Arrived at \(Names.system(arrived.commander.currentSystem, in: arrived)), day 1.") == true)
        #expect(AnnouncementText.achievement(.firstProfit) == "Achievement unlocked: First Profit.")
        s.send(.retire)
        TestSessions.resolvePresentation(s)
        #expect(r.texts.last?.contains("You retired.") == true && r.texts.last?.contains("Score") == true)
    }

    @Test("A11Y-012 an interrupted transit announces the encounter intro; an achievement joins its step")
    func announcementEncounterAndAchievement() throws {
        let s = try TestSessions.make()
        let r = RecordingAnnouncer()
        s.announcer = r
        s.install(PirateAmbushScenario.make(), gameID: "ambush", slotID: nil)
        s.send(.warp)
        let intro = try #require(s.encounterUI.intro)
        #expect(r.texts.last?.contains(intro.headline) == true)

        let a = try LogbookTests.sessionWithAchievements(seed: AchievementFixtures.seed)
        let ra = RecordingAnnouncer()
        a.announcer = ra
        a.requestQuickStart()
        a.send(.buyCargo(AchievementFixtures.item, quantity: 1))
        a.send(.selectNextTarget(forward: true))
        a.send(.warp)
        a.send(.sellCargo(AchievementFixtures.item, quantity: 1))
        #expect(ra.texts.last == "Achievement unlocked: First Profit.")
    }

    // MARK: §5 Rotors

    @Test("A11Y-014 the Market and Quests rotors' entries in order")
    func rotors() throws {
        let s = try TestSessions.playing(seed: 11)
        s.send(.buyCargo(.furs, quantity: 1))
        s.send(.buyCargo(.water, quantity: 1))
        let st = try #require(s.state)
        let rows = MarketRowModel.rows(state: st)
        #expect(MarketRotors.inHold(rows) == [.water, .furs])
        let profitable = MarketRotors.profitableAtTarget(rows) { item in item == .ore ? 10_000 : item == .water ? 1 : nil }
        #expect(profitable == (rows.first { $0.item == .ore }?.buyPrice != nil ? [.ore] : []))
        func card(_ i: Int, _ days: Int?) -> QuestsModel.Card {
            QuestsModel.Card(index: i, entry: QuestLogEntry(kind: .gemulonFuel, systems: [], daysLeft: days), steps: nil, deadlineSpan: nil)
        }
        #expect(QuestRotors.deadlines([card(0, 9), card(1, nil), card(2, 3), card(3, 9)]) == [2, 0, 3])
        #expect(QuestRotors.deadlineCards([card(5, 9), card(7, 1)]).map(\.index) == [7, 5])
    }

    @Test("A11Y-005 hints for Market +/−, Warp, Resolve and Fill Up / Repair")
    func hints() throws {
        #expect(AccessibilityHints.tradeModifiers == "Shift for 5, Command for 20, Shift-Command for 100, Option for all")
        #expect(AccessibilityHints.warp(to: "Castor") == "Warps to Castor. Warping can't be undone.")
        #expect(AccessibilityHints.resolve == "Attacks until the encounter is resolved")
        #expect(AccessibilityHints.fillUp == "Buys as much as you can afford")
        // The Market row actions send the trade they name.
        let s = try TestSessions.playing(seed: 11)
        let st = try #require(s.state)
        let row = try #require(MarketRowModel.rows(state: st).first { $0.item == .water })
        #expect(MarketRowAccessibility.command(.buyOne, row: row) == .buyCargo(.water, quantity: 1))
        #expect(MarketRowAccessibility.command(.whyThisPrice, row: row) == nil)
    }

    // MARK: §6 Display settings

    @Test("A11Y-016 MotionPolicy: Reduce Motion is nil or opacity ≤ 0.2 s; springs settle within 0.35 s")
    func motionPolicy() {
        for site in MotionSite.allCases {
            let reduced = MotionPolicy.spec(for: site, prefs: AccessibilityPreferences(reduceMotion: true))
            switch reduced {
            case .none: break
            case let .opacity(d): #expect(d <= MotionPolicy.maximumReducedOpacity, "\(site)")
            case .spring, .continuous: Issue.record("\(site) moves under Reduce Motion")
            }
            #expect(!MotionPolicy.runsContinuously(site, prefs: AccessibilityPreferences(reduceMotion: true)))
            let normal = MotionPolicy.spec(for: site, prefs: .standard)
            if case let .spring(settle) = normal { #expect(settle <= MotionPolicy.maximumSpring, "\(site)") }
        }
        #expect(MotionPolicy.spec(for: .transitPlayback, prefs: .standard) == .continuous)
        #expect(MotionPolicy.spec(for: .sectionSwitch, prefs: .standard) == MotionSpec.none)
        #expect(MotionPolicy.animation(for: .mapViewport, prefs: AccessibilityPreferences(reduceMotion: true)) == nil)
        #expect(MotionPolicy.animation(for: .mapViewport, prefs: .standard) != nil)
    }

    @Test("A11Y-018 ContrastStyle for both settings")
    func contrastStyle() {
        let normal = ContrastStyle.make(prefs: .standard)
        #expect(normal.mapStrokeScale == 1 && normal.barOutlineWidth == 1 && normal.chartLineWidth == 1.5)
        #expect(!normal.highContrastSignals && normal.cardBorderWidth == 0 && !normal.keyNumbersPrimary)
        let ic = ContrastStyle.make(prefs: AccessibilityPreferences(increaseContrast: true))
        #expect(ic.mapStrokeScale == 2 && ic.barOutlineWidth == 2 && ic.chartLineWidth == 2.5)
        #expect(ic.highContrastSignals && ic.cardBorderWidth == 1 && ic.keyNumbersPrimary)
    }

    @Test("A11Y-019 OverlayBackground is a material normally and opaque with Reduce Transparency")
    func overlayBackground() {
        #expect(OverlayBackground.make(prefs: .standard) == .material)
        #expect(OverlayBackground.make(prefs: AccessibilityPreferences(reduceTransparency: true)) == .opaque)
    }

    @Test("A11Y-021 every ColorSignal has an always-on twin; Differentiate Without Color adds the listed extras")
    func colorSignals() {
        let extras: Set<ColorSignal> = [.inRange, .heatmapScale, .hullCritical, .shieldsDown]
        let dwc = AccessibilityPreferences(differentiateWithoutColor: true)
        for signal in ColorSignal.allCases {
            switch signal.twin {
            case let .symbol(name): #expect(!name.isEmpty)
            case let .text(t), let .shape(t): #expect(!String(localized: t).isEmpty)
            case let .symbolAndText(name, t): #expect(!name.isEmpty && !String(localized: t).isEmpty)
            }
            #expect((signal.extra(prefs: dwc) != nil) == extras.contains(signal), "\(signal)")
            #expect(signal.extra(prefs: .standard) == nil)
        }
    }

    // MARK: §7 Text Size

    @Test("A11Y-024 Text Size reaches accessibility3 and scales text on macOS (dynamicTypeSize or the app text scale)")
    func textSizeGuard() throws {
        #expect(TextSizeSetting.allCases.first == .small)
        #expect(TextSizeSetting.allCases.last == .accessibility3)
        #expect(TextSizeSetting.allCases.last?.dynamicTypeSize == .accessibility3)
        func height(_ view: some View) -> CGFloat {
            ImageRenderer(content: view.fixedSize()).nsImage?.size.height ?? 0
        }
        // The guard: does `.dynamicTypeSize` change a text style on this OS?
        let large = height(Text(verbatim: "Parsec").font(.body).dynamicTypeSize(.large))
        let biggest = height(Text(verbatim: "Parsec").font(.body).dynamicTypeSize(.accessibility3))
        #expect(large > 0)
        if biggest < large * 1.5 {
            // BLOCKED: dynamicTypeSize has no effect on macOS — the spec's fallback, the app text scale, must carry Text Size.
            print("BLOCKED: dynamicTypeSize has no effect on macOS (\(large) → \(biggest)); using the app text scale (TextScale.swift)")
        }
        // The fallback behind the same setting: `AppTextSize`'s scale applied through `scaledFont`.
        func scaled(_ setting: TextSizeSetting) -> CGFloat {
            height(Text(verbatim: "Parsec").scaledFont(.body).environment(\.textScale, setting.scale))
        }
        #expect(scaled(.accessibility3) >= scaled(.large) * 1.5, "the largest Text Size renders at least 1.5× taller")
        #expect(scaled(.small) < scaled(.large))
        let scales = TextSizeSetting.allCases.map(\.scale)
        #expect(scales == scales.sorted() && Set(scales).count == scales.count)
    }
}
