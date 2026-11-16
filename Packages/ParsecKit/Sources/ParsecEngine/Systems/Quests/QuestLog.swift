// SPDX-License-Identifier: GPL-2.0-or-later
// The open-quest list (docs/specs/UI-SHELL.md UI-SHELL-121…123): C# Form_ViewQuests.GetQuestStrings and Palm
// QuestEvent.c DrawQuestsForm, as typed entries. The app maps each kind to a localized text.

/// One text of the quest list. Each case stands for exactly one source string (Strings.cs `Quest…`); associated values
/// carry what the text fills in.
public enum QuestLogKind: Sendable, Equatable, Hashable {
    /// "Inform Gemulon about alien invasion within N days." (N ≥ 2)
    case gemulonInformDays(Int)
    case gemulonInformTomorrow
    case gemulonFuel
    /// "Stop Dr. Fehler's experiment at Daled within N days." (N ≥ 2)
    case experimentInformDays(Int)
    case experimentInformTomorrow
    /// Reactor aboard, fuel still OK: "… to Nix for Henry Morgan."
    case reactor
    /// Reactor aboard, burning fuel: "… to Nix before it consumes all its fuel."
    case reactorFuel
    case reactorLaser
    case spaceMonsterKill
    case japoriDeliver
    case dragonflyBaratas, dragonflyMelina, dragonflyRegulas, dragonflyZalkon
    case dragonflyShield
    case princessCentauri, princessInthara, princessQonos
    /// "Transport <princess> from Qonos to Galvon." (the Princess is not aboard).
    case princessReturn(crewID: Int)
    /// "Return <princess> to Galvon."
    case princessReturning(crewID: Int)
    /// The impatient variant of `princessReturning` (unreachable in C#, kept for completeness).
    case princessReturningImpatient(crewID: Int)
    case princessQuantum
    case scarabFind
    /// "Notify the authorities at <system> that the Scarab has been destroyed."
    case scarabNotify(system: Int)
    /// "Get your hull upgraded at <system>."
    case scarabHull(system: Int)
    case sculpture
    case sculptureHiddenBays
    case artifact
    case jarek, jarekImpatient
    case wild, wildImpatient
    case tribbles
    case moon
}

/// An open quest as the quest list shows it.
public struct QuestLogEntry: Sendable, Equatable, Hashable {
    public var kind: QuestLogKind
    /// The systems the text names, in text order (C# made each a hyperlink that selects the system).
    public var systems: [Int]
    /// Days until the deadline where the source counts them (Gemulon, Experiment, Reactor).
    public var daysLeft: Int?

    public init(kind: QuestLogKind, systems: [Int], daysLeft: Int? = nil) {
        self.kind = kind
        self.systems = systems
        self.daysLeft = daysLeft
    }
}

public extension GameState {
    /// UI-SHELL-121/122: the open quests in the order of the ruleset's quest screen (`QuestRules.questLogOrder`).
    var questLog: [QuestLogEntry] {
        switch ruleset.flags.quest.questLogOrder {
        case .csharp: csharpQuestLog
        case .palm: palmQuestLog
        }
    }

    private func eventHeld(_ e: SpecialEventType, at system: Int) -> Bool {
        galaxy.systems.indices.contains(system) && galaxy.systems[system].specialEvent == e
    }

    private var gemulonEntry: QuestLogEntry? {
        let status = quests.gemulon
        guard status > QuestStatus.Gemulon.notStarted, status < QuestStatus.Gemulon.date else { return nil }
        let days = QuestStatus.Gemulon.date - status
        return QuestLogEntry(kind: days == 1 ? .gemulonInformTomorrow : .gemulonInformDays(days), systems: [SystemID.gemulon],
                             daysLeft: days)
    }

    private var experimentEntry: QuestLogEntry? {
        let status = quests.experiment
        guard status > QuestStatus.Experiment.notStarted, status < QuestStatus.Experiment.date else { return nil }
        let days = QuestStatus.Experiment.date - status
        return QuestLogEntry(kind: days == 1 ? .experimentInformTomorrow : .experimentInformDays(days),
                             systems: [SystemID.daled], daysLeft: days)
    }

    /// The reactor aboard; `daysLeft` counts to the meltdown check (QST-REACTOR-013), which C# does not show.
    private var reactorEntry: QuestLogEntry? {
        guard reactorOnBoard else { return nil }
        return QuestLogEntry(kind: quests.reactor == QuestStatus.Reactor.fuelOK ? .reactor : .reactorFuel,
                             systems: [SystemID.nix], daysLeft: QuestStatus.Reactor.date - quests.reactor)
    }

    private var dragonflyStageEntry: QuestLogEntry? {
        switch quests.dragonfly {
        case QuestStatus.Dragonfly.flyBaratas: QuestLogEntry(kind: .dragonflyBaratas, systems: [SystemID.baratas])
        case QuestStatus.Dragonfly.flyMelina: QuestLogEntry(kind: .dragonflyMelina, systems: [SystemID.melina])
        case QuestStatus.Dragonfly.flyRegulas: QuestLogEntry(kind: .dragonflyRegulas, systems: [SystemID.regulas])
        case QuestStatus.Dragonfly.flyZalkon: QuestLogEntry(kind: .dragonflyZalkon, systems: [SystemID.zalkon])
        default: nil
        }
    }

    private static func entry(_ condition: Bool, _ kind: QuestLogKind, _ systems: [Int] = []) -> QuestLogEntry? {
        condition ? QuestLogEntry(kind: kind, systems: systems) : nil
    }

