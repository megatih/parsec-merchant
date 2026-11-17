// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// Outfitter section (⌘4): slots and items for sale per group, and the detail pane (UI-SHELL-077/078).
struct OutfitterSectionView: View {
    @Environment(GameSession.self) private var session
    @State private var selection: OutfitterSelection?

    var body: some View {
        Group {
            if let state = session.state {
                let model = OutfitterModel.make(state: state)
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !model.hasEquipmentForSale {
                                Text("No equipment for sale here.")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(model.groups) { group($0) }
                        }
                        .padding()
                    }
                    Divider()
                    detail(state: state)
                        .frame(width: 280)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.SectionRoot.root(.outfitter))
    }

    // MARK: Groups

    private func group(_ g: OutfitterGroupModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(g.group.title).font(.title3.bold())
            Text("Your slots").font(.subheadline).foregroundStyle(.secondary)
            if g.tiles.isEmpty {
                Text("No slots").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(g.tiles) { tile($0, group: g.group) }
                }
            }
            Text("For sale").font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
            if g.offers.isEmpty {
                Text("None for sale here.").foregroundStyle(.secondary)
            } else {
                ForEach(g.offers, id: \.item) { offer($0) }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Outfitter.group(g.group))
    }

    private func tile(_ t: SlotTile, group: OutfitterGroup) -> some View {
        let isSelected = t.installed.map { selection == .installed($0.item, slot: t.slot) } ?? false
        return VStack(alignment: .leading, spacing: 4) {
            if let item = t.installed {
                Text(EquipmentText.name(item.item)).font(.callout.bold())
                if let charge = t.charge {
                    Text("Charge \(charge)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Button("Sell for \(item.sellPrice.formatted()) cr.") {
                    selection = nil
                    session.send(item.sellCommand)
                }
                .controlSize(.small)
                .disabled(item.sellBlocker != nil)
                .help(item.sellBlocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Sell this item."))
                .accessibilityIdentifier(AXID.Outfitter.sell(group, slot: t.slot))
            } else {
                Text("Free slot").foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
        }
        .contentShape(Rectangle())
        .onTapGesture { if let item = t.installed { selection = .installed(item.item, slot: t.slot) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Outfitter.slot(group, slot: t.slot))
    }

    private func offer(_ o: EquipmentOffer) -> some View {
        HStack {
            Text(EquipmentText.name(o.item))
            Spacer()
            Text("\(o.buyPrice.formatted()) cr.").monospacedDigit()
            Button("Buy") { session.send(o.item.buyCommand) }
                .disabled(o.buyBlocker != nil)
                .help(o.buyBlocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Buy this item."))
                .accessibilityIdentifier(AXID.Outfitter.buy(o.item))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(selection == .offer(o.item) ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { selection = .offer(o.item) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Outfitter.offer(o.item))
    }

    // MARK: Detail pane (UI-SHELL-078)

    @ViewBuilder private func detail(state: GameState) -> some View {
        Group {
            if let selection {
                let d = EquipmentDetail.make(item: selection.item, installedSlot: selection.slot, state: state)
                let blocker = selection.slot == nil ? state.equipmentBuyBlocker(selection.item) : nil
                Form {
                    SwiftUI.Section {
                        HStack {
                            EquipmentIcon(item: selection.item)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading) {
                                Text(EquipmentText.name(d.item)).font(.headline)
                                Text(EquipmentText.kind(d.item)).foregroundStyle(.secondary)
                            }
                        }
                        Text(EquipmentText.description(d.item))
                    }
                    SwiftUI.Section {
                        if let p = d.power { LabeledContent("Power") { Text(verbatim: p.formatted()).monospacedDigit() } }
                        if let c = d.charge { LabeledContent("Charge") { Text(verbatim: c.formatted()).monospacedDigit() } }
                        if let s = d.skillBonus { LabeledContent("Improves") { Text(Names.skill(s)) } }
                        LabeledContent("Buy price") {
                            if let b = d.buyPrice { Text("\(b.formatted()) cr.").monospacedDigit() } else { Text("Not sold here") }
                        }
                        LabeledContent("Sell price") { Text("\(d.sellPrice.formatted()) cr.").monospacedDigit() }
                        LabeledContent("vs. current") { comparison(d.comparison) }
                    }
                    if let blocker {
                        Text(ReasonText.text(for: blocker)).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("Select an item", systemImage: "wrench.and.screwdriver",
                                       description: Text("Choose an item for sale or one of your slots."))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Outfitter.detail)
    }

    @ViewBuilder private func comparison(_ c: EquipmentDetail.Comparison) -> some View {
        switch c {
        case .nothingInstalled:
            Text("None installed")
        case let .power(best, delta):
            Text("\(ShipCompare.deltaText(delta)) vs. \(String(localized: EquipmentText.name(best)))")
                .foregroundStyle(delta > 0 ? .green : (delta < 0 ? .red : .secondary))
        case let .owned(count):
            if count == 0 { Text("Not installed") } else { Text("\(count) installed") }
        }
    }

}
