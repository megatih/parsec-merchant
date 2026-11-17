// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The bottom status bar (UI-SHELL-044/045) with the feed overlay (an overlay, never a popover).
struct StatusBarView: View {
    @Environment(GameSession.self) private var session
    @State private var showFeed = false
    @State private var visibleRejection: CommandError?

    var body: some View {
        if let state = session.state {
            let model = StatusBarModel.make(state: state, feed: session.feed)
            HStack(spacing: 16) {
                Text("Bays \(model.filledBays)/\(model.totalBays)")
                    .help(Text("Cargo bays in use / total."))
                    .accessibilityIdentifier(AXID.Status.bays)
                Text("Fuel \(model.fuel)/\(model.fuelCapacity)")
                    .help(Text("Fuel in parsecs / tank size."))
                    .accessibilityIdentifier(AXID.Status.fuel)
                Text("Hull \(model.hullPercent)%")
                    .help(Text("Hull strength."))
                    .accessibilityIdentifier(AXID.Status.hull)
                Divider().frame(height: 14)
                if let reason = visibleRejection {
                    Text(ReasonText.text(for: reason))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier(AXID.Status.reason)
                }
                if session.arrivalCard != nil, session.selectedSection != .bridge, !session.isInputLocked {
                    // UI-ENC-055: arrival never changes the section; this chip leads to the card on Bridge.
                    Button {
                        session.selectedSection = .bridge
                    } label: {
                        Label("Arrival report", systemImage: "flag.checkered")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(Text("Show the arrival report on Bridge."))
                    .accessibilityIdentifier(AXID.Arrival.statusChip)
                }
                Button {
                    showFeed.toggle()
                } label: {
                    if let latest = model.latestFeed {
                        HStack(spacing: 4) {
                            Image(systemName: FeedStyle.classify(latest.entry).symbol)
                            Text(verbatim: FeedText.text(for: latest.entry, state: state))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        Text("No events yet.")
                    }
                }
                .buttonStyle(.plain)
                .help(Text("Show recent events."))
                .accessibilityIdentifier(AXID.Status.feed)
                Spacer()
            }
            .font(.callout)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(alignment: .bottomLeading) {
                if showFeed {
                    FeedOverlay(groups: FeedGroup.make(session.feed), state: state,
                                showLogbookEnabled: LogbookLinks.feedShowLogbookEnabled(state: state, inputLocked: session.isInputLocked),
                                showLogbook: { session.showLogbook(tab: .log) }, dismiss: { showFeed = false })
                        .offset(y: -34)
                }
            }
            // UI-KEYS-018: the window's Esc router closes the overlay (level 7).
            .escapeHandler(.closeFeed, active: showFeed) { showFeed = false }
            .task(id: session.rejectionSerial) {
                visibleRejection = session.lastRejection
                guard visibleRejection != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { visibleRejection = nil }
            }
            .onChange(of: session.lastRejection) { _, new in if new == nil { visibleRejection = nil } }
        }
    }
}
