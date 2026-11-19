// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import ParsecInsights
import SwiftUI
import Testing
@testable import ParsecMerchant

/// The game states the Bridge layout is proved in (UI-BRG-032).
@MainActor
enum BridgeFixtures {
    enum Case: String, CaseIterable {
        case newGame, fullHold, debt, wormhole, notices, longStrings
    }

    static func session(ruleset: RulesetID, _ fixture: Case, seed: UInt64 = 11) throws -> GameSession {
        let s = try TestSessions.make(seed: seed)
        var config = s.quickStartConfig()
        config.ruleset = ruleset
        #expect(s.startNewGame(config) == nil)
        try TestSessions.edit(s) { state in apply(fixture, to: &state) }
        return s
    }

    // One fixture per case; each is a list of plain assignments.
    static func apply(_ fixture: Case, to state: inout GameState) {
        let here = state.commander.currentSystem
        switch fixture {
        case .newGame:
            break
        case .fullHold:
            // All ten goods held, the hold full, and 8-digit cash.
            let bays = state.commander.ship.cargoBays(state.ruleset)
            var cargo = Array(repeating: 1, count: TradeItemType.allCases.count)
            cargo[0] += max(0, bays - cargo.count)
            state.commander.ship.cargo = cargo
            state.commander.priceCargo = cargo.enumerated().map { $1 * (1_000 + 437 * $0) }
            state.commander.cash = 12_345_678
            if let target = state.destinations.first { state.warpSystem = target }
        case .debt:
            state.commander.debt = 87_654_321 / 1_000
            state.commander.cash = 420
            state.commander.ship.escapePod = true
            state.commander.insurance = true
            state.commander.noClaim = 5
            state.commander.ship.type = .grasshopper
            state.commander.ship.crew = [state.commander.ship.crew.first ?? 0, 1, 2]
            state.commander.ship.hull = max(1, state.commander.ship.hull / 5)
            if let target = state.destinations.first { state.warpSystem = target }
        case .wormhole:
            let hole = state.galaxy.wormholes.first ?? here
            state.commander.currentSystem = hole
            state.galaxy.systems[hole].visited = true
            let far = state.galaxy.systems.indices.max { distance(state, hole, $0) < distance(state, hole, $1) } ?? hole
            state.warpSystem = far
            state.trackedSystem = state.galaxy.systems.indices.first { $0 != far && $0 != hole && distance(state, hole, $0) > 40 } ?? far
            state.commander.ship.fuel = 3
        case .notices:
            // A special offer, two mercenaries for hire, a quest deadline and the newspaper.
            for event in SpecialEventType.allCases where state.specialEventAvailable == nil {
                state.galaxy.systems[here].specialEvent = event
            }
            for id in state.mercenaries.indices.dropFirst().prefix(2) { state.mercenaries[id].systemID = here }
            state.quests.gemulon = QuestStatus.Gemulon.started + 2
            state.quests.experiment = QuestStatus.Experiment.started + 1
            if let target = state.destinations.first { state.warpSystem = target }
        case .longStrings:
            longStrings(&state)
        }
    }

    static func distance(_ state: GameState, _ a: Int, _ b: Int) -> Int {
        let p = state.galaxy.systems[a], q = state.galaxy.systems[b]
        return (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)
    }

    static func longest<T>(_ values: [T], _ text: (T) -> String) -> T {
        values.max { text($0).count < text($1).count } ?? values[0]
    }

    /// UI-BRG-034: the longest system, government, tech level, size, resource and pressure names of the ruleset, here and
    /// at the target, with every good held and large numbers.
    static func longStrings(_ state: inout GameState) {
        let byName = state.galaxy.systems.indices.sorted { Names.system($0, in: state).count > Names.system($1, in: state).count }
        let here = byName[0], target = byName[1]
        state.commander.currentSystem = here
        state.warpSystem = target
        state.trackedSystem = byName[2]
        let politics = longest(PoliticalSystemType.allCases) { String(localized: SystemText.government($0)) }
        for index in [here, target] {
            state.galaxy.systems[index].visited = true
            state.galaxy.systems[index].politics = politics
            state.galaxy.systems[index].techLevel = longest(TechLevel.allCases) { String(localized: SystemText.techLevel($0)) }
            state.galaxy.systems[index].size = longest(SystemSize.allCases) { String(localized: Names.size($0)) }
            state.galaxy.systems[index].specialResource = longest(SpecialResource.allCases) { String(localized: SystemText.resource($0)) }
            state.galaxy.systems[index].pressure = longest(SystemPressure.allCases) { $0 == .none ? "" : String(localized: SystemText.pressure($0) ?? "") }
        }
        apply(.fullHold, to: &state)
        state.warpSystem = target
        state.commander.debt = 99_999
        state.commander.ship.hull = 1
    }
}

