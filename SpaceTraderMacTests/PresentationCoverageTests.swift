// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// One row of the ALR §4 table as written in docs/specs/ALR.md.
private struct ALRTableRow {
    var number: Int
    var alertType: String
    var alertClass: String
    var presentation: String
}

/// Reads the ALR §4 mapping table (the test reads the spec relative to this file, UI-ENC-004 item 1).
private func alrTable() throws -> [ALRTableRow] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/specs/ALR.md")
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n").compactMap { line -> ALRTableRow? in
        let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 9, let n = Int(cells[1]) else { return nil }
        return ALRTableRow(number: n, alertType: cells[2].replacingOccurrences(of: "`", with: ""), alertClass: cells[5],
                           presentation: cells[7])
    }
}

@MainActor
@Suite("Presentation coverage (UI-ENC-004)")
struct PresentationCoverageTests {
    private let state = GameState(config: NewGameConfig(commanderName: "Coverage", seed: 3))

    @Test("UI-ENC-004 item 1: 188 ALR rows numbered 1…188 with unique names; number, name and class equal ALR §4")
    func catalogMatchesSpec() throws {
        let rows = ALRCatalog.rows
        #expect(rows.count == 188)
        #expect(rows.map(\.number) == Array(1...188))
        #expect(Set(rows.map(\.alertType)).count == 188)
        let table = try alrTable()
        #expect(table.count == 188)
        for (row, spec) in zip(rows, table) {
            #expect(row.number == spec.number && row.alertType == spec.alertType, "row \(row.number)")
            #expect(row.alertClass.tableName == spec.alertClass, "class of row \(row.number) \(row.alertType)")
            #expect(row.presentation.allowedClasses.contains(row.alertClass), "presentation of row \(row.number)")
        }
    }

