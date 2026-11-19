// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-SB-001: the status bar: what must always be visible and nothing else. Eight fixed slots, in this order, on every
/// page and during transit and encounters: location, cash, debt, bays, fuel, hull, shields and one message.
struct StatusBarView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    @State private var showFeed = false
    @State private var visibleRejection: CommandError?
    /// UI-BRG-042: the feed length when the arrival summary appeared; a newer event replaces the summary.
    @State private var arrivalFeedMark: Int?

    var body: some View {
        if let state = session.state {
            let model = StatusBarModel.make(state: state, feed: session.feed)
            HStack(spacing: PMSpace.m * scale) {
                location(model)
                divider
                PMStat(label: "Cash", value: StatusBarText.credits(model.cash), large: true, identifier: AXID.Status.cash,
                       help: "Credits on hand. Borrow or repay at the Bank")
                PMStat(label: "Debt", value: StatusBarText.credits(model.debt), tone: model.debt > 0 ? .loss : .neutral, identifier: AXID.Status.debt,
                       help: "What you owe. Interest is charged on every warp")
                divider
                PMStat(label: "Bays", value: "\(model.filledBays)/\(model.totalBays)",
                    tone: model.filledBays >= model.totalBays && model.totalBays > 0 ? .caution : .neutral,
                       identifier: AXID.Status.bays, help: "Cargo bays in use. Trade on the Bridge")
                PMStat(label: "Fuel", value: "\(model.fuel)/\(model.fuelCapacity)", tone: model.fuelShort ? .caution : .neutral, identifier: AXID.Status.fuel,
                       help: "Fuel in parsecs and tank size. Fill the tank on the Bridge")
                PMStat(label: "Hull", value: StatusBarText.percent(model.hullPercent),
                    tone: model.hullPercent < 25 ? .loss : (model.hullPercent < 50 ? .caution : .neutral),
                       identifier: AXID.Status.hull, help: "Hull strength. Repair on the Bridge")
                PMStat(label: "Shields", value: model.shieldPercent.map(StatusBarText.percent) ?? String(localized: "none"), identifier: AXID.Status.shields,
                       help: "Shield charge. Buy shields on the Equipment page")
                divider
                message(model, state: state)
            }
            .pmPadding(.horizontal, PMSpace.m)
            .frame(maxWidth: .infinity, minHeight: 36 * scale, alignment: .leading)
            .background(PMColor.panelInset)
            .overlay(alignment: .bottom) { Rectangle().fill(PMColor.hairline).frame(height: 1) }
            .overlay(alignment: .topLeading) {
                if showFeed {
                    FeedOverlay(groups: FeedGroup.make(session.feed), state: state,
                                showLogbookEnabled: LogbookLinks.feedShowLogbookEnabled(state: state, inputLocked: session.isInputLocked),
                                showLogbook: { session.showLogbook(tab: .log) }, dismiss: { showFeed = false })
                        .offset(x: PMSpace.m * scale, y: 40 * scale)  // below the bar, which is at the top of the window
                }
            }
            .zIndex(1)
            // UI-KEYS-018: the window's Esc router closes the overlay (level 7).
            .escapeHandler(.closeFeed, active: showFeed) { showFeed = false }
            .task(id: session.rejectionSerial) {
                visibleRejection = session.lastRejection
                guard visibleRejection != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { visibleRejection = nil }
            }
            .onChange(of: session.lastRejection) { _, new in if new == nil { visibleRejection = nil } }
            .task(id: session.arrivalCard?.summary) {
                // The step that ends a trip adds its events after the summary is set; mark the feed once it has settled.
                arrivalFeedMark = nil
                await Task.yield()
                arrivalFeedMark = session.arrivalCard == nil ? nil : session.feed.count
            }
            .accessibilityElement(children: .contain)
            .probed(AXID.Status.bar)
        }
    }

    private var divider: some View {
        Rectangle().fill(PMColor.hairline).frame(width: 1, height: 18 * scale).accessibilityHidden(true)
    }

    private func location(_ model: StatusBarModel) -> some View {
        let text = model.transit.map { String(localized: "To \($0.destination), \($0.clicks) clicks · Day \(model.day)") }
            ?? String(localized: "\(model.systemName) · Day \(model.day)")
        return HStack(spacing: PMSpace.xs * scale) {
            Image(systemName: model.transit == nil ? "mappin.and.ellipse" : "arrow.right.circle").foregroundStyle(PMColor.accent).accessibilityHidden(true)
            Text(verbatim: text).pmFont(.valueLarge).foregroundStyle(PMColor.textPrimary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Location"))
        .accessibilityValue(Text(verbatim: text))
        .accessibilityAddTraits(.isStaticText)
        .help(Text("Where you are and the day of your voyage"))
        .probed(AXID.Status.location)
    }

    /// The one message slot: a rejection for four seconds, otherwise the latest event. A click opens Recent Events.
    private func message(_ model: StatusBarModel, state: GameState) -> some View {
        let latest = model.latestFeed.map { FeedText.text(for: $0.entry, state: state) }
        // UI-BRG-042: after a trip the slot holds the arrival summary until something newer happens; a click opens the report.
        let arrival = session.arrivalCard.flatMap { report in arrivalFeedMark.map { $0 == session.feed.count } ?? true ? report : nil }
        return Button {
            if let arrival, visibleRejection == nil {
                session.present(.sheet(.report(.arrival(arrival))))
            } else {
                showFeed.toggle()
            }
        } label: {
            HStack(spacing: PMSpace.xs * scale) {
                if let reason = visibleRejection {
                    Image(systemName: PMTone.caution.symbol ?? "exclamationmark.triangle.fill").foregroundStyle(PMColor.caution).accessibilityHidden(true)
                    Text(ReasonText.text(for: reason)).foregroundStyle(PMColor.caution).probed(AXID.Status.reason)
                } else if let arrival {
                    Image(systemName: "flag.checkered").foregroundStyle(PMColor.accent).accessibilityHidden(true)
                    Text(verbatim: arrival.summary).foregroundStyle(PMColor.textPrimary)
                } else if let latest, let item = model.latestFeed {
                    Image(systemName: FeedStyle.classify(item.entry).symbol).foregroundStyle(PMColor.textSecondary).accessibilityHidden(true)
                    Text(verbatim: latest).foregroundStyle(PMColor.textPrimary)
                } else {
                    Text("No events yet.").foregroundStyle(PMColor.textSecondary)
                }
            }
            .pmFont(.body)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: PointerTarget.minimum * scale, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -4 * scale)
        .help(arrival.map { Text("\($0.summary). Click to read the arrival report") } ?? latest.map { Text(verbatim: $0) } ?? Text("Show recent events"))
        // The slot is the arrival summary's button while it shows it (UI-BRG-042), the Recent Events button otherwise.
        .probed(arrival != nil && visibleRejection == nil ? AXID.Arrival.card : AXID.Status.feed)
    }
}

/// Number formats of the status bar.
enum StatusBarText {
    static func credits(_ amount: Int) -> String { String(localized: "\(amount.formatted()) cr.") }
    static func percent(_ value: Int) -> String { String(localized: "\(value)%") }
}
