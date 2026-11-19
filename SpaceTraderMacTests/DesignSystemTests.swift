// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// UI-DS: the design system of the game area (docs/PRD-UI-Revamp.md §3).
@MainActor
@Suite("Design system (UI-DS)")
struct DesignSystemTests {
    @Test("UI-DS-002 the interface scale is clamp(min(W/1200, H/680), floor, 2), stepped down to 0.05")
    func scale() {
        #expect(PMScale.designSize == CGSize(width: 1200, height: 680))
        #expect(PMScale.scale(for: CGSize(width: 1200, height: 680)) == 1)
        #expect(PMScale.scale(for: CGSize(width: 900, height: 500)) == 1, "never below 1")
        #expect(abs(PMScale.scale(for: CGSize(width: 1440, height: 860)) - 1.2) < 1e-9)
        #expect(abs(PMScale.scale(for: CGSize(width: 1500, height: 2000)) - 1.25) < 1e-9, "the tighter axis decides")
        #expect(abs(PMScale.scale(for: CGSize(width: 1290, height: 2000)) - 1.05) < 1e-9, "1.075 steps down to 1.05")
        #expect(PMScale.scale(for: CGSize(width: 9000, height: 9000)) == 2)
        #expect(abs(PMScale.scale(for: CGSize(width: 1200, height: 680), floor: 1.3) - 1.3) < 1e-9, "the Text Size floor")
        #expect(PMScale.scale(for: CGSize(width: 3000, height: 1700), floor: 1.3) == 2)
    }

    @Test("UI-DS-003 space beyond the scaled design size changes sizes only: the same elements at every size")
    func sameElements() throws {
        let session = try TestSessions.playing(seed: 11)
        let sets = GameShellTests.sizes.map { Set(GameShellTests.shell(session, size: $0).1.keys) }
        #expect(sets[0] == sets[1] && sets[1] == sets[2] && sets[0].count >= 20)
    }

    @Test("UI-DS-004 Text Size steps set the scale's floor and the window's minimum; a step that does not fit the screen falls back")
    func textSize() {
        #expect(PMScale.textSteps == [1, 1.15, 1.3, 1.5, 2])
        #expect(PMScale.minimumSize(floor: 1) == CGSize(width: 1200, height: 680) && PMScale.minimumSize(floor: 1.5) == CGSize(width: 1800, height: 1020))
        #expect(PMScale.effectiveFloor(wanted: 2, available: CGSize(width: 1470, height: 900)) == 1.15)
        #expect(PMScale.effectiveFloor(wanted: 2, available: CGSize(width: 2560, height: 1400)) == 2)
        #expect(PMScale.effectiveFloor(wanted: 1.3, available: CGSize(width: 1204, height: 700)) == 1)
        #expect(PMScale.effectiveFloor(wanted: 1.3, available: nil) == 1.3)
        #expect(TextSizeSetting.standard.interfaceFloor == 1 && TextSizeSetting.accessibility3.interfaceFloor == 2)
        #expect(TextSizeSetting.allCases.allSatisfy { PMScale.textSteps.contains($0.interfaceFloor) })
    }

