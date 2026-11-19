// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// The arrival report (UI-ENC-051…063), the newspaper auto-show (NEWS-012) and the narrative sheets (UI-ENC-073…077).
extension GameSession {
    /// Settings › Arrival report style (UI-SHELL-100).
    var arrivalReportStyle: ArrivalReportStyle { AppSettings(defaults: defaults).arrivalReportStyle }

    /// The step consumer after the combat log (UI-ENC-005): folds the trip, decides the arrival form and raises the
    /// narrative result page.
    func consumeArrival(_ step: StepRecord) {
        if step.contains({ if case .departed = $0 { true } else { false } }) {
            // UI-ENC-055: the card stays until dismissed or the next departure.
            arrivalCard = nil
            pendingArrival = nil
        }
        if let trip = tripAccumulator.fold(step, log: CombatLog.lines(for: step).map(\.display)) {
            pendingArrival = ArrivalPresentation.decide(trip: trip, style: arrivalReportStyle)
            if case .arrived = trip.end, Self.newsAutoShows(trip.after) { pendingNewsAutoShow = true }
        }
        // UI-ENC-077: the result page of an accepted special event (after any follow-up consent).
        if step.command == .specialEvent,
           let result = NarrativeText.result(for: step.events, before: step.before, after: step.after) {
            presentAfterPlayback(.sheet(.narrative(.result(result))))
        }
    }

    /// UI-ENC-061: shows the finished trip's form (the card, or a report sheet), once no playback runs.
    func showPendingArrival() {
        guard transitPlayback == nil, let arrival = pendingArrival else { return }
        pendingArrival = nil
        // UI-NAV-004: a trip always ends on the Bridge.
        if case .gameOver = arrival {} else { selectedSection = .bridge }
        switch arrival {
        case let .card(report):
            arrivalCard = report
        case let .sheet(sheet):
            // UI-ENC-057: Continue dismisses it; the card is not shown again for that trip.
            arrivalCard = nil
            present(.sheet(.report(sheet)))
        case .gameOver:
            arrivalCard = nil
        }
    }

    /// UI-ENC-055: Dismiss on the card.
    func dismissArrivalCard() {
        arrivalCard = nil
    }

    /// NEWS-012 / NEWS-013: auto-show is on and the ruleset offers it.
    static func newsAutoShows(_ state: GameState) -> Bool {
        state.options.newsAutoShow && state.ruleset.flags.travel.newsAutoShowAvailable && state.phase == .docked
    }

    /// UI-ENC-062: sends `.readNewspaper` after the arrival form was shown. NEWS-004…008 apply unchanged: a rejection
    /// is the status reason, the `.buyNewspaper` confirmation is the offer, and the paper opens the newspaper sheet.
    func runNewsAutoShowIfPending() {
        guard pendingNewsAutoShow, transitPlayback == nil, pendingArrival == nil else { return }
        pendingNewsAutoShow = false
        guard let state, Self.newsAutoShows(state) else { return }
        send(.readNewspaper)
    }

    /// UI-ENC-062: a new game also triggers the auto-show.
    func autoShowNewspaperForNewGame() {
        guard let state, Self.newsAutoShows(state) else { return }
        send(.readNewspaper)
    }

    func resetArrivalState() {
        tripAccumulator = TripAccumulator()
        arrivalCard = nil
        pendingArrival = nil
        pendingNewsAutoShow = false
    }

    // MARK: Newspaper and narrative

    /// UI-ENC-072: Read on the Bridge card, the arrival teaser or Game › Newspaper.
    func readNewspaper() {
        send(.readNewspaper)
    }

    /// UI-ENC-073: the Bridge card opens the offer page of the current special event.
    func openSpecialEvent() {
        guard let type = state?.specialEventAvailable else { return }
        present(.sheet(.narrative(.offer(type))))
    }

    /// UI-ENC-076: Accept (or Continue for a message-only event) closes the sheet first, then sends `.specialEvent`.
    /// The sheet is the `acceptSpecialEvent` consent, so no second dialog appears.
    func acceptSpecialEvent(messageOnly: Bool) {
        dismissPresentation()
        send(.specialEvent, acknowledging: messageOnly ? [] : [.acceptSpecialEvent])
    }
}