/// UI-BRG-030…035: the Bridge fits. Every element of the manifest is present, inside its region, at its natural size,
/// not overlapping, with a 36 pt target, at every size, in every ruleset and state, and nothing scrolls.
@MainActor
@Suite("Bridge layout (UI-BRG)", .serialized)
struct BridgeLayoutTests {
    static let sizes = [CGSize(width: 1200, height: 680), CGSize(width: 1204, height: 700), CGSize(width: 1280, height: 800),
                        CGSize(width: 1440, height: 860), CGSize(width: 1728, height: 1050), CGSize(width: 2056, height: 1290),
                        CGSize(width: 2560, height: 1380)]

    /// The Bridge in the game area of a window of `size`: the window less the dock bar (44) and the status bar (36).
    static func render(_ session: GameSession, window size: CGSize) -> (view: NSView, elements: [String: ShellRender.Element], scale: CGFloat, area: CGSize) {
        let scale = PMScale.scale(for: size)
        let area = CGSize(width: size.width, height: size.height - 80 * scale)
        let view = BridgeView().environment(\.pmScale, scale).environment(\.textScale, scale).environment(\.colorScheme, .dark)
            .background(PMColor.space).modifier(SceneAccessibility())
        let (hosting, elements) = ShellRender.probe(view, session: session, size: area)
        return (hosting, elements, scale, area)
    }