    /// C# `Form_ViewQuests.GetQuestStrings` (Form_ViewQuests.cs:131-266), quirks kept (UI-SHELL-121).
    private var csharpQuestLog: [QuestLogEntry] {
        let q = quests
        var log: [QuestLogEntry?] = []
        log.append(gemulonEntry ?? Self.entry(q.gemulon == QuestStatus.Gemulon.fuel, .gemulonFuel, [SystemID.gemulon]))
        log.append(experimentEntry)
        log.append(reactorEntry
            ?? Self.entry(q.reactor == QuestStatus.Reactor.delivered, .reactorLaser, [SystemID.nix]))
        log.append(Self.entry(q.spaceMonster == QuestStatus.SpaceMonster.atAcamar, .spaceMonsterKill, [SystemID.acamar]))
        log.append(Self.entry(q.japori == QuestStatus.Japori.inTransit, .japoriDeliver, [SystemID.japori]))
        log.append(dragonflyStageEntry
            ?? Self.entry(q.dragonfly == QuestStatus.Dragonfly.destroyed, .dragonflyShield, [SystemID.zalkon]))
        log.append(csharpPrincessEntry)
        log.append(csharpScarabEntry)
        // Quirk: the hidden-compartments entry is keyed on the reactor quest, not the sculpture quest.
        log.append(Self.entry(sculptureOnBoard, .sculpture, [SystemID.endor])
            ?? Self.entry(q.reactor == QuestStatus.Reactor.delivered, .sculptureHiddenBays, [SystemID.endor]))
        log.append(Self.entry(q.artifact == QuestStatus.Artifact.onBoard, .artifact))
        log.append(Self.entry(jarekOnBoard, q.jarek == QuestStatus.Jarek.impatient ? .jarekImpatient : .jarek,
                              [SystemID.devidia]))
        log.append(Self.entry(wildOnBoard, q.wild == QuestStatus.Wild.impatient ? .wildImpatient : .wild, [SystemID.kravat]))
        log.append(Self.entry(commander.ship.tribbles > 0, .tribbles))
        log.append(Self.entry(q.moon == QuestStatus.Moon.bought, .moon, [SystemID.utopia]))
        return log.compactMap { $0 }
    }

    /// The C# Princess switch: an entry only at the exact statuses it names, so none while she counts towards
    /// impatience (status 5…14), and the impatient text is unreachable under `rescued`.
    private var csharpPrincessEntry: QuestLogEntry? {
        let princess = CrewID.princess
        switch quests.princess {
        case QuestStatus.Princess.flyCentauri: return QuestLogEntry(kind: .princessCentauri, systems: [SystemID.centauri])
        case QuestStatus.Princess.flyInthara: return QuestLogEntry(kind: .princessInthara, systems: [SystemID.inthara])
        case QuestStatus.Princess.flyQonos: return QuestLogEntry(kind: .princessQonos, systems: [SystemID.qonos])
        case QuestStatus.Princess.rescued:
            guard princessOnBoard else {
                return QuestLogEntry(kind: .princessReturn(crewID: princess), systems: [SystemID.qonos, SystemID.galvon])
            }
            let impatient = quests.princess == QuestStatus.Princess.impatient
            return QuestLogEntry(kind: impatient ? .princessReturningImpatient(crewID: princess)
                                     : .princessReturning(crewID: princess), systems: [SystemID.galvon])
        case QuestStatus.Princess.returned: return QuestLogEntry(kind: .princessQuantum, systems: [SystemID.galvon])
        default: return nil
        }
    }

    /// C#: hunting, else (destroyed) the hull upgrade where it is offered, else the notice where the Scarab died.
    private var csharpScarabEntry: QuestLogEntry? {
        switch quests.scarab {
        case QuestStatus.Scarab.hunting: return QuestLogEntry(kind: .scarabFind, systems: [])
        case QuestStatus.Scarab.destroyed:
            if let hull = galaxy.systems.firstIndex(where: { $0.specialEvent == .scarabUpgradeHull }) {
                return QuestLogEntry(kind: .scarabHull(system: hull), systems: [hull])
            }
            guard let site = galaxy.systems.firstIndex(where: { $0.specialEvent == .scarabDestroyed }) else { return nil }
            return QuestLogEntry(kind: .scarabNotify(system: site), systems: [site])
        default: return nil
        }
    }

    /// Palm `DrawQuestsForm` (Src/QuestEvent.c:94-238, UI-SHELL-122).
    private var palmQuestLog: [QuestLogEntry] {
        let q = quests
        var log: [QuestLogEntry?] = []
        log.append(Self.entry(q.spaceMonster == QuestStatus.SpaceMonster.atAcamar, .spaceMonsterKill, [SystemID.acamar]))
        log.append(dragonflyStageEntry
            ?? Self.entry(eventHeld(.dragonflyShield, at: SystemID.zalkon), .dragonflyShield, [SystemID.zalkon]))
        log.append(Self.entry(q.japori == QuestStatus.Japori.inTransit, .japoriDeliver, [SystemID.japori]))
        log.append(Self.entry(artifactOnBoard, .artifact))
        log.append(Self.entry(wildOnBoard, .wild, [SystemID.kravat]))
        log.append(Self.entry(jarekOnBoard, .jarek, [SystemID.devidia]))
        log.append(gemulonEntry
            ?? Self.entry(eventHeld(.gemulonFuel, at: SystemID.gemulon), .gemulonFuel, [SystemID.gemulon]))
        log.append(experimentEntry)
        log.append(reactorEntry)
        log.append(Self.entry(eventHeld(.reactorLaser, at: SystemID.nix), .reactorLaser, [SystemID.nix]))
        log.append(Self.entry(q.scarab == QuestStatus.Scarab.hunting, .scarabFind))
        log.append(Self.entry(commander.ship.tribbles > 0, .tribbles))
        log.append(Self.entry(q.moon == QuestStatus.Moon.bought, .moon, [SystemID.utopia]))
        return log.compactMap { $0 }
    }
}