    @Test("UI-DS-010 contrast: text at least 7:1 and signals at least 4.5:1 on every panel fill; lines and the accent at least 3:1")
    func contrast() {
        let fills: [PMColor.Token] = [.panel, .panelRaised, .panelInset]
        for fill in fills {
            for text in [PMColor.Token.textPrimary, .textSecondary] {
                #expect(PMColor.rgb(text).contrast(with: PMColor.rgb(fill)) >= 7, "\(text) on \(fill): \(PMColor.rgb(text).contrast(with: PMColor.rgb(fill)))")
            }
        }
        for token in [PMColor.Token.profit, .loss, .caution, .info, .rolePolice, .rolePirate, .roleTrader, .roleAlien, .textDisabled] {
            #expect(PMColor.rgb(token).contrast(with: PMColor.rgb(.panel)) >= 4.5, "\(token): \(PMColor.rgb(token).contrast(with: PMColor.rgb(.panel)))")
        }
        for token in [PMColor.Token.strongLine, .accent] { #expect(PMColor.rgb(token).contrast(with: PMColor.rgb(.panel)) >= 3, "\(token)") }
        // The primary button: dark text on the accent.
        #expect(PMColor.rgb(.space).contrast(with: PMColor.rgb(.accent)) >= 7)
        // The formula itself: black on white is 21:1.
        #expect(abs(PMColor.RGB(0x000000).contrast(with: PMColor.RGB(0xFFFFFF)) - 21) < 1e-9)
    }

    @Test("UI-DS-011 Increase Contrast: hairlines become strong lines, secondary text primary, borders 2 pt")
    func increaseContrast() {
        #expect(PMColor.border(increaseContrast: true) == PMColor.strongLine && PMColor.border(increaseContrast: false) == PMColor.hairline)
        #expect(PMColor.label(increaseContrast: true) == PMColor.textPrimary && PMColor.label(increaseContrast: false) == PMColor.textSecondary)
        #expect(PMColor.borderWidth(increaseContrast: true) == 2 && PMColor.borderWidth(increaseContrast: false) == 1)
    }

    @Test("UI-DS-012 every colour-coded state has a twin that is not colour: tones carry a symbol, signals a symbol, word or shape")
    func neverColourAlone() {
        for tone in PMTone.allCases where tone != .neutral { #expect(tone.symbol != nil, "\(tone)") }
        #expect(Set(PMTone.allCases.compactMap(\.symbol)).count == PMTone.allCases.count - 1, "each tone its own symbol")
        for signal in ColorSignal.allCases {
            switch signal.twin {
            case let .symbol(name): #expect(!name.isEmpty, "\(signal)")
            case let .text(text), let .shape(text): #expect(!String(localized: text).isEmpty, "\(signal)")
            case let .symbolAndText(name, text): #expect(!name.isEmpty && !String(localized: text).isEmpty, "\(signal)")
            }
        }
        #expect(ColorSignal.allCases.count >= 27)
    }

    @Test("UI-DS-020 tokens: spacing on a 4-point grid, two radii, durations within 0.35 s, type no smaller than 11 pt")
    func tokens() {
        #expect(PMSpace.all == [4, 8, 12, 16, 24] && PMSpace.all.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
        #expect(PMRadius.control == 4 && PMRadius.panel == 8)
        #expect([PMMotion.hover, PMMotion.page, PMMotion.value].allSatisfy { $0 <= PMMotion.longest } && PMMotion.longest == 0.35)
        #expect(PMMotion.animation(PMMotion.page, reduceMotion: true) == nil && PMMotion.animation(PMMotion.page, reduceMotion: false) != nil)
        #expect(PMFont.Style.allCases.allSatisfy { $0.size >= 11 })
        #expect(PMFont.Style.title.size == 17 && PMFont.Style.body.size == 13 && PMFont.Style.valueLarge.size == 15)
        #expect(PMColor.Token.allCases.count == 18)
    }

    /// One of each component, in each state, in a row.
    struct Gallery: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ForEach(Array(PMButtonKind.allCases.enumerated()), id: \.offset) { i, kind in
                        PMButton(title: "Warp", kind: kind, key: "⌘J", identifier: "gallery.button.\(i)") {}
                        PMButton(title: "Warp", kind: kind, disabledReason: "No target", identifier: "gallery.disabled.\(i)") {}
                    }
                }
                HStack {
                    PMStat(label: "Cash", value: "99,999,999 cr.", large: true, identifier: "gallery.stat")
                    PMStat(label: "Debt", value: "1,000 cr.", tone: .loss, identifier: "gallery.statLoss")
                    PMBadge(text: "Pirate", symbol: "flag.2.crossed", color: PMColor.rolePirate, identifier: "gallery.badge")
                    PMKeyCap(key: "⇧S")
                    PMNotice(symbol: "newspaper", title: "News", tag: "3 cr.", identifier: "gallery.notice") {}
                    PMNotice(symbol: "star", title: "Special", emptyReason: "No special offer", identifier: "gallery.noticeEmpty") {}
                }
                PMGauge(label: "Hull", fraction: 0.4, valueText: "40%", tone: .caution, identifier: "gallery.gauge").frame(width: 300)
                PMSegmented(options: [(0, "Ships", "gallery.segment.0"), (1, "Designer", "gallery.segment.1")], selection: .constant(0),
                    identifier: "gallery.segmented")
                PMField(text: .constant("12"), prompt: "1", label: "Quantity", identifier: "gallery.field").frame(width: 60)
                PMRow(selected: true, identifier: "gallery.row") { Text(verbatim: "Water").pmFont(.body) }
                HStack {
                    PMDockButton(title: "Bridge", symbol: "scope", key: "⌘1", current: true, identifier: "gallery.dock") {}
                    PMDockButton(title: "Bank", symbol: "building.columns", key: "⌘5", badge: "!", disabledReason: "Unavailable in transit",
                        identifier: "gallery.dockOff") {}
                }
                PMPanel("Target System", identifier: "gallery.panel") {
                    PMEmptyState(symbol: "tray", message: "No ships for sale in this system", identifier: "gallery.empty")
                }
                .frame(height: 120)
            }
            .padding(12)
            .background(PMColor.space)
        }
    }

    @Test("UI-DS-030 UI-DS-031 every component renders in every state without clipping at scale 1, 1.3 and 2; disabled buttons keep their reason")
    func components() throws {
        let session = try TestSessions.playing()
        for scale in [1.0, 1.3, 2.0] {
            let size = CGSize(width: 1100 * scale, height: 560 * scale)
            let (hosting, e) = ShellRender.probe(Gallery().environment(\.pmScale, scale).frame(width: size.width, height: size.height, alignment: .topLeading),
                                                 session: session, size: size)
            if scale == 1 { print("QA components picture: \(ShellRender.save(hosting, name: "components"))") }
            let ids = ["gallery.stat", "gallery.statLoss", "gallery.badge", "gallery.notice", "gallery.noticeEmpty", "gallery.gauge", "gallery.segmented",
                       "gallery.field", "gallery.row", "gallery.dock", "gallery.dockOff", "gallery.panel", "gallery.empty"]
                + (0..<4).flatMap { ["gallery.button.\($0)", "gallery.disabled.\($0)"] }
            for id in ids {
                let element = try #require(e[id], "\(id) at \(scale)")
                #expect(element.frame.width > 0 && element.frame.height > 0, "\(id)")
                #expect(CGRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1).contains(element.frame),
                    "\(id) \(element.frame) is clipped at scale \(scale)")
            }
            // Pointer targets grow with the scale (UI-PTR-002).
            for id in ["gallery.button.0", "gallery.notice", "gallery.dock", "gallery.row"] {
                #expect((e[id]?.frame.height ?? 0) >= PointerTarget.minimum * scale - 1, "\(id) \(e[id]?.frame ?? .zero)")
            }
            for i in 0..<4 { #expect(e["gallery.disabled.\(i)"]?.enabled == false && e["gallery.button.\(i)"]?.enabled == true) }
            #expect(e["gallery.noticeEmpty"]?.enabled == false && e["gallery.dockOff"]?.enabled == false)
        }
        #expect(PMButtonKind.allCases.count == 4)
    }
}
