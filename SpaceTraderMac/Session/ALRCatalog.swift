// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-004: the class column of ALR §4.
enum ALRClass: String, CaseIterable, Sendable {
    case commandError, confirmation, gameEvent, critical, narrative, systemAlert, removed

    /// The class as written in the ALR §4 table.
    var tableName: String {
        switch self {
        case .commandError: "CommandError"
        case .confirmation: "Confirmation"
        case .gameEvent: "GameEvent"
        case .critical: "GameEvent (critical)"
        case .narrative: "Narrative"
        case .systemAlert: "SystemAlert"
        case .removed: "Removed"
        }
    }
}

/// Advisory notes rendered like inline reasons (ALR §2 "CommandError": `preview` notes that block nothing).
enum PreviewNote: String, CaseIterable, Sendable {
    /// ALR-140: the purchase sheet's footer when not every transfer is affordable.
    case cannotAffordAllTransfers
    /// ALR-179: the Shipyard's trade-in footer while tribbles are aboard.
    case tribblesTradeIn
    /// ALR-021: Jump is disabled via `jumpPreview` (the classic alert cannot occur).
    case jumpNoTarget
}

/// `PendingDecision` cases without payloads.
enum PendingDecisionKind: String, CaseIterable, Sendable {
    case confirm, tradeInOrbit, plunder, scoop, newspaper

    init(_ d: PendingDecision) {
        switch d {
        case .confirm: self = .confirm
        case .tradeInOrbit: self = .tradeInOrbit
        case .plunder: self = .plunder
        case .scoop: self = .scoop
        case .newspaper: self = .newspaper
        }
    }
}

/// `AppConfirmation` cases without payloads, with a sample value each.
enum AppConfirmationKind: String, CaseIterable, Sendable {
    case discardUnsavedGame, revertToAutosave, deleteSlot, loadImportedSave, clearHighScores, timewarpLoad, closeGame
    case resetAchievements

    init(_ c: AppConfirmation) {
        switch c {
        case .discardUnsavedGame: self = .discardUnsavedGame
        case .revertToAutosave: self = .revertToAutosave
        case .deleteSlot: self = .deleteSlot
        case .loadImportedSave: self = .loadImportedSave
        case .clearHighScores: self = .clearHighScores
        case .timewarpLoad: self = .timewarpLoad
        case .closeGame: self = .closeGame
        case .resetAchievements: self = .resetAchievements
        }
    }

    var sample: AppConfirmation {
        switch self {
        case .discardUnsavedGame: .discardUnsavedGame
        case .revertToAutosave: .revertToAutosave
        case .deleteSlot: .deleteSlot("sample")
        case .loadImportedSave: .loadImportedSave("sample")
        case .clearHighScores: .clearHighScores(.modern)
        case .timewarpLoad: .timewarpLoad(reloaded: false)
        case .closeGame: .closeGame
        case .resetAchievements: .resetAchievements
        }
    }
}

/// `SystemAlert` cases without payloads, with a sample value each.
enum SystemAlertKind: String, CaseIterable, Sendable {
    case saveFailed, openFailed, nothingToContinue

    init(_ a: SystemAlert) {
        switch a {
        case .saveFailed: self = .saveFailed
        case .openFailed: self = .openFailed
        case .nothingToContinue: self = .nothingToContinue
        }
    }

    var sample: SystemAlert {
        switch self {
        case .saveFailed: .saveFailed(reason: "The disk is full.")
        case .openFailed: .openFailed(reason: "The file is damaged.", suggestion: "Try a backup.")
        case .nothingToContinue: .nothingToContinue
        }
    }
}

/// `HighScoreOutcome` cases without payloads, with a sample value each.
enum HighScoreOutcomeKind: String, CaseIterable, Sendable {
    case entered, missed, excludedForCheats, excludedForReload

    init(_ o: HighScoreOutcome) {
        switch o {
        case .entered: self = .entered
        case .missed: self = .missed
        case .excludedForCheats: self = .excludedForCheats
        case .excludedForReload: self = .excludedForReload
        }
    }

    var sample: HighScoreOutcome {
        switch self {
        case .entered: .entered(rank: 3)
        case .missed: .missed
        case .excludedForCheats: .excludedForCheats
        case .excludedForReload: .excludedForReload
        }
    }
}

/// What a Narrative row presents: a special event's result page (keyed by type), the sealed canisters page, or a
/// passenger's "Ship's comm" line (UI-ENC-066, -078).
enum NarrativeKey: Equatable, Sendable {
    case specialEventResult([SpecialEventType])
    case sealedCanisters
    case passengerComm(crewID: Int, impatient: Bool)

