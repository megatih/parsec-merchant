// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Region D, the Target System (UI-BRG-020…023): the header, Warp directly under it, the reserved note line, the
/// target buttons, the public facts and the costs of the next warp. Never empty: with no target it shows the current
/// system.
struct BridgeTargetPanel: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    let model: BridgeTargetModel
    @FocusState private var warpFocused: Bool

    var body: some View {
        BridgePanel(identifier: BridgeID.target) {
            VStack(alignment: .leading, spacing: PMSpace.s * scale) {
                header
                warpRow
                note
                buttons
                HStack(alignment: .top, spacing: PMSpace.m * scale) {
                    facts
                    Spacer(minLength: 0)
                    costs
                }
                fuel
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: PMSpace.s * scale) {
            Text(verbatim: model.system.name).pmFont(.title).foregroundStyle(PMColor.textPrimary).fixedSize()
                .accessibilityAddTraits(.isHeader)
                .probed(BridgeID.Target.name)
            Text("\(model.distance) parsecs").pmFont(.value).foregroundStyle(PMColor.textSecondary).fixedSize()
                .probed(BridgeID.Target.distance)
            Spacer(minLength: 0)
            badge
        }
        .frame(height: 22 * scale)
    }

    private var badge: some View {
        switch model.status {
        case .current: PMBadge(text: "Current system", symbol: "location.fill", color: PMColor.textSecondary, identifier: BridgeID.Target.badge)
        case .inRange: PMBadge(text: "In range", symbol: "checkmark.circle", color: PMColor.profit, identifier: BridgeID.Target.badge)
        case .outOfRange: PMBadge(text: "Out of range", symbol: "exclamationmark.triangle.fill", color: PMColor.caution, identifier: BridgeID.Target.badge)
        case .viaWormhole: PMBadge(text: "Via wormhole", symbol: "tornado", color: PMColor.info, identifier: BridgeID.Target.badge)
        }
    }

    // MARK: Warp

    /// Why Warp cannot act: with no target the panel says how to choose one (UI-BRG-020).
    private var warpReason: String? {
        if model.warp.isEnabled { return nil }
        return model.isCurrent && session.isDocked && !session.isInputLocked ? String(localized: "Select a target system on the chart") : model.warp.help
    }

    private var warpRow: some View {
        HStack(spacing: PMSpace.s * scale) {
            // UI-KEYS-019: Return warps only while Warp has the focus; ⌘J is the command.
            PMButton(title: "Warp", kind: .primary, key: "⌘J", fillsWidth: true, disabledReason: warpReason, identifier: BridgeID.Target.warp) {
                session.send(.warp)
            }
            .focused($warpFocused)
            .help(Text(verbatim: warpReason ?? model.warp.help))
            if let jump = model.jump {
                PMButton(title: "Use Singularity", help: "Jump with the portable singularity", disabledReason: jumpReason(jump),
                         identifier: BridgeID.Target.jump) {
                    session.send(.jump)
                }
                .fixedSize()
            }
        }
        .frame(height: PointerTarget.minimum * scale)
    }

    private func jumpReason(_ jump: TargetCardModel.Jump) -> String? {
        if let rejection = jump.rejection { return String(localized: ReasonText.text(for: rejection)) }
        return jump.enabled ? nil : String(localized: ReasonText.text(for: .notAllowedInPhase))
    }

    /// UI-BRG-021: the blocker as text; the line is always there, so nothing moves.
    private var note: some View {
        HStack(spacing: PMSpace.xs * scale) {
            if let warpReason {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(PMColor.caution).accessibilityHidden(true)
                Text(verbatim: warpReason).foregroundStyle(PMColor.caution)
            } else {
                Text("Costs of the warp: \(model.costs.total.formatted()) cr.").foregroundStyle(PMColor.textSecondary)
            }
        }
        .pmFont(.caption)
        .fixedSize()
        .frame(height: 14 * scale)
        .accessibilityElement(children: .combine)
        .probed(BridgeID.Target.note)
    }

    // MARK: Buttons

    private var buttons: some View {
        let locked = session.isInputLocked || !session.isDocked
        let lockedReason = locked ? String(localized: ReasonText.text(for: .notAllowedInPhase)) : nil
        let cycleReason = lockedReason ?? (model.canCycle ? nil : String(localized: "No system is in range"))
        return HStack(spacing: 6 * scale) {
            PMButton(title: "Previous", systemImage: "chevron.backward", help: "Previous system in range (⌘[)", disabledReason: cycleReason,
                     identifier: BridgeID.Target.previous) {
                session.send(.selectNextTarget(forward: false))
            }
            .fixedSize()
            PMButton(title: "Next", systemImage: "chevron.forward", help: "Next system in range (⌘])", disabledReason: cycleReason,
                     identifier: BridgeID.Target.next) {
                session.send(.selectNextTarget(forward: true))
            }
            .fixedSize()
            PMButton(title: model.isTracked ? "Stop Tracking" : "Track",
                     help: model.isTracked ? "Stop tracking this system" : "Keep an arrow to this system on the chart",
                     disabledReason: lockedReason ?? (model.isCurrent ? String(localized: "Select a target system on the chart") : nil),
                     identifier: BridgeID.Target.track) {
                session.send(model.trackCommand)
            }
            .fixedSize()
            PMButton(title: "Find…", help: "Find a system by name (⌥⌘F)", disabledReason: session.isInputLocked ? lockedReason : nil,
                     identifier: BridgeID.Target.find) {
                session.showFindSystem()
            }
            .fixedSize()
        }
        .frame(height: PointerTarget.minimum * scale)
    }

    // MARK: Facts and costs

    /// UI-BRG-023: public facts; the resource only once the system has been visited.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            BridgeFact(label: "Size", labelWidth: 74, identifier: BridgeID.Target.size) { Text(Names.size(model.system.size)) }
            BridgeFact(label: "Tech level", labelWidth: 74, identifier: BridgeID.Target.tech) { Text(SystemText.techLevel(model.system.techLevel)) }
            BridgeFact(label: "Government", labelWidth: 74, identifier: BridgeID.Target.government) {
                Text(SystemText.government(model.system.government))
            }
            BridgeFact(label: "Resources", labelWidth: 74, identifier: BridgeID.Target.resources) { Text(SystemText.resource(model.system.resource)) }
            BridgeFact(label: "Police", labelWidth: 74, identifier: BridgeID.Target.police) { BridgeActivity(activity: model.system.police) }
            BridgeFact(label: "Pirates", labelWidth: 74, identifier: BridgeID.Target.pirates) { BridgeActivity(activity: model.system.pirates) }
        }
    }

    private var costs: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            cost("Mercenaries", model.costs.mercenaries, BridgeID.Target.mercenaries)
            cost("Insurance", model.costs.insurance, BridgeID.Target.insurance)
            cost("Interest", model.costs.interest, BridgeID.Target.interest)
            cost("Wormhole tax", model.costs.wormholeTax, BridgeID.Target.wormholeTax)
            cost("Total", model.costs.total, BridgeID.Target.total)
        }
    }

    private func cost(_ label: LocalizedStringResource, _ value: Int, _ id: String) -> some View {
        BridgeFact(label: label, labelWidth: 80, identifier: id) { Text("\(value.formatted()) cr.").monospacedDigit() }
    }

    private var fuel: some View {
        BridgeFact(label: "Fuel after warp", labelWidth: 100, identifier: BridgeID.Target.fuelAfter) {
            Text("\(model.fuelAfter) parsecs").monospacedDigit()
        }
    }
}
