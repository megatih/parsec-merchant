// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Localized quest-list texts (UI-SHELL-123). The English text of each case is the C# `Quest…` string (Strings.cs)
/// with `^1` filled in as C# did (`Functions.Multiples(n, "day")` for the day counts, the Princess's name).
enum QuestText {
    // An exhaustive mapping over every quest-list text: one line per case, so the case count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    static func title(for kind: QuestLogKind, state: GameState) -> LocalizedStringResource {
        func crew(_ id: Int) -> String { Names.crew(id, in: state) }
        func sys(_ i: Int) -> String { Names.system(i, in: state) }
        switch kind {
        case let .gemulonInformDays(n): return "Inform Gemulon about alien invasion within \(n) days."
        case .gemulonInformTomorrow: return "Inform Gemulon about alien invasion by tomorrow."
        case .gemulonFuel: return "Get your fuel compactor at Gemulon."
        case let .experimentInformDays(n): return "Stop Dr. Fehler's experiment at Daled within \(n) days."
        case .experimentInformTomorrow: return "Stop Dr. Fehler's experiment at Daled by tomorrow."
        case .reactor: return "Deliver the unstable reactor to Nix for Henry Morgan."
        case .reactorFuel: return "Deliver the unstable reactor to Nix before it consumes all its fuel."
        case .reactorLaser: return "Get your special laser at Nix."
        case .spaceMonsterKill: return "Kill the space monster at Acamar."
        case .japoriDeliver: return "Deliver antidote to Japori."
        case .dragonflyBaratas: return "Follow the Dragonfly to Baratas."
        case .dragonflyMelina: return "Follow the Dragonfly to Melina."
        case .dragonflyRegulas: return "Follow the Dragonfly to Regulas."
        case .dragonflyZalkon: return "Follow the Dragonfly to Zalkon."
        case .dragonflyShield: return "Get your lightning shield at Zalkon."
        case .princessCentauri: return "Follow the Scorpion to Centauri."
        case .princessInthara: return "Follow the Scorpion to Inthara."
        case .princessQonos: return "Follow the Scorpion to Qonos."
        case let .princessReturn(id): return "Transport \(crew(id)) from Qonos to Galvon."
        case let .princessReturning(id): return "Return \(crew(id)) to Galvon."
        case let .princessReturningImpatient(id):
            return "Return \(crew(id)) to Galvon.\nShe is becoming anxious to arrive at home, and is no longer of any help in engineering functions."
        case .princessQuantum: return "Get your Quantum Disruptor at Galvon."
        case .scarabFind: return "Find and destroy the Scarab (which is hiding at the exit to a wormhole)."
        case let .scarabNotify(system): return "Notify the authorities at \(sys(system)) that the Scarab has been destroyed."
        case let .scarabHull(system): return "Get your hull upgraded at \(sys(system))."
        case .sculpture: return "Deliver the stolen sculpture to Endor."
        case .sculptureHiddenBays: return "Have hidden compartments installed at Endor."
        case .artifact: return "Deliver the alien artifact to Professor Berger at some hi-tech system."
        case .jarek: return "Take ambassador Jarek to Devidia."
        case .jarekImpatient:
            return """
                Take ambassador Jarek to Devidia.
                Jarek is wondering why the journey is taking so long, and is no longer of much help in negotiating trades.
                """
        case .wild: return "Smuggle Jonathan Wild to Kravat."
        case .wildImpatient:
            return "Smuggle Jonathan Wild to Kravat.\nWild is getting impatient, and will no longer aid your crew along the way."
        case .tribbles: return "Get rid of those pesky tribbles."
        case .moon: return "Claim your moon at Utopia."
        }
    }

    static func string(for kind: QuestLogKind, state: GameState) -> String { String(localized: title(for: kind, state: state)) }

    /// The empty-list text (Strings.cs `QuestNone`).
    static let none: LocalizedStringResource = "There are no open quests."
}