    var eventKind: GameEventKind {
        switch self {
        case .specialEventResult: .specialEventCompleted
        case .sealedCanisters: .sealedCanisters
        case let .passengerComm(_, impatient): impatient ? .passengerImpatient : .passengerConcerned
        }
    }

    var surfaces: Set<EventSurface> {
        switch self {
        case .specialEventResult, .sealedCanisters: [.narrativeResult, .feed]
        case .passengerComm: [.comm, .feed]
        }
    }

    var sampleEvent: GameEvent {
        switch self {
        case let .specialEventResult(types): .specialEventCompleted(types.first ?? .moon)
        case .sealedCanisters: .sealedCanisters(.robots)
        case let .passengerComm(id, impatient):
            if impatient { .passengerImpatient(crewID: id) } else { .passengerConcerned(crewID: id) }
        }
    }
}

/// What replaces a removed alert (ALR §2 "Removed").
enum ALRReplacement: Equatable, Sendable {
    /// An element of the app (checked against `AXID.all`).
    case axid(String)
    case sheet(SheetRoute)
    case command(Command)
    case appConfirmation(AppConfirmationKind)
    /// The classic alert is never raised (ALR §3 "14 types are never raised").
    case neverRaised
    /// No macOS counterpart (the Windows registry, ALR-134).
    case noCounterpart
}

/// UI-ENC-004: how one classic alert is presented now.
enum ALRPresentation: Equatable, Sendable {
    case inlineReason(CommandError)
    case previewNote(PreviewNote)
    case confirmation(WarningID)
    /// ALR-146: the transfer toggles of the purchase sheet.
    case transferOption
    case decision(PendingDecisionKind)
    case appConfirmation(AppConfirmationKind)
    case event(GameEventKind, surfaces: Set<EventSurface>)
    case narrative(NarrativeKey)
    case highScoreOutcome(HighScoreOutcomeKind)
    case systemAlert(SystemAlertKind)
    case removed(replacement: ALRReplacement)

    /// The engine event the row's presentation shows, for event and narrative rows.
    var eventKind: GameEventKind? {
        switch self {
        case let .event(kind, _): kind
        case let .narrative(key): key.eventKind
        case .inlineReason, .previewNote, .confirmation, .transferOption, .decision, .appConfirmation, .highScoreOutcome,
             .systemAlert, .removed:
            nil
        }
    }

    var narrativeKey: NarrativeKey? {
        if case let .narrative(key) = self { return key }
        return nil
    }

    /// The surfaces the row lists (event and narrative rows).
    var surfaces: Set<EventSurface> {
        switch self {
        case let .event(_, surfaces): surfaces.union([.feed])
        case let .narrative(key): key.surfaces
        case .inlineReason, .previewNote, .confirmation, .transferOption, .decision, .appConfirmation, .highScoreOutcome,
             .systemAlert, .removed:
            []
        }
    }

    /// The classes this presentation may belong to.
    var allowedClasses: Set<ALRClass> {
        switch self {
        case .inlineReason, .previewNote: [.commandError]
        case .confirmation, .transferOption, .decision, .appConfirmation: [.confirmation]
        case .event: [.gameEvent, .critical]
        case .highScoreOutcome: [.gameEvent]
        case .narrative: [.narrative]
        case .systemAlert: [.systemAlert]
        case .removed: [.removed]
        }
    }
}

/// UI-ENC-004: one row of ALR §4.
struct ALRRow: Equatable, Sendable {
    var number: Int
    var alertType: String
    var alertClass: ALRClass
    var presentation: ALRPresentation
}

/// UI-ENC-004: the classic alert catalog (ALR §4), checked against `docs/specs/ALR.md` by the coverage test and listed
/// by the developer tester (UI-ENC-092).
enum ALRCatalog {
    private static func err(_ e: CommandError) -> ALRPresentation { .inlineReason(e) }
    private static func note(_ n: PreviewNote) -> ALRPresentation { .previewNote(n) }
    private static func conf(_ w: WarningID) -> ALRPresentation { .confirmation(w) }
    private static func dec(_ d: PendingDecisionKind) -> ALRPresentation { .decision(d) }
    private static func app(_ a: AppConfirmationKind) -> ALRPresentation { .appConfirmation(a) }
    private static func ev(_ k: GameEventKind, _ s: Set<EventSurface>) -> ALRPresentation { .event(k, surfaces: s) }
    private static func nar(_ k: NarrativeKey) -> ALRPresentation { .narrative(k) }
    private static func hs(_ o: HighScoreOutcomeKind) -> ALRPresentation { .highScoreOutcome(o) }
    private static func sys(_ a: SystemAlertKind) -> ALRPresentation { .systemAlert(a) }
    private static func rm(_ r: ALRReplacement) -> ALRPresentation { .removed(replacement: r) }
    private static func result(_ types: [SpecialEventType]) -> ALRPresentation { .narrative(.specialEventResult(types)) }
    private static func comm(_ id: Int, impatient: Bool) -> ALRPresentation {
        .narrative(.passengerComm(crewID: id, impatient: impatient))
    }

