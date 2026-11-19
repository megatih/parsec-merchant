// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// Equipment (⌘3, PRD §4.6): Weapons, Shields and Gadgets side by side, each with the ship's slots and what is for
/// sale here, and the ship drawn large below so a purchase shows on the hull. Buy and Sell are buttons (UI-PG-020);
/// drag and drop is an accelerator (UI-PTR-010).
struct EquipmentPage: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale

    var body: some View {
        GamePage(section: .outfitter) {
            if let state = session.state {
                let model = OutfitterModel.make(state: state)
                PMFitScroll {
                    VStack(alignment: .leading, spacing: PMSpace.s * scale) {
                        if !model.hasEquipmentForSale {
                            PMNote(text: "No equipment for sale here.", tone: .info, identifier: "outfitter.nothingForSale")
                        }
                        HStack(alignment: .top, spacing: PMSpace.s * scale) {
                            ForEach(model.groups) { g in group(g, state: state) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        shipPanel(model, state: state)
                    }
                }
            }
        }
    }

    // MARK: One kind of equipment

    private func group(_ g: OutfitterGroupModel, state: GameState) -> some View {
        PMPanel(g.group.title, identifier: AXID.Outfitter.group(g.group)) {
            Text("Installed").pmFont(.caption).foregroundStyle(PMColor.textSecondary)
            if g.tiles.isEmpty {
                PMNote(text: "This ship has no slots of this kind.", tone: .neutral)
            }
            ForEach(g.tiles) { t in tile(t, group: g.group) }
            PMDivider()
            Text("For sale").pmFont(.caption).foregroundStyle(PMColor.textSecondary)
            if g.offers.isEmpty {
                PMNote(text: "Nothing of this kind is sold here.", tone: .neutral)
            }
            ForEach(g.offers, id: \.item) { o in offer(o, state: state) }
        }
    }

    private func tile(_ t: SlotTile, group: OutfitterGroup) -> some View {
        HStack(spacing: PMSpace.s * scale) {
            if let item = t.installed {
                EquipmentIcon(item: item.item).frame(width: 28 * scale, height: 28 * scale)
                VStack(alignment: .leading, spacing: 0) {
                    Text(EquipmentText.name(item.item)).pmFont(.body).foregroundStyle(PMColor.textPrimary)
                    if let charge = t.charge {
                        Text("Charge \(charge)").pmFont(.caption).monospacedDigit().foregroundStyle(PMColor.textSecondary)
                    }
                }
                Spacer(minLength: PMSpace.xs * scale)
                PMButton(title: "Sell \(item.sellPrice.formatted()) cr.", compact: true, help: "Sell this item", disabledReason: item.sellBlocker?.reason,
                         identifier: AXID.Outfitter.sell(group, slot: t.slot)) {
                    session.send(item.sellCommand)
                }
                .fixedSize()
            } else {
                Image(systemName: "square.dashed").foregroundStyle(PMColor.textSecondary).frame(width: 28 * scale, height: 28 * scale)
                    .accessibilityHidden(true)
                Text("Empty slot").pmFont(.body).foregroundStyle(PMColor.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, PMSpace.s * scale)
        .frame(maxWidth: .infinity, minHeight: 44 * scale, alignment: .leading)
        .background(PMColor.panelInset, in: RoundedRectangle(cornerRadius: PMRadius.control * scale))
        .overlay { RoundedRectangle(cornerRadius: PMRadius.control * scale).strokeBorder(PMColor.hairline) }
        .help(t.installed.map { Text(EquipmentText.description($0.item)) } ?? Text("A free slot: buy an item of this kind to fill it"))
        // UI-PTR-010: an installed item drags to the sell well; a free slot takes an item for sale of its kind.
        .modifier(SlotDragDrop(tile: t, group: group) { drag in
            guard case let .buy(item) = OutfitterDrop.action(for: drag, onto: .slot(group, free: t.installed == nil),
                                                             buyBlocked: session.state?.equipmentBuyBlocker(drag.item) != nil) else { return false }
            session.send(item.buyCommand)
            return true
        })
        .contextMenu {
            if let item = t.installed {
                Button("Sell for \(item.sellPrice.formatted()) cr.") { session.send(item.sellCommand) }.disabled(item.sellBlocker != nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t.installed.map { Text(EquipmentText.name($0.item)) } ?? Text("Empty slot"))  // A11Y-003
        .accessibilityIdentifier(AXID.Outfitter.slot(group, slot: t.slot))
    }

    private func offer(_ o: EquipmentOffer, state: GameState) -> some View {
        let detail = EquipmentDetail.make(item: o.item, installedSlot: nil, state: state)
        return HStack(spacing: PMSpace.s * scale) {
            EquipmentIcon(item: o.item).frame(width: 28 * scale, height: 28 * scale)
            VStack(alignment: .leading, spacing: 0) {
                Text(EquipmentText.name(o.item)).pmFont(.body).foregroundStyle(PMColor.textPrimary)
                effect(detail).pmFont(.caption).foregroundStyle(PMColor.textSecondary)
            }
            Spacer(minLength: PMSpace.xs * scale)
            Text("\(o.buyPrice.formatted()) cr.").pmFont(.value).foregroundStyle(PMColor.textPrimary).fixedSize()
            PMButton(title: "Buy", compact: true, help: "Buy this item", disabledReason: o.buyBlocker?.reason, identifier: AXID.Outfitter.buy(o.item)) {
                session.send(o.item.buyCommand)
            }
            .fixedSize()
        }
        .padding(.horizontal, PMSpace.s * scale)
        .frame(maxWidth: .infinity, minHeight: 44 * scale, alignment: .leading)
        .contentShape(Rectangle())
        .hoverHighlight(cornerRadius: PMRadius.control)  // UI-PTR-003
        .help(Text("\(String(localized: EquipmentText.description(o.item))) \(o.buyBlocker.map { String(localized: ReasonText.text(for: $0)) } ?? "")"))
        // UI-PTR-006: double-click is the row's primary action; the Buy button stays the one-click path.
        .simultaneousGesture(TapGesture(count: 2).onEnded { if o.buyBlocker == nil { session.send(o.item.buyCommand) } })
        .draggable(OutfitterDragItem(item: o.item, source: .offer))
        .contextMenu {
            Button("Buy for \(o.buyPrice.formatted()) cr.") { session.send(o.item.buyCommand) }.disabled(o.buyBlocker != nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Outfitter.offer(o.item))
    }

    /// The item's power or effect and how it compares with what is installed, in one line.
    private func effect(_ d: EquipmentDetail) -> Text {
        var parts: [String] = []
        if let p = d.power { parts.append(String(localized: "Power \(p)")) }
        if let s = d.skillBonus { parts.append(String(localized: "Improves \(String(localized: Names.skill(s)))")) }
        switch d.comparison {
        case .nothingInstalled: parts.append(String(localized: "None installed"))
        case let .power(best, delta): parts.append(String(localized: "\(ShipCompare.deltaText(delta)) vs. \(String(localized: EquipmentText.name(best)))"))
        case let .owned(count): parts.append(count == 0 ? String(localized: "Not installed") : String(localized: "\(count) installed"))
        }
        return Text(verbatim: parts.joined(separator: " · "))
    }

    // MARK: The ship and the sell well

    private func shipPanel(_ model: OutfitterModel, state: GameState) -> some View {
        PMPanel("Your Ship", identifier: "outfitter.ship") {
            HStack(spacing: PMSpace.m * scale) {
                ShipPortrait(input: ArtAdapters.playerShipInput(state))
                    .frame(maxWidth: .infinity)
                    .frame(height: 150 * scale)
                // UI-PTR-010: the sell well: drop an installed item here to sell it (the slot's Sell button is the click path).
                Label("Drag an installed item here to sell it", systemImage: "arrow.down.to.line")
                    .pmFont(.body)
                    .foregroundStyle(PMColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(PMSpace.m * scale)
                    .frame(width: 220 * scale, height: 110 * scale)
                    .background(RoundedRectangle(cornerRadius: PMRadius.panel * scale)
                        .strokeBorder(PMColor.strongLine, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .dropDestination(for: OutfitterDragItem.self) { drags, _ in
                        guard let drag = drags.first, case let .sell(item, slot) = OutfitterDrop.action(for: drag, onto: .sellWell, buyBlocked: false),
                              let tile = model.groups.first(where: { $0.group == OutfitterDrop.group(of: item) })?.tiles.first(where: { $0.slot == slot }),
                              let installed = tile.installed, installed.item == item, installed.sellBlocker == nil else { return false }
                        session.send(installed.sellCommand)
                        return true
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AXID.Outfitter.sellWell)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
