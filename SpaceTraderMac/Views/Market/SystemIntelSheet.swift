// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// INT-037: Find Prices: the ten items' sell and buy quotes at a system with source and age, the known resource, the
/// pressure hint and the last visit.
struct SystemIntelSheet: View {
    @Environment(GameSession.self) private var session
    let system: Int
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state = session.state, let inputs = session.intelInputs() {
                let m = SystemIntelModel.make(system: system, book: inputs.book, snapshot: inputs.snapshot)
                Text("Prices at \(Names.system(system, in: state))").font(.title2.bold())
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Item").bold()
                        Text("Sell").bold()
                        Text("Buy").bold()
                        Text("Source").bold()
                    }
                    Divider()
                    ForEach(m.rows, id: \.item) { row in
                        GridRow {
                            Text(Names.item(row.item))
                            Text(verbatim: row.quote.sell.map { $0.formatted() } ?? "—").monospacedDigit()
                            Text(verbatim: row.quote.buy.map { $0.formatted() } ?? "—").monospacedDigit()
                            Text(verbatim: IntelText.age(row.quote)).foregroundStyle(.secondary)
                        }
                        .opacity(row.quote.staleness == .old ? 0.55 : 1)
                        .help(IntelText.help(row.quote))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(AXID.SystemIntel.row(row.item))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: SystemIntelText.resource(m.knownResource))
                    if let hint = m.pressureHint {
                        Text(verbatim: SystemIntelText.pressure(hint))
                    }
                    Text(verbatim: SystemIntelText.lastVisit(m.lastVisit))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.SystemIntel.done)
            }
        }
        .padding(24)
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.SystemIntel.sheet)
    }
}

/// INT-037: the facts lines of the System Intel sheet.
enum SystemIntelText {
    static func resource(_ r: SpecialResource?) -> String {
        guard let r else { return String(localized: "Special resources unknown") }
        return String(localized: SystemText.resource(r))
    }

    static func pressure(_ hint: PressureHint) -> String {
        String(localized: "Day \(hint.day): \(IntelText.pressure(hint.pressure))")
    }

    static func lastVisit(_ v: SystemIntelModel.LastVisit) -> String {
        switch v {
        case let .day(d): String(localized: "Last visit: Day \(d)")
        case .dateUnknown: String(localized: "Last visit: date unknown")
        case .never: String(localized: "Last visit: never")
        }
    }
}
