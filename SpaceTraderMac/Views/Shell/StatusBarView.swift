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
                Button {
                    showFeed.toggle()
                } label: {
                    Text(model.latestFeed.map { EventText.text(for: $0.entry, state: state) } ?? "No events yet.")
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                    FeedOverlay(items: StatusBarModel.overlayItems(session.feed), state: state) { showFeed = false }
                        .offset(y: -34)
                }
            }
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

/// The newest feed items (dismissed by Esc or the close button). "Show Logbook" arrives with LOG in M10.
private struct FeedOverlay: View {
    let items: [FeedItem]
    let state: GameState
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Events").font(.headline)
                Spacer()
                Button("Close", action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text("Day \(item.day)").foregroundStyle(.secondary).monospacedDigit()
                            Text(EventText.text(for: item.entry, state: state))
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 460, height: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
        .accessibilityIdentifier(AXID.Status.feedList)
    }
}