    /// The 188 rows of ALR §4 in `Enums.cs` order.
    static let rows: [ALRRow] = [
        ALRRow(number: 1, alertType: "Alert", alertClass: .removed, presentation: rm(.sheet(.cheatConsole))),
        ALRRow(number: 2, alertType: "AntidoteOnBoard", alertClass: .narrative, presentation: result([.japori])),
        ALRRow(number: 3, alertType: "AntidoteDestroyed", alertClass: .gameEvent, presentation: ev(.escapePodUsed, [.reportSheet])),
        ALRRow(number: 4, alertType: "AntidoteTaken", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 5, alertType: "AppStart", alertClass: .removed, presentation: rm(.axid(AXID.Welcome.root))),
        ALRRow(number: 6, alertType: "ArrivalBuyNewspaper", alertClass: .confirmation, presentation: conf(.buyNewspaper)),
        ALRRow(number: 7, alertType: "ArrivalIFFuel", alertClass: .gameEvent, presentation: ev(.autoFuelFailed, [.arrivalReport])),
        ALRRow(number: 8, alertType: "ArrivalIFFuelRepairs", alertClass: .gameEvent, presentation: ev(.autoFuelFailed, [.arrivalReport])),
        ALRRow(number: 9, alertType: "ArrivalIFNewspaper", alertClass: .commandError, presentation: err(.insufficientFunds)),
        ALRRow(number: 10, alertType: "ArrivalIFRepairs", alertClass: .gameEvent, presentation: ev(.autoRepairFailed, [.arrivalReport])),
        ALRRow(number: 11, alertType: "ArtifactLost", alertClass: .gameEvent, presentation: ev(.escapePodUsed, [.reportSheet])),
        ALRRow(number: 12, alertType: "ArtifactRelinquished", alertClass: .gameEvent, presentation: ev(.artifactRelinquished, [.combatLog, .feed])),
        ALRRow(number: 13, alertType: "CargoIF", alertClass: .commandError, presentation: err(.insufficientFunds)),
        ALRRow(number: 14, alertType: "CargoNoEmptyBays", alertClass: .commandError, presentation: err(.noEmptyBays)),
        ALRRow(number: 15, alertType: "CargoNoneAvailable", alertClass: .commandError, presentation: err(.cargoNoneAvailable)),
        ALRRow(number: 16, alertType: "CargoNoneToSell", alertClass: .commandError, presentation: err(.cargoNoneToSell)),
        ALRRow(number: 17, alertType: "CargoNotInterested", alertClass: .commandError, presentation: err(.marketNotInterested)),
        ALRRow(number: 18, alertType: "CargoNotSold", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 19, alertType: "ChartJump", alertClass: .confirmation, presentation: conf(.useSingularity)),
        ALRRow(number: 20, alertType: "ChartJumpCurrent", alertClass: .commandError, presentation: err(.singularityTargetIsCurrentSystem)),
        ALRRow(number: 21, alertType: "ChartJumpNoSystemSelected", alertClass: .commandError, presentation: note(.jumpNoTarget)),
        ALRRow(number: 22, alertType: "ChartTrackSystem", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 23, alertType: "ChartWormholeUnreachable", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 24, alertType: "Cheater", alertClass: .removed, presentation: rm(.sheet(.cheatConsole))),
        ALRRow(number: 25, alertType: "CrewFireMercenary", alertClass: .confirmation, presentation: conf(.fireMercenary)),
        ALRRow(number: 26, alertType: "CrewNoQuarters", alertClass: .commandError, presentation: err(.noFreeQuarters)),
        ALRRow(number: 27, alertType: "DebtNoBuy", alertClass: .commandError, presentation: err(.inDebt)),
        ALRRow(number: 28, alertType: "DebtNone", alertClass: .commandError, presentation: err(.noDebt)),
        ALRRow(number: 29, alertType: "DebtReminder", alertClass: .gameEvent, presentation: ev(.debtReminder, [.arrivalReport])),
        ALRRow(number: 30, alertType: "DebtTooLargeGrounded", alertClass: .commandError, presentation: err(.debtTooLargeToTravel)),
        ALRRow(number: 31, alertType: "DebtTooLargeLoan", alertClass: .commandError, presentation: err(.debtTooLargeForLoan)),
        ALRRow(number: 32, alertType: "DebtTooLargeTrade", alertClass: .commandError, presentation: err(.debtTooLargeToTrade)),
        ALRRow(number: 33, alertType: "DebtWarning", alertClass: .gameEvent, presentation: ev(.debtWarning, [.arrivalReport])),
        ALRRow(number: 34, alertType: "Egg", alertClass: .gameEvent, presentation: ev(.easterEgg, [.arrivalReport])),
        ALRRow(number: 35, alertType: "EncounterAliensSurrender", alertClass: .confirmation, presentation: conf(.surrenderArtifact)),
        ALRRow(number: 36, alertType: "EncounterArrested", alertClass: .critical, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 37, alertType: "EncounterAttackCaptain", alertClass: .confirmation, presentation: conf(.attackCaptain)),
        ALRRow(number: 38, alertType: "EncounterAttackNoDisruptors", alertClass: .commandError, presentation: err(.noDisruptors)),
        ALRRow(number: 39, alertType: "EncounterAttackNoLasers", alertClass: .commandError, presentation: err(.noLasers)),
        ALRRow(number: 40, alertType: "EncounterAttackNoWeapons", alertClass: .commandError, presentation: err(.noWeapons)),
        ALRRow(number: 41, alertType: "EncounterAttackPolice", alertClass: .confirmation, presentation: conf(.attackPolice)),
        ALRRow(number: 42, alertType: "EncounterAttackTrader", alertClass: .confirmation, presentation: conf(.attackTrader)),
        ALRRow(number: 43, alertType: "EncounterBothDestroyed", alertClass: .critical, presentation: ev(.bothDestroyed, [.combatLog, .gameOverCard])),
        ALRRow(number: 44, alertType: "EncounterDisabledOpponent", alertClass: .gameEvent, presentation: ev(.opponentDisabled, [.combatLog, .arrivalReport])),
        ALRRow(number: 45, alertType: "EncounterDrinkContents", alertClass: .confirmation, presentation: conf(.drinkTonic)),
        ALRRow(number: 46, alertType: "EncounterDumpAll", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 47, alertType: "EncounterDumpWarning", alertClass: .confirmation, presentation: conf(.litteringWarning)),
        ALRRow(number: 48, alertType: "EncounterEscaped", alertClass: .gameEvent, presentation: ev(.playerEscaped, [.combatLog, .arrivalReport])),
        ALRRow(number: 49, alertType: "EncounterEscapedHit", alertClass: .gameEvent, presentation: ev(.playerEscaped, [.combatLog, .arrivalReport])),
        ALRRow(number: 50, alertType: "EncounterEscapePodActivated", alertClass: .critical, presentation: ev(.escapePodUsed, [.reportSheet])),
        ALRRow(number: 51, alertType: "EncounterLooting", alertClass: .gameEvent, presentation: ev(.looted, [.combatLog, .arrivalReport])),
        ALRRow(number: 52, alertType: "EncounterMarieCeleste", alertClass: .confirmation, presentation: conf(.boardMarieCeleste)),
        ALRRow(number: 53, alertType: "EncounterMarieCelesteNoBribe", alertClass: .commandError, presentation: err(.bribeNotAccepted)),
        ALRRow(number: 54, alertType: "EncounterOpponentEscaped", alertClass: .gameEvent, presentation: ev(.opponentEscaped, [.combatLog, .arrivalReport])),
        ALRRow(number: 55, alertType: "EncounterPiratesBounty", alertClass: .gameEvent, presentation: ev(.bountyPaid, [.combatLog, .arrivalReport])),
        ALRRow(number: 56, alertType: "EncounterPiratesExamineReactor", alertClass: .gameEvent, presentation: ev(.looted, [.combatLog, .arrivalReport])),
        ALRRow(number: 57, alertType: "EncounterPiratesFindNoCargo", alertClass: .gameEvent, presentation: ev(.blackmailed, [.combatLog, .arrivalReport])),
        ALRRow(number: 58, alertType: "EncounterPiratesSurrenderPrincess", alertClass: .commandError, presentation: err(.surrenderPrincess)),
        ALRRow(number: 59, alertType: "EncounterPiratesTakeSculpture", alertClass: .gameEvent, presentation: ev(.sculptureTaken, [.combatLog, .arrivalReport])),
        ALRRow(number: 60, alertType: "EncounterPoliceBribe", alertClass: .confirmation, presentation: conf(.bribe)),
        ALRRow(number: 61, alertType: "EncounterPoliceBribeCant", alertClass: .commandError, presentation: err(.bribeNotPossible)),
        ALRRow(number: 62, alertType: "EncounterPoliceBribeLowCash", alertClass: .commandError, presentation: err(.insufficientFunds)),
        ALRRow(number: 63, alertType: "EncounterPoliceFine", alertClass: .gameEvent, presentation: ev(.fined, [.combatLog, .arrivalReport])),
        ALRRow(number: 64, alertType: "EncounterPoliceNothingFound", alertClass: .gameEvent, presentation: ev(.inspectionClean, [.combatLog, .arrivalReport])),
        ALRRow(number: 65, alertType: "EncounterPoliceNothingIllegal", alertClass: .confirmation, presentation: conf(.submitWithNothingIllegal)),
        ALRRow(number: 66, alertType: "EncounterPoliceSubmit", alertClass: .confirmation, presentation: conf(.submitInspection)),
        ALRRow(number: 67, alertType: "EncounterPoliceSurrender", alertClass: .confirmation, presentation: conf(.surrenderToPolice)),
        ALRRow(number: 68, alertType: "EncounterPostMarie", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 69, alertType: "EncounterPostMarieFlee", alertClass: .confirmation, presentation: conf(.fleeMariePolice)),
        ALRRow(number: 70, alertType: "EncounterScoop", alertClass: .confirmation, presentation: dec(.scoop)),
        ALRRow(number: 71, alertType: "EncounterScoopNoRoom", alertClass: .confirmation, presentation: dec(.scoop)),
        ALRRow(number: 72, alertType: "EncounterScoopNoScoop", alertClass: .gameEvent, presentation: ev(.scoopNoRoom, [.feed])),
        ALRRow(number: 73, alertType: "EncounterSurrenderRefused", alertClass: .commandError, presentation: err(.surrenderRefused)),
        ALRRow(number: 74, alertType: "EncounterTonicConsumedGood", alertClass: .gameEvent, presentation: ev(.tonicConsumed, [.combatLog, .feed])),
        ALRRow(number: 75, alertType: "EncounterTonicConsumedStrange", alertClass: .gameEvent, presentation: ev(.tonicConsumed, [.combatLog, .feed])),
        ALRRow(number: 76, alertType: "EncounterTradeCompleted", alertClass: .gameEvent, presentation: ev(.orbitTradeCompleted, [.combatLog, .arrivalReport])),
        ALRRow(number: 77, alertType: "EncounterYouLose", alertClass: .critical, presentation: ev(.playerDestroyed, [.combatLog, .gameOverCard])),
        ALRRow(number: 78, alertType: "EncounterYouWin", alertClass: .gameEvent, presentation: ev(.opponentDestroyed, [.combatLog, .arrivalReport])),
        ALRRow(number: 79, alertType: "EquipmentAlreadyOwn", alertClass: .commandError, presentation: err(.equipmentAlreadyOwned)),
        ALRRow(number: 80, alertType: "EquipmentBuy", alertClass: .confirmation, presentation: conf(.buyEquipment)),
        ALRRow(number: 81, alertType: "EquipmentEscapePod", alertClass: .confirmation, presentation: conf(.buyEscapePod)),
        ALRRow(number: 82, alertType: "EquipmentExtraBaysInUse", alertClass: .commandError, presentation: err(.extraBaysInUse)),
        ALRRow(number: 83, alertType: "EquipmentFuelCompactor", alertClass: .narrative, presentation: result([.gemulonFuel])),
        ALRRow(number: 84, alertType: "EquipmentHiddenCompartments", alertClass: .narrative, presentation: result([.sculptureHiddenBays])),
        ALRRow(number: 85, alertType: "EquipmentIF", alertClass: .commandError, presentation: err(.insufficientFunds)),
        ALRRow(number: 86, alertType: "EquipmentLightningShield", alertClass: .narrative, presentation: result([.dragonflyShield])),
        ALRRow(number: 87, alertType: "EquipmentMorgansLaser", alertClass: .narrative, presentation: result([.reactorLaser])),
        ALRRow(number: 88, alertType: "EquipmentNotEnoughSlots", alertClass: .commandError, presentation: err(.noFreeSlot)),
        ALRRow(number: 89, alertType: "EquipmentQuantumDisruptor", alertClass: .narrative, presentation: result([.princessQuantum])),
        ALRRow(number: 90, alertType: "EquipmentSell", alertClass: .confirmation, presentation: conf(.sellEquipment)),
        ALRRow(number: 91, alertType: "FileErrorOpen", alertClass: .systemAlert, presentation: sys(.openFailed)),
        ALRRow(number: 92, alertType: "FileErrorSave", alertClass: .systemAlert, presentation: sys(.saveFailed)),
        ALRRow(number: 93, alertType: "FleaBuilt", alertClass: .gameEvent, presentation: ev(.escapePodUsed, [.reportSheet])),
        ALRRow(number: 94, alertType: "GameAbandonConfirm", alertClass: .confirmation, presentation: app(.discardUnsavedGame)),
        ALRRow(number: 95, alertType: "GameClearHighScores", alertClass: .removed, presentation: rm(.appConfirmation(.clearHighScores))),
        ALRRow(number: 96, alertType: "GameEndBoughtMoon", alertClass: .critical, presentation: ev(.gameEnded, [.gameOverCard])),
        ALRRow(number: 97, alertType: "GameEndBoughtMoonGirl", alertClass: .critical, presentation: ev(.gameEnded, [.gameOverCard])),
        ALRRow(number: 98, alertType: "GameEndHighScoreAchieved", alertClass: .gameEvent, presentation: hs(.entered)),
        ALRRow(number: 99, alertType: "GameEndHighScoreCheat", alertClass: .gameEvent, presentation: hs(.excludedForCheats)),
        ALRRow(number: 100, alertType: "GameEndHighScoreMissed", alertClass: .gameEvent, presentation: hs(.missed)),
        ALRRow(number: 101, alertType: "GameEndKilled", alertClass: .critical, presentation: ev(.gameEnded, [.gameOverCard])),
        ALRRow(number: 102, alertType: "GameEndRetired", alertClass: .critical, presentation: ev(.gameEnded, [.gameOverCard])),
        ALRRow(number: 103, alertType: "GameEndScore", alertClass: .gameEvent, presentation: ev(.gameEnded, [.gameOverCard])),
        ALRRow(number: 104, alertType: "GameRetire", alertClass: .confirmation, presentation: conf(.retire)),
        ALRRow(number: 105, alertType: "InsuranceNoEscapePod", alertClass: .commandError, presentation: err(.insuranceRequiresEscapePod)),
        ALRRow(number: 106, alertType: "InsurancePayoff", alertClass: .critical, presentation: ev(.escapePodUsed, [.reportSheet])),
        ALRRow(number: 107, alertType: "InsuranceStop", alertClass: .confirmation, presentation: conf(.stopInsurance)),
        ALRRow(number: 108, alertType: "JailConvicted", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 109, alertType: "JailFleaReceived", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 110, alertType: "JailHiddenCargoBaysRemoved", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 111, alertType: "JailIllegalGoodsImpounded", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 112, alertType: "JailInsuranceLost", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 113, alertType: "JailMercenariesLeave", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 114, alertType: "JailShipSold", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 115, alertType: "JarekTakenHome", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 116, alertType: "LeavingIFInsurance", alertClass: .commandError, presentation: err(.cannotPayInsurance)),
        ALRRow(number: 117, alertType: "LeavingIFMercenaries", alertClass: .commandError, presentation: err(.cannotPayMercenaries)),
        ALRRow(number: 118, alertType: "LeavingIFWormholeTax", alertClass: .commandError, presentation: err(.cannotPayWormholeTax)),
        ALRRow(number: 119, alertType: "MeetCaptainAhab", alertClass: .confirmation, presentation: conf(.meetCaptain)),
        ALRRow(number: 120, alertType: "MeetCaptainConrad", alertClass: .confirmation, presentation: conf(.meetCaptain)),
        ALRRow(number: 121, alertType: "MeetCaptainHuie", alertClass: .confirmation, presentation: conf(.meetCaptain)),
        ALRRow(number: 122, alertType: "NewGameConfirm", alertClass: .removed, presentation: rm(.appConfirmation(.discardUnsavedGame))),
        ALRRow(number: 123, alertType: "NewGameMoreSkillPoints", alertClass: .removed, presentation: rm(.axid(AXID.NewGame.start))),
        ALRRow(number: 124, alertType: "OptionsNoGame", alertClass: .removed, presentation: rm(.axid(AXID.Welcome.root))),
        ALRRow(number: 125, alertType: "PreciousHidden", alertClass: .gameEvent, presentation: ev(.preciousHidden, [.combatLog, .arrivalReport])),
        ALRRow(number: 126, alertType: "PrincessTakenHome", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 127, alertType: "ReactorConfiscated", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 128, alertType: "ReactorDestroyed", alertClass: .gameEvent, presentation: ev(.escapePodUsed, [.reportSheet])),
        ALRRow(number: 129, alertType: "ReactorOnBoard", alertClass: .narrative, presentation: result([.reactor])),
        ALRRow(number: 130, alertType: "ReactorMeltdown", alertClass: .critical, presentation: ev(.reactorMeltdown, [.reportSheet])),
        ALRRow(number: 131, alertType: "ReactorWarningFuel", alertClass: .gameEvent, presentation: ev(.reactorWarning, [.arrivalReport])),
        ALRRow(number: 132, alertType: "ReactorWarningFuelGone", alertClass: .gameEvent, presentation: ev(.reactorWarning, [.arrivalReport])),
        ALRRow(number: 133, alertType: "ReactorWarningTemp", alertClass: .critical, presentation: ev(.reactorWarning, [.reportSheet])),
        ALRRow(number: 134, alertType: "RegistryError", alertClass: .removed, presentation: rm(.noCounterpart)),
        ALRRow(number: 135, alertType: "SculptureConfiscated", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 136, alertType: "SculptureSaved", alertClass: .gameEvent, presentation: ev(.escapePodUsed, [.reportSheet])),
        ALRRow(number: 137, alertType: "ShipBuyConfirm", alertClass: .confirmation, presentation: conf(.buyShip)),
        ALRRow(number: 138, alertType: "ShipBuyCrewQuarters", alertClass: .commandError, presentation: err(.notEnoughQuarters)),
        ALRRow(number: 139, alertType: "ShipBuyIF", alertClass: .commandError, presentation: err(.insufficientFunds)),
        ALRRow(number: 140, alertType: "ShipBuyIFTransfer", alertClass: .commandError, presentation: note(.cannotAffordAllTransfers)),
        ALRRow(number: 141, alertType: "ShipBuyNoSlots", alertClass: .confirmation, presentation: conf(.buyShip)),
        ALRRow(number: 142, alertType: "ShipBuyNotAvailable", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 143, alertType: "ShipBuyNoTransfer", alertClass: .confirmation, presentation: conf(.buyShip)),
        ALRRow(number: 144, alertType: "ShipBuyPassengerQuarters", alertClass: .commandError, presentation: err(.passengersNeedQuarters)),
        ALRRow(number: 145, alertType: "ShipBuyReactor", alertClass: .commandError, presentation: err(.reactorOnBoard)),
        ALRRow(number: 146, alertType: "ShipBuyTransfer", alertClass: .confirmation, presentation: .transferOption),
        ALRRow(number: 147, alertType: "ShipDesignIF", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 148, alertType: "ShipDesignThanks", alertClass: .gameEvent, presentation: ev(.customShipBuilt, [.feed])),
        ALRRow(number: 149, alertType: "ShipHullUpgraded", alertClass: .narrative, presentation: result([.scarabUpgradeHull])),
        ALRRow(number: 150, alertType: "SpecialCleanRecord", alertClass: .narrative, presentation: result([.eraseRecord])),
        ALRRow(number: 151, alertType: "SpecialExperimentPerformed", alertClass: .gameEvent, presentation: ev(.experimentPerformed, [.feed])),
        ALRRow(number: 152, alertType: "SpecialIF", alertClass: .commandError, presentation: err(.insufficientFunds)),
        ALRRow(number: 153, alertType: "SpecialMoonBought", alertClass: .narrative, presentation: result([.moon])),
        ALRRow(number: 154, alertType: "SpecialNoQuarters", alertClass: .commandError, presentation: err(.noFreeQuarters)),
        ALRRow(number: 155, alertType: "SpecialNotEnoughBays", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 156, alertType: "SpecialPassengerConcernedJarek", alertClass: .narrative, presentation: comm(CrewID.jarek, impatient: false)),
        ALRRow(number: 157, alertType: "SpecialPassengerConcernedPrincess", alertClass: .narrative, presentation: comm(CrewID.princess, impatient: false)),
        ALRRow(number: 158, alertType: "SpecialPassengerConcernedWild", alertClass: .narrative, presentation: comm(CrewID.wild, impatient: false)),
        ALRRow(number: 159, alertType: "SpecialPassengerImpatientJarek", alertClass: .narrative, presentation: comm(CrewID.jarek, impatient: true)),
        ALRRow(number: 160, alertType: "SpecialPassengerImpatientPrincess", alertClass: .narrative, presentation: comm(CrewID.princess, impatient: true)),
        ALRRow(number: 161, alertType: "SpecialPassengerImpatientWild", alertClass: .narrative, presentation: comm(CrewID.wild, impatient: true)),
        ALRRow(number: 162, alertType: "SpecialPassengerOnBoard", alertClass: .narrative, presentation: result([.jarek, .princessQonos, .wild])),
        ALRRow(number: 163, alertType: "SpecialSealedCanisters", alertClass: .narrative, presentation: nar(.sealedCanisters)),
        ALRRow(number: 164, alertType: "SpecialSkillIncrease", alertClass: .narrative, presentation: result([.skill])),
        ALRRow(number: 165, alertType: "SpecialTimespaceFabricRip", alertClass: .gameEvent, presentation: ev(.fabricRip, [.arrivalReport, .transitBanner])),
        ALRRow(number: 166, alertType: "SpecialTrainingCompleted", alertClass: .gameEvent, presentation: ev(.captainTraining, [.combatLog, .feed])),
        ALRRow(number: 167, alertType: "TravelArrival", alertClass: .removed, presentation: rm(.neverRaised)),
        ALRRow(number: 168, alertType: "TravelUneventfulTrip", alertClass: .gameEvent, presentation: ev(.uneventfulTrip, [.arrivalReport])),
        ALRRow(number: 169, alertType: "TribblesAllDied", alertClass: .gameEvent, presentation: ev(.tribblesDied, [.arrivalReport])),
        ALRRow(number: 170, alertType: "TribblesAteFood", alertClass: .gameEvent, presentation: ev(.tribblesAteFood, [.arrivalReport])),
        ALRRow(number: 171, alertType: "TribblesGone", alertClass: .narrative, presentation: result([.tribbleBuyer])),
        ALRRow(number: 172, alertType: "TribblesHalfDied", alertClass: .gameEvent, presentation: ev(.tribblesDied, [.arrivalReport])),
        ALRRow(number: 173, alertType: "TribblesKilled", alertClass: .gameEvent, presentation: ev(.escapePodUsed, [.reportSheet])),
        ALRRow(number: 174, alertType: "TribblesMostDied", alertClass: .gameEvent, presentation: ev(.tribblesDied, [.arrivalReport])),
        ALRRow(number: 175, alertType: "TribblesOwn", alertClass: .narrative, presentation: result([.tribble])),
        ALRRow(number: 176, alertType: "TribblesRemoved", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 177, alertType: "TribblesInspector", alertClass: .gameEvent, presentation: ev(.tribbleInspectorWarning, [.arrivalReport])),
        ALRRow(number: 178, alertType: "TribblesSqueek", alertClass: .removed, presentation: rm(.axid(AXID.Encounter.view))),
        ALRRow(number: 179, alertType: "TribblesTradeIn", alertClass: .commandError, presentation: note(.tribblesTradeIn)),
        ALRRow(number: 180, alertType: "WildArrested", alertClass: .gameEvent, presentation: ev(.arrested, [.reportSheet])),
        ALRRow(number: 181, alertType: "WildChatsPirates", alertClass: .gameEvent, presentation: ev(.looted, [.combatLog, .arrivalReport])),
        ALRRow(number: 182, alertType: "WildGoesPirates", alertClass: .gameEvent, presentation: ev(.wildJoinedPirates, [.combatLog, .arrivalReport])),
        ALRRow(number: 183, alertType: "WildLeavesShip", alertClass: .gameEvent, presentation: ev(.wildLeftShip, [.feed])),
        ALRRow(number: 184, alertType: "WildSculpture", alertClass: .narrative, presentation: result([.wild])),
        ALRRow(number: 185, alertType: "WildWontBoardLaser", alertClass: .commandError, presentation: err(.wildRequiresLaser)),
        ALRRow(number: 186, alertType: "WildWontBoardReactor", alertClass: .commandError, presentation: err(.wildRefusesReactor)),
        ALRRow(number: 187, alertType: "WildWontStayAboardLaser", alertClass: .confirmation, presentation: conf(.wildLeavesWithoutLaser)),
        ALRRow(number: 188, alertType: "WildWontStayAboardReactor", alertClass: .confirmation, presentation: conf(.wildLeavesForReactor)),
    ]

