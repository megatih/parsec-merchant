// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecEngine

/// What the Bridge's system card and the target card show about one system (UI-SHELL-054, -059). Pure over the state.
struct SystemCardModel: Equatable, Sendable {
    static let maxActivityDots = 7

    var index: Int
    var name: String
    var size: SystemSize
    var techLevel: TechLevel
    var government: PoliticalSystemType
    /// The resource the player knows; nil ("Unknown") until the system has been visited (ECO-007, MOD-006).
    var resource: SpecialResource?
    var police: Activity
    var pirates: Activity
    /// The pressure tag; nil when there is none.
    var pressure: SystemPressure?

    static func make(state: GameState, system index: Int) -> SystemCardModel {
        let s = state.galaxy.systems[index]
        let politics = state.ruleset.tables.politics(s.politics)
        return SystemCardModel(index: index, name: Names.system(index, in: state), size: s.size, techLevel: s.techLevel,
                               government: s.politics, resource: s.visited ? s.specialResource : nil,
                               police: politics.activityPolice, pirates: politics.activityPirates,
                               pressure: s.pressure == .none ? nil : s.pressure)
    }

    /// 0…7 filled dots for an activity level.
    static func dots(_ a: Activity) -> Int { a == .na ? 0 : min(maxActivityDots, a.rawValue) }
}

/// One dock service, fuel or hull (UI-SHELL-055, -056). Pure over the state.
struct DockServiceModel: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case fuel, hull }

    var kind: Kind
    /// Fuel units or hull points now, and the maximum.
    var current: Int
    var maximum: Int
    /// Credits per unit of fuel or point of hull.
    var unitCost: Int
    /// Credits to fill the tank or repair the hull completely.
    var fullCost: Int
    var cash: Int

    static func fuel(state: GameState) -> DockServiceModel {
        DockServiceModel(kind: .fuel, current: state.commander.ship.fuel, maximum: state.fuelCapacity,
                         unitCost: state.commander.ship.spec(state.ruleset).fuelCost, fullCost: state.fullTankCost,
                         cash: state.commander.cash)
    }

    static func hull(state: GameState) -> DockServiceModel {
        let ship = state.commander.ship
        return DockServiceModel(kind: .hull, current: ship.hull, maximum: ship.hullStrength(state.ruleset),
                                unitCost: ship.spec(state.ruleset).repairCost, fullCost: state.fullRepairCost,
                                cash: state.commander.cash)
    }

    /// "Tank full" / "No repairs needed": the controls are replaced by this text.
    var isComplete: Bool { current >= maximum }

    /// Hull as a percentage of its strength (the hull gauge).
    var percent: Int { maximum > 0 ? current * 100 / maximum : 0 }

    /// Why the buttons are disabled: complete, or not enough cash for one unit ("Not enough cash.").
    var blocker: CommandError? {
        if isComplete { return kind == .fuel ? .tankFull : .noRepairsNeeded }
        if cash < max(1, unitCost) { return .insufficientFunds }
        return nil
    }

    /// The partial amount's range in credits, `1…min(fullCost, cash)`; nil while the controls are disabled.
    var amountRange: ClosedRange<Int>? {
        guard blocker == nil else { return nil }
        return 1...max(1, min(fullCost, cash))
    }

    /// Fill Up / Repair: the full cost; the engine clamps it to cash (SHP-051, SHP-053).
    var fullCommand: Command { kind == .fuel ? .buyFuel(credits: fullCost) : .repairHull(credits: fullCost) }

    /// The partial purchase, clamped to the range; nil when the amount buys less than one unit.
    func partialCommand(credits: Int) -> Command? {
        guard let range = amountRange else { return nil }
        let amount = min(max(credits, range.lowerBound), range.upperBound)
        guard amount / max(1, unitCost) > 0 else { return nil }
        return kind == .fuel ? .buyFuel(credits: amount) : .repairHull(credits: amount)
    }

    /// The default value of the partial amount (the full cost within the range).
    var defaultAmount: Int { amountRange?.upperBound ?? 0 }
}

/// The special-event card (UI-SHELL-057). Pure over the state.
struct SpecialEventCardModel: Equatable, Sendable {
    var type: SpecialEventType
    /// Credits the player pays (positive) or receives (negative); 0 when free.
    var price: Int
    /// Message-only events show Continue instead of Accept / Decline.
    var messageOnly: Bool

    static func make(state: GameState) -> SpecialEventCardModel? {
        guard let type = state.specialEventAvailable else { return nil }
        let spec = state.specialEventSpec(type)
        return SpecialEventCardModel(type: type, price: spec?.price ?? 0, messageOnly: spec?.messageOnly ?? false)
    }

    /// Identifies one visit (game, day, system): Decline hides the card until the next arrival.
    static func visitToken(gameID: String?, state: GameState) -> String {
        "\(gameID ?? "")|\(state.commander.days)|\(state.commander.currentSystem)"
    }

    /// The card is shown iff an event is offered and it was not declined during this visit.
    static func visible(state: GameState, gameID: String?, declinedToken: String) -> SpecialEventCardModel? {
        guard let model = make(state: state), declinedToken != visitToken(gameID: gameID, state: state) else { return nil }
        return model
    }

    var command: Command { .specialEvent }
}