    @Test("UI-ENC-004 item 2: every PendingDecision case routes to a presentation the app can show")
    func decisionsRoute() throws {
        for d in try RouteFixtures.decisions() {
            let p = PresentationRouter.route(d, state: state, command: .warp)
            switch (PendingDecisionKind(d), p) {
            case (.confirm, .confirmation), (.tradeInOrbit, .sheet(.tradeInOrbit)), (.plunder, .sheet(.plunder)),
                 (.scoop, .scoop), (.newspaper, .sheet(.newspaper)):
                break
            default:
                Issue.record("\(d) routed to \(p)")
            }
        }
        // Every decision row of the catalog names a routable decision.
        for row in ALRCatalog.rows {
            if case let .decision(kind) = row.presentation { #expect(PendingDecisionKind.allCases.contains(kind)) }
        }
    }

    @Test("UI-ENC-004 item 3: every WarningID has confirmation text, a route, and the ALR destructive marking")
    func warnings() throws {
        let table = try alrTable()
        var expected: [WarningID: Bool] = [:]
        for row in ALRCatalog.rows {
            guard case let .confirmation(w) = row.presentation else { continue }
            expected[w] = table[row.number - 1].presentation.contains("(destructive)")
        }
        // ALR-065 maps both nothing-illegal prompts (attack/bribe and flee).
        expected[.fleeInspection] = expected[.submitWithNothingIllegal]
        let special = RouteFixtures.specialEventState()
        for w in WarningID.allCases {
            let c = ConfirmationText.content(for: Confirmation(w, amounts: [100, 50]), state: state)
            #expect(!c.title.isEmpty && !c.message.isEmpty && !c.confirmLabel.isEmpty, "\(w)")
            if let destructive = expected[w] { #expect(c.isDestructive == destructive, "\(w)") }
            let p = PresentationRouter.route(.confirm(Confirmation(w)), state: special, command: .warp)
            switch p {
            case .confirmation, .sheet(.retire), .sheet(.narrative), .sheet(.shipPurchase): break
            default: Issue.record("\(w) routed to \(p)")
            }
        }
        // Warnings without an ALR row: Palm's jettison-all (ECO-058) and the special-event consent (QST) are not
        // AlertTypes; everything else is in the table.
        #expect(Set(WarningID.allCases).subtracting(expected.keys) == [.jettisonAll, .acceptSpecialEvent])
    }

    @Test("UI-ENC-004 item 4: every CommandError has a non-empty ReasonText")
    func reasons() {
        for e in CommandError.allCases {
            #expect(!String(localized: ReasonText.text(for: e)).isEmpty, "\(e)")
        }
    }

    @Test("UI-ENC-004 item 5: every GameEvent case has EventText and surfaces covering its ALR rows")
    func events() throws {
        for kind in GameEventKind.allCases {
            let e = kind.fixture
            #expect(GameEventKind(e) == kind)
            #expect(!String(localized: EventText.text(for: e, state: state)).isEmpty, "\(kind)")
            #expect(EventSurfaces.surfaces(for: e).contains(.feed), "\(kind)")
        }
        for row in ALRCatalog.rows {
            guard let kind = row.presentation.eventKind else { continue }
            let sample = try #require(ALRCatalog.sampleEvent(for: row))
            #expect(GameEventKind(sample) == kind, "sample of row \(row.number)")
            let surfaces = EventSurfaces.surfaces(for: sample)
            #expect(surfaces.isSuperset(of: row.presentation.surfaces), "row \(row.number) \(row.alertType): \(surfaces)")
            if row.alertClass == .critical {
                #expect(surfaces.contains(.reportSheet) || surfaces.contains(.gameOverCard), "critical row \(row.number)")
            }
        }
    }

    @Test("UI-ENC-004 item 6 UI-ENC-084: narrative rows, high-score outcomes, system alerts and app confirmations have text")
    func otherTexts() throws {
        for row in ALRCatalog.rows {
            guard let key = row.presentation.narrativeKey else { continue }
            #expect(!String(localized: EventText.text(for: key.sampleEvent, state: state)).isEmpty, "row \(row.number)")
            if case let .specialEventResult(types) = key {
                for t in types { #expect(!String(localized: SpecialEventText.title(t)).isEmpty) }
            }
        }
        // UI-ENC-084: every HighScoreOutcome and RecordedScore case has outcome text.
        let entry = state.highScoreEntry(for: .retired)
        for kind in HighScoreOutcomeKind.allCases {
            #expect(!(HighScoreOutcomeText.text(for: .outcome(kind.sample), entry: entry) ?? "").isEmpty, "\(kind)")
            #expect(HighScoreOutcomeKind(kind.sample) == kind)
        }
        for recorded in [RecordedScore.alreadyRecorded, .failed] {
            #expect(!(HighScoreOutcomeText.text(for: recorded, entry: entry) ?? "").isEmpty, "\(recorded)")
        }
        for kind in SystemAlertKind.allCases {
            #expect(!SystemAlertText.title(kind.sample).isEmpty && SystemAlertKind(kind.sample) == kind)
        }
        let session = try TestSessions.make()
        for kind in AppConfirmationKind.allCases {
            let c = AppConfirmationText.content(for: kind.sample, session: session)
            #expect(!c.title.isEmpty && !c.message.isEmpty && !c.confirmLabel.isEmpty && AppConfirmationKind(kind.sample) == kind)
        }
    }

    @Test("UI-ENC-004 item 5 UI-ENC-064 every GameEvent and feed note has a feed classification; critical rows are critical")
    func feedClassification() throws {
        for kind in GameEventKind.allCases {
            let style = FeedStyle.classify(.event(kind.fixture))
            #expect(FeedCategory.allCases.contains(style.category) && !style.symbol.isEmpty, "\(kind)")
            #expect(!FeedText.text(for: .event(kind.fixture), state: state).isEmpty, "\(kind)")
        }
        for note in [FeedNote.gameSaved, .recoveredFromBackup] {
            #expect(FeedSeverity.allCases.contains(FeedStyle.classify(.note(note)).severity))
        }
        // The critical rows' events are critical; no other event kind is (reactorWarning only at the temperature status).
        var criticalKinds: Set<GameEventKind> = []
        for row in ALRCatalog.rows where row.alertClass == .critical {
            let sample = try #require(ALRCatalog.sampleEvent(for: row))
            #expect(FeedStyle.classify(sample).severity == .critical, "row \(row.number)")
            criticalKinds.insert(GameEventKind(sample))
        }
        for kind in GameEventKind.allCases where FeedStyle.classify(kind.fixture).severity == .critical {
            #expect(criticalKinds.contains(kind), "\(kind)")
        }
        for row in ALRCatalog.rows where row.alertClass != .critical && row.presentation.eventKind == .reactorWarning {
            #expect(FeedStyle.classify(try #require(ALRCatalog.sampleEvent(for: row))).severity != .critical, "row \(row.number)")
        }
    }

    @Test("UI-ENC-004 item 6 UI-ENC-078 every narrative row has a NarrativeText result page or a Ship's comm line")
    func narrativeRows() {
        for row in ALRCatalog.rows {
            switch row.presentation.narrativeKey {
            case let .specialEventResult(types)?:
                for t in types {
                    let page = NarrativeText.result(for: [.specialEventCompleted(t)], before: state, after: state)
                    #expect(page.map { !$0.title.isEmpty && !$0.message.isEmpty } == true, "row \(row.number) \(t)")
                }
            case .sealedCanisters?:
                #expect(NarrativeText.result(for: [.sealedCanisters(.robots)], before: state, after: state) != nil)
            case let .passengerComm(id, impatient)?:
                #expect(PassengerComm.line(crewID: id, impatient: impatient, state: state).hasPrefix("Ship's comm — "), "row \(row.number)")
            case nil:
                break
            }
        }
    }

    @Test("""
        UI-ENC-004 item 7 ALR-001 ALR-005 ALR-018 ALR-022 ALR-023 ALR-024 ALR-046 ALR-068 ALR-095 ALR-109 ALR-122 \
        ALR-123 ALR-124 ALR-134 ALR-142 ALR-147 ALR-155 ALR-167 ALR-178 removed rows name an existing replacement
        """)
    func removedRows() throws {
        let table = try alrTable()
        let removed = ALRCatalog.rows.filter { $0.alertClass == .removed }
        #expect(removed.count == 19)
        for row in removed {
            guard case let .removed(replacement) = row.presentation else {
                Issue.record("row \(row.number) is removed but presents something")
                continue
            }
            switch replacement {
            case let .axid(id): #expect(AXID.all.contains(id), "row \(row.number): \(id)")
            case let .sheet(route): #expect(!Presentation.sheet(route).id.isEmpty)
            case let .command(c): #expect(c != .retire)
            case let .appConfirmation(kind): #expect(AppConfirmationKind.allCases.contains(kind))
            case .neverRaised:
                let raisedAt = try alrRaisedAt(row.number)
                #expect(raisedAt.contains("never raised"), "row \(row.number) claims never raised: \(raisedAt)")
            case .noCounterpart:
                #expect(table[row.number - 1].alertType == "RegistryError")
            }
        }
        // No engine value is presented by a removed row: the removed rows carry only replacements.
        #expect(removed.allSatisfy { $0.presentation.eventKind == nil })
    }

    /// The "Raised at" column of an ALR §4 row.
    private func alrRaisedAt(_ number: Int) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/specs/ALR.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let line = text.split(separator: "\n").first { $0.hasPrefix("| \(number) |") } ?? ""
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
        return cells.count > 4 ? String(cells[4]) : ""
    }

    @Test("UI-ENC-004 UI-ENC-097 the encounter-area identifiers are unique, match the scheme and are in AXID.all")
    func identifiers() throws {
        let area = AXID.encounterAreaAll
        #expect(Set(area).count == area.count)
        let regex = try Regex(AXID.pattern)
        for id in area {
            #expect(id.wholeMatch(of: regex) != nil, "\(id)")
            #expect(AXID.all.contains(id))
        }
        #expect(Set(AXID.all).count == AXID.all.count)
        // The kept M7 interim strings are unchanged (UI-ENC §17).
        #expect(AXID.Encounter.action(.attack) == "encounter.action.attack" && AXID.Encounter.interimPanel == "encounter.panel")
        #expect(AXID.Decision.tradeQuantity == "decision.trade.quantity" && AXID.Decision.plunderTake(.furs) == "decision.plunder.take.furs")
        #expect(AXID.Decision.newspaperClose == "decision.newspaper.close")
    }
}