    /// The fixture event for an event or narrative row (UI-ENC-004; the developer tester's samples, UI-ENC-092).
    static func sampleEvent(for row: ALRRow) -> GameEvent? {
        switch row.number {
        case 8: return .autoFuelFailed
        case 48: return .playerEscaped(wasHit: false)
        case 49: return .playerEscaped(wasHit: true)
        case 74: return .tonicConsumed(good: true)
        case 75: return .tonicConsumed(good: false)
        case 93: return .escapePodUsed(insurancePayout: 0)
        case 96: return .gameEnded(.boughtMoon, score: 1000)
        case 97: return .gameEnded(.boughtMoonGirl, score: 1000)
        case 101: return .gameEnded(.killed, score: 10)
        case 102: return .gameEnded(.retired, score: 100)
        case 106: return .escapePodUsed(insurancePayout: 5000)
        case 114: return .arrested(term: 30, fine: 50_000, shipSold: true)
        case 131: return .reactorWarning(status: 2)
        case 132: return .reactorWarning(status: 16)
        case 133: return .reactorWarning(status: ReactorStatus.temperatureWarning)
        case 169: return .tribblesDied(.allFromReactor)
        case 172: return .tribblesDied(.halfFromReactor)
        case 174: return .tribblesDied(.narcotics(converted: 10))
        default:
            guard let kind = row.presentation.eventKind else { return nil }
            return row.presentation.narrativeKey?.sampleEvent ?? kind.fixture
        }
    }
}
