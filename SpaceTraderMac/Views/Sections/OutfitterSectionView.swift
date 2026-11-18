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
                                    .scaledFont(.headline)
                                    .foregroundStyle(.readableSecondary)
                            }
                            ForEach(model.groups) { group($0) }
                            if model.groups.contains(where: { g in g.tiles.contains { $0.installed != nil } }) { sellWell(model) }
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
            Text(g.group.title).scaledFont(.title3, weight: .bold).accessibilityAddTraits(.isHeader)
            Text("Your slots").scaledFont(.subheadline).foregroundStyle(.readableSecondary)
            if g.tiles.isEmpty {
                Text("No slots").foregroundStyle(.readableSecondary)
            } else {
                AccessibleLazyVGrid(label: "Slots", columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(g.tiles) { tile($0, group: g.group) }
                }
            }
            Text("For sale").scaledFont(.subheadline).foregroundStyle(.readableSecondary).padding(.top, 4)
            if g.offers.isEmpty {
                Text("None for sale here.").foregroundStyle(.readableSecondary)
            } else {
                ForEach(g.offers, id: \.item) { offer($0) }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(g.group.title))
        .accessibilityIdentifier(AXID.Outfitter.group(g.group))
    }

    private func tile(_ t: SlotTile, group: OutfitterGroup) -> some View {
        let isSelected = t.installed.map { selection == .installed($0.item, slot: t.slot) } ?? false
        return VStack(alignment: .leading, spacing: 4) {
            if let item = t.installed {
                Text(EquipmentText.name(item.item)).scaledFont(.callout, weight: .bold)
                if let charge = t.charge {
                    Text("Charge \(charge)").scaledFont(.caption).monospacedDigit().foregroundStyle(.readableSecondary)
                }
                Button {
                    selection = nil
                    session.send(item.sellCommand)
                } label: {
                    Text("Sell for \(item.sellPrice.formatted()) cr.")
                }
                .disabled(item.sellBlocker != nil)
                .help(item.sellBlocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Sell this item."))
                .accessibilityIdentifier(AXID.Outfitter.sell(group, slot: t.slot))
            } else {
                Text("Free slot").foregroundStyle(.readableSecondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
        }
        .hoverHighlight(isEnabled: t.installed != nil)  // UI-PTR-003
        .contentShape(Rectangle())
        .onTapGesture { if let item = t.installed { selection = .installed(item.item, slot: t.slot) } }
        // UI-PTR-010: an installed item drags to the sell well; a free slot takes an item for sale of its kind.
        .modifier(SlotDragDrop(tile: t, group: group) { drag in
            guard case let .buy(item) = OutfitterDrop.action(for: drag, onto: .slot(group, free: t.installed == nil),
                                                             buyBlocked: session.state?.equipmentBuyBlocker(drag.item) != nil) else { return false }
            session.send(item.buyCommand)
            return true
        })
        .contextMenu {
            if let item = t.installed {
                Button("Sell for \(item.sellPrice.formatted()) cr.") {
                    selection = nil
                    session.send(item.sellCommand)
                }
                .disabled(item.sellBlocker != nil)
                .help(item.sellBlocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Sell this item."))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t.installed.map { Text(EquipmentText.name($0.item)) } ?? Text("Free slot"))  // A11Y-003
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
        .hoverHighlight(cornerRadius: 6)  // UI-PTR-003
        .contentShape(Rectangle())
        // UI-PTR-006: double-click is the row's primary action, the same as its Buy button.
        .onTapGesture { selection = .offer(o.item) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { if o.buyBlocker == nil { session.send(o.item.buyCommand) } })
        .draggable(OutfitterDragItem(item: o.item, source: .offer))
        .contextMenu {
            Button("Buy for \(o.buyPrice.formatted()) cr.") { session.send(o.item.buyCommand) }
                .disabled(o.buyBlocker != nil)
                .help(o.buyBlocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Buy this item."))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Outfitter.offer(o.item))
    }

    /// UI-PTR-010: the sell well: drop an installed item here to sell it (the tile's Sell button is the tap path).
    private func sellWell(_ model: OutfitterModel) -> some View {
        Label("Drag an installed item here to sell it", systemImage: "arrow.down.to.line")
            .foregroundStyle(.readableSecondary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .dropDestination(for: OutfitterDragItem.self) { drags, _ in
                guard let drag = drags.first, case let .sell(item, slot) = OutfitterDrop.action(for: drag, onto: .sellWell, buyBlocked: false),
                      let tile = model.groups.first(where: { $0.group == OutfitterDrop.group(of: item) })?.tiles.first(where: { $0.slot == slot }),
                      let installed = tile.installed, installed.item == item, installed.sellBlocker == nil else { return false }
                selection = nil
                session.send(installed.sellCommand)
                return true
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AXID.Outfitter.sellWell)
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
                                Text(EquipmentText.name(d.item)).scaledFont(.headline)
                                Text(EquipmentText.kind(d.item)).foregroundStyle(.readableSecondary)
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
                        Text(ReasonText.text(for: blocker)).foregroundStyle(.readableSecondary)
                    }
                }
                .formStyle(.grouped)
                .labeledContentStyle(ReadableLabeledContentStyle())  // A11Y-029: values at full contrast
            } else {
                // A11Y-029: an own placeholder (ContentUnavailableView draws its title below 4.5:1 contrast).
                VStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver").scaledFont(.largeTitle).foregroundStyle(.readableSecondary)
                        .accessibilityHidden(true)
                    Text("Select an item").scaledFont(.title3, weight: .bold).accessibilityAddTraits(.isHeader)
                    Text("Choose an item for sale or one of your slots.").foregroundStyle(.readableSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .foregroundStyle(delta > 0 ? .signalGreen : (delta < 0 ? .signalRed : .secondary))
        case let .owned(count):
            if count == 0 { Text("Not installed") } else { Text("\(count) installed") }
        }
    }

}

/// UI-PTR-010: a slot tile's drag source (installed item) and drop target (free slot).
private struct SlotDragDrop: ViewModifier {
    let tile: SlotTile
    let group: OutfitterGroup
    let onDrop: (OutfitterDragItem) -> Bool

    func body(content: Content) -> some View {
        if let installed = tile.installed {
            content.draggable(OutfitterDragItem(item: installed.item, source: .installed(slot: tile.slot)))
        } else {
            content.dropDestination(for: OutfitterDragItem.self) { drags, _ in
                return drags.first.map(onDrop) ?? false
            }
        }
    }
}