/// The mercenary card (UI-SHELL-058): "N mercenaries for hire" or the name when there is one.
struct MercenaryCardModel: Equatable, Sendable {
    var crewIDs: [Int]
    var singleName: String?

    static func make(state: GameState) -> MercenaryCardModel? {
        let ids = state.mercenariesForHire
        guard !ids.isEmpty else { return nil }
        return MercenaryCardModel(crewIDs: ids, singleName: ids.count == 1 ? Names.crew(ids[0], in: state) : nil)
    }

    var text: LocalizedStringResource {
        if let singleName { return "\(singleName) is looking for work." }
        return "\(crewIDs.count) mercenaries for hire"
    }
}

/// UI-ENC-072: the newspaper card: the masthead once paid this visit, else "Local newspaper" and the price; Read sends
/// `.readNewspaper` and is disabled with the reason when the paper is unaffordable (ALR-009).
struct NewspaperCardModel: Equatable, Sendable {
    var cost: Int
    var paid: Bool
    var system: Int
    /// The paid paper's masthead (UI-ENC-068).
    var masthead: String?
    /// `insufficientFunds` when the unpaid paper costs more than the funds the engine checks (NEWS-004/005).
    var blocker: CommandError?

    static func make(state: GameState) -> NewspaperCardModel {
        NewspaperCardModel(cost: state.newspaperCost, paid: state.paidForNewspaper, system: state.commander.currentSystem,
                           masthead: state.newspaperPreview.map { NewspaperText.masthead($0, state: state) },
                           blocker: blocker(state: state))
    }

    nonisolated static func blocker(state: GameState) -> CommandError? {
        guard !state.paidForNewspaper else { return nil }
        let funds = state.ruleset.flags.travel.newspaperUsesCashToSpend ? state.cashToSpend : state.commander.cash
        return funds < state.newspaperCost ? .insufficientFunds : nil
    }

    var command: Command { .readNewspaper }
}

/// The target card (UI-SHELL-059, -060). Pure over the state.
struct TargetCardModel: Equatable, Sendable {
    struct Jump: Equatable, Sendable {
        var destination: Int
        var enabled: Bool
        /// The departure check that would fail after the singularity is used up (TRV-021).
        var blocking: CommandError?
        var rejection: CommandError?
    }

    var system: SystemCardModel
    var preview: WarpTargetPreview
    var warp: WarpButtonModel
    var isTracked: Bool
    /// Track / Untrack is shown when the target is out of range, or to stop tracking it.
    var showsTrack: Bool
    /// ‹ › cycle the systems in range (MENU-033).
    var canCycle: Bool
    /// "Wormhole to X" when the target is reached through the current system's wormhole.
    var viaWormhole: Bool
    var jump: Jump?

    /// nil while no target is chosen (the target is the current system).
    static func make(state: GameState, isModal: Bool) -> TargetCardModel? {
        let target = state.warpSystem
        let canCycle = !state.destinations.isEmpty
        let jump: Jump? = state.quests.canSuperWarp ? {
            let j = state.jumpPreview
            return Jump(destination: j.destination, enabled: j.available, blocking: j.blocking, rejection: j.rejection)
        }() : nil
        guard target != state.commander.currentSystem else {
            return jump.map { _ in
                TargetCardModel(system: .make(state: state, system: target), preview: state.warpTargetPreview(target),
                                warp: WarpButtonModel.make(state: state, isModal: isModal), isTracked: false, showsTrack: false,
                                canCycle: canCycle, viaWormhole: false, jump: jump)
            }
        }
        let preview = state.warpTargetPreview(target)
        let tracked = state.trackedSystem == target
        return TargetCardModel(system: .make(state: state, system: target), preview: preview,
                               warp: WarpButtonModel.make(state: state, isModal: isModal), isTracked: tracked,
                               showsTrack: !preview.inRange || tracked, canCycle: canCycle, viaWormhole: preview.viaWormhole,
                               jump: jump)
    }

    /// MENU-034: track the target, or stop tracking it.
    var trackCommand: Command { .track(isTracked ? nil : system.index) }
}

/// The toolbar target picker's entries (UI-SHELL-041): `destinations` by distance, then by name.
enum TargetPickerModel {
    struct Entry: Equatable, Sendable {
        var index: Int
        var name: String
        var distance: Int
    }

    static func entries(state: GameState) -> [Entry] {
        state.destinations
            .map { Entry(index: $0, name: Names.system($0, in: state), distance: state.warpTargetPreview($0).distance) }
            .sorted { ($0.distance, $0.name) < ($1.distance, $1.name) }
    }

    /// The wormhole entry ("Wormhole to X", sends `.selectWormhole(current)`), when the current system has one.
    static func wormhole(state: GameState) -> (destination: Int, command: Command)? {
        let cur = state.commander.currentSystem
        guard let w = state.galaxy.wormholeDestination(from: cur) else { return nil }
        return (w, .selectWormhole(cur))
    }
}

/// The galaxy code on the Bridge (UI-SHELL-103) and its Copy button.
enum GalaxyCodeCard {
    static func code(state: GameState) -> String { GalaxyCode(state).string }

    /// Writes the code to the pasteboard (the general one from the view; tests pass a private one).
    @discardableResult
    static func copy(_ code: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(code, forType: .string)
    }
}
