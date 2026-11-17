// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import CoreTransferable
import ParsecEngine
import SwiftUI
import UniformTypeIdentifiers

/// UI-ENC-083: the career card. Also rendered as the shared PNG (UI-ENC-085), so it reads only its `CareerCard`.
struct CareerCardView: View {
    let card: CareerCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: card.commanderName).scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(verbatim: CareerText.ship(card)).foregroundStyle(.readableSecondary)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("Rules", Text("\(Text(Names.ruleset(card.ruleset))) · \(Text(Names.difficulty(card.difficulty)))"))
                row("Galaxy code", Text(verbatim: card.galaxyCode).monospaced())
                row("Ending", Text(Names.ending(card.end)))
                row("Days", Text(card.days, format: .number).monospacedDigit())
                row("Worth", Text("\(card.worth.formatted()) cr.").monospacedDigit())
                row("Score", Text(verbatim: card.scoreText).monospacedDigit())
                row("Police record", Text(Names.policeRecord(card.policeRecord)))
                row("Reputation", Text(Names.reputation(card.reputation)))
                row("Kills", Text("\(card.totalKills) (pirates \(card.piratesKilled), police \(card.policeKilled), traders \(card.tradersKilled))")
                    .monospacedDigit())
                row("Cash", Text("\(card.cash.formatted()) cr.").monospacedDigit())
                row("Debt", Text("\(card.debt.formatted()) cr.").monospacedDigit())
                if let s = card.stats {
                    // STAT-021: the log-based totals.
                    row("Encounters", Text("won \(s.encountersWon), fled \(s.encountersFled), surrendered \(s.encountersSurrendered)")
                        .monospacedDigit())
                    row("Best trade", Text(verbatim: CareerText.bestTrade(s.bestTrade)))
                    row("Systems visited", Text("\(s.systemsVisited) of \(s.systemCount)").monospacedDigit())
                    row("Parsecs travelled", Text(s.parsecsTravelled, format: .number).monospacedDigit())
                    row("Achievements", Text(s.achievementsUnlocked, format: .number).monospacedDigit())
                }
            }
            let badges = CareerText.badges(card)
            if !badges.isEmpty {
                HStack {
                    ForEach(badges, id: \.self) { badge in
                        Text(verbatim: badge)
                            .scaledFont(.caption, weight: .bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(Capsule().strokeBorder(.secondary))
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 440, alignment: .leading)
    }

    private func row(_ label: LocalizedStringResource, _ value: Text) -> some View {
        GridRow {
            Text(label).foregroundStyle(.readableSecondary)
            value
        }
    }
}

/// UI-ENC-085: renders the career card as PNG data at scale 2, with no window chrome.
enum CareerCardRenderer {
    static func image(card: CareerCard) -> CGImage? {
        let content = CareerCardView(card: card)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.cgImage
    }

    static func png(card: CareerCard) -> Data? {
        guard let image = image(card: card) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// UI-ENC-085: the `Transferable` PNG behind the Share button. The image is rendered when the share is performed.
nonisolated struct CareerCardImage: Transferable, Sendable {
    let card: CareerCard

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let data = await MainActor.run(body: { CareerCardRenderer.png(card: item.card) }) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName("Parsec Merchant Career.png")
    }
}