    /// The assertions of UI-BRG-032 for one render; returns the problems found.
    static func problems(_ e: [String: ShellRender.Element], view: NSView, scale: CGFloat, area: CGSize) -> [String] {
        var out: [String] = []
        let bounds = CGRect(origin: .zero, size: area).insetBy(dx: -0.5, dy: -0.5)
        // 1. Nothing missing.
        let missing = BridgeManifest.all.filter { e[$0] == nil }
        if !missing.isEmpty { out.append("missing: \(missing.prefix(6))") }
        // 2. Positive sizes, inside the region, the region inside the game area.
        for region in BridgeManifest.regions {
            guard let frame = e[region]?.frame else { continue }
            if !bounds.contains(frame) { out.append("\(region) \(frame) leaves the game area") }
        }
        for id in BridgeManifest.all {
            guard let frame = e[id]?.frame else { continue }
            if frame.width <= 0 || frame.height <= 0 { out.append("\(id) is empty \(frame)") }
            if let region = BridgeManifest.region(of: id), let outer = e[region]?.frame, !outer.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                out.append("\(id) \(frame.integral) leaves \(region) \(outer.integral)")
            }
        }
        // 3. No overlaps: the regions; the rows; the elements of each region except the containers.
        out += overlaps(BridgeManifest.regions, e)
        out += overlaps(TradeItemType.allCases.map(BridgeID.Cargo.row), e)
        out += overlaps(BridgeID.System.all, e)
        out += overlaps(BridgeID.Target.all, e)
        out += overlaps(BridgeID.Cargo.summary, e)
        for item in TradeItemType.allCases {
            let ids = Array(BridgeID.Cargo.cells(item).dropFirst()) + BridgeID.Cargo.controls(item)
            out += overlaps(ids, e)
            // Every cell and control of a row lies inside the row.
            if let row = e[BridgeID.Cargo.row(item)]?.frame {
                for id in ids where !(e[id].map { row.insetBy(dx: -0.5, dy: -0.5).contains($0.frame) } ?? true) {
                    out.append("\(id) \(e[id]?.frame.integral ?? .zero) leaves its row \(row.integral)")
                }
            }
        }
        // 5. Nothing scrolls.
        if ShellRender.descendants(of: view).contains(where: { $0 is NSScrollView }) { out.append("an NSScrollView is in the Bridge") }
        // 6. Every control has a 36 pt target.
        for id in BridgeManifest.controls {
            guard let frame = e[id]?.frame else { continue }
            if min(frame.width, frame.height) < 36 * scale - 0.5 { out.append("\(id) target \(frame.size) is under \(36 * scale)") }
        }
        return out
    }

    static func overlaps(_ ids: [String], _ e: [String: ShellRender.Element]) -> [String] {
        var out: [String] = []
        let frames = ids.compactMap { id in e[id].map { (id, $0.frame.insetBy(dx: 0.5, dy: 0.5)) } }
        for i in frames.indices {
            for j in frames.indices where j > i && frames[i].1.intersects(frames[j].1) {
                out.append("\(frames[i].0) \(frames[i].1.integral) overlaps \(frames[j].0) \(frames[j].1.integral)")
            }
        }
        return out
    }

    @Test("UI-BRG-032 UI-BRG-001 UI-BRG-020 the Bridge fits at 7 sizes × 3 rulesets × 5 states; UI-BRG-035 the manifest never changes with size")
    func fits() throws {
        var combinations = 0
        for ruleset in RulesetID.allCases {
            for fixture in BridgeFixtures.Case.allCases where fixture != .longStrings {
                let session = try BridgeFixtures.session(ruleset: ruleset, fixture)
                var identifiers: Set<String>?
                for size in Self.sizes {
                    let r = Self.render(session, window: size)
                    let problems = Self.problems(r.elements, view: r.view, scale: r.scale, area: r.area)
                    #expect(problems.isEmpty, "\(ruleset) \(fixture) \(Int(size.width))×\(Int(size.height)): \(problems.prefix(8))")
                    let found = Set(r.elements.keys.filter { $0.hasPrefix("bridge.") })
                    if let identifiers { #expect(found == identifiers, "UI-BRG-035 \(ruleset) \(fixture) \(size)") } else { identifiers = found }
                    combinations += 1
                }
            }
        }
        print("BridgeLayoutTests: \(combinations) size × ruleset × state combinations checked")
        #expect(combinations == 105)
    }

    @Test("UI-BRG-034 the longest names of each ruleset fit at the minimum size and above")
    func longStrings() throws {
        for ruleset in RulesetID.allCases {
            let session = try BridgeFixtures.session(ruleset: ruleset, .longStrings)
            for size in [Self.sizes[0], Self.sizes[3]] {
                let r = Self.render(session, window: size)
                if size.width == 1200, ruleset == .modern { print("QA picture: \(ShellRender.save(r.view, name: "bridge-long-1200x680"))") }
                let problems = Self.problems(r.elements, view: r.view, scale: r.scale, area: r.area)
                #expect(problems.isEmpty, "\(ruleset) \(size): \(problems.prefix(8))")
            }
        }
    }

    @Test("UI-BRG-031 the manifest: 4 regions, 10 rows of 9 cells and 5 controls, the summary, the facts, gauges, notices, chart and target")
    func manifest() {
        #expect(BridgeManifest.regions.count == 4)
        #expect(BridgeID.Cargo.all.count == 3 + 10 * 14)
        #expect(BridgeID.System.facts.count == 8 && BridgeID.System.gauges.count == 2 && BridgeID.System.services.count == 2
            && BridgeID.System.notices.count == 4)
        #expect(BridgeID.Target.facts.count == 6 && BridgeID.Target.costs.count == 5 && BridgeID.Target.buttons.count == 5)
        #expect(Set(BridgeManifest.all).count == BridgeManifest.all.count, "identifiers are unique")
        #expect(BridgeManifest.all.allSatisfy { $0.hasPrefix("bridge.") })
        #expect(BridgeManifest.controls.allSatisfy(BridgeManifest.all.contains))
    }

    @Test("UI-BRG-032 the layout budget: the four regions tile the game area at the minimum size and the rows stay 36…44 pt")
    func budget() {
        let l = BridgeLayout.make(size: CGSize(width: 1200, height: 600), scale: 1)
        #expect(l.system == CGRect(x: 8, y: 8, width: 776, height: 148) && l.cargo == CGRect(x: 8, y: 164, width: 776, height: 428))
        #expect(l.chart == CGRect(x: 792, y: 8, width: 400, height: 280) && l.target == CGRect(x: 792, y: 296, width: 400, height: 296))
        #expect(l.rowHeight == 36)
        for size in Self.sizes {
            let s = PMScale.scale(for: size)
            let l = BridgeLayout.make(size: CGSize(width: size.width, height: size.height - 80 * s), scale: s)
            #expect(l.rowHeight >= 36 * s - 0.01 && l.rowHeight <= 44 * s + 0.01, "\(size) \(l.rowHeight)")
            #expect(l.chart.width >= 400 * s - 1 && l.system.width >= 776 * s - 1)
        }
    }

    @Test("QA pictures of the Bridge at 1200 × 680, 1440 × 860 and 2056 × 1290")
    func pictures() throws {
        let session = try BridgeFixtures.session(ruleset: .modern, .fullHold)
        for size in [Self.sizes[0], Self.sizes[3], Self.sizes[5]] {
            let hosting = ShellRender.host(GameShellView().modifier(SceneAccessibility()), session: session, size: size)
            print("QA picture: \(ShellRender.save(hosting, name: "bridge-\(Int(size.width))x\(Int(size.height))"))")
        }
    }
}
