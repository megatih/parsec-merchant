// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Bank (⌘5, PRD §4.8): Loan, Insurance and the Costs of the Next Warp, three panels side by side.
struct BankPage: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    @State private var borrowAmount = 0
    @State private var repayAmount = 0

    var body: some View {
        GamePage(section: .bank) {
            if let engine = session.engine {
                let model = BankModel.make(engine: engine)
                VStack(alignment: .leading, spacing: PMSpace.s * scale) {
                    if model.debtWarning {
                        PMNote(text: "Your debt is very high. At \(BankModel.debtLimit.formatted()) cr. you can no longer trade or travel.", tone: .loss,
                               identifier: AXID.Bank.debtWarning)
                    }
                    HStack(alignment: .top, spacing: PMSpace.s * scale) {
                        loan(model)
                        insurance(model)
                        costs(model.dailyCosts)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Loan (UI-SHELL-082)

    private func loan(_ m: BankModel) -> some View {
        PMPanel("Loan", identifier: "bank.loan") {
            PMInfoRow("Debt", credits: m.preview.debt)
            PMInfoRow(label: "Maximum loan") { Text(m.loanReason.text) }
            PMNote(text: "Each warp costs 10% interest: \(m.interestPerWarp.formatted()) cr.", tone: .neutral)
            PMDivider()
            BankAmountRow(title: "Borrow", amount: $borrowAmount, limit: m.preview.availableToBorrow, blocker: m.borrowBlocker,
                          fieldID: AXID.Bank.borrowAmount, sliderID: AXID.Bank.borrowSlider, submitID: AXID.Bank.borrowSubmit) {
                if let c = m.borrowCommand(amount: borrowAmount) { send(c) }
            }
            BankAmountRow(title: "Repay", amount: $repayAmount, limit: m.preview.maxRepay, blocker: m.repayBlocker,
                          fieldID: AXID.Bank.repayAmount, sliderID: AXID.Bank.repaySlider, submitID: AXID.Bank.repaySubmit) {
                if let c = m.repayCommand(amount: repayAmount) { send(c) }
            }
            PMButton(title: "Repay All \(m.preview.repayAllAmount.formatted()) cr.", help: "Pay back as much of the debt as you can",
                     disabledReason: m.repayAllCommand == nil ? (m.repayBlocker ?? .noDebt).reason : nil, identifier: AXID.Bank.repayAll) {
                if let c = m.repayAllCommand { send(c) }
            }
        }
    }

    private func send(_ command: Command) {
        session.send(command)
        if let state = session.state {
            borrowAmount = BankModel.clamp(borrowAmount, to: state.bankPreview.availableToBorrow)
            repayAmount = BankModel.clamp(repayAmount, to: state.bankPreview.maxRepay)
        }
    }

    // MARK: Insurance (UI-SHELL-083)

    private func insurance(_ m: BankModel) -> some View {
        PMPanel("Insurance", identifier: "bank.insurance") {
            PMInfoRow("Ship value", credits: m.shipValue)
            PMGauge(label: "No-claim discount", fraction: m.noClaimFraction,
                    valueText: m.preview.noClaimAtMaximum ? String(localized: "\(m.preview.noClaim)% (max)") : StatusBarText.percent(m.preview.noClaim),
                    identifier: "bank.insurance.noClaim")
                .help(Text("Each day without a claim adds 1% discount, up to 90%"))
            PMInfoRow(m.preview.insured ? "Daily premium" : "Daily premium if insured", credits: m.premium)
            PMDivider()
            if m.preview.insured {
                PMNote(text: "Your ship is insured.", tone: .info)
                PMButton(title: "Stop Insurance", kind: .danger, help: "Stopping resets your no-claim discount",
                         disabledReason: m.stopInsuranceBlocker?.reason, identifier: AXID.Bank.insuranceStop) {
                    session.send(.stopInsurance)
                }
            } else {
                if let blocker = m.buyInsuranceBlocker { PMNote(text: ReasonText.text(for: blocker)) }
                if !m.hasEscapePod {
                    PMButton(title: "Buy an escape pod at the Shipyard", systemImage: "arrow.right", kind: .quiet, help: "Open the Shipyard page",
                             identifier: AXID.Bank.shipyardLink) {
                        session.selectedSection = .shipyard
                    }
                }
                PMButton(title: "Buy Insurance", kind: .primary, help: "Insurance pays out your ship's value if you escape in your pod",
                         disabledReason: m.preview.canBuyInsurance ? nil : (m.buyInsuranceBlocker ?? .notAllowedInPhase).reason,
                         identifier: AXID.Bank.insuranceBuy) {
                    session.send(.buyInsurance)
                }
            }
        }
    }

    // MARK: Costs (BNK-061)

    private func costs(_ c: DailyCosts) -> some View {
        PMPanel("Costs of the Next Warp", identifier: "bank.costs") {
            PMInfoRow("Mercenaries", credits: c.mercenaries)
            PMInfoRow("Insurance", credits: c.insurance)
            PMInfoRow("Interest", credits: c.interest)
            PMInfoRow("Wormhole tax", credits: c.wormholeTax)
            PMDivider()
            PMInfoRow("Total", credits: c.total)
        }
        .help(Text("What the next warp to your target will cost"))
    }
}

/// A slider and a field bounded by `0…limit`, with a submit button (Borrow, Repay).
private struct BankAmountRow: View {
    let title: LocalizedStringResource
    @Binding var amount: Int
    let limit: Int
    let blocker: CommandError?
    let fieldID: String
    let sliderID: String
    let submitID: String
    let submit: () -> Void
    @Environment(\.pmScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: PMSpace.xs * scale) {
            HStack(spacing: PMSpace.s * scale) {
                Slider(value: sliderValue, in: 0...Double(max(1, limit)), step: Double(BankSlider.step(limit: limit))) { Text(title) }
                    .labelsHidden()
                    .disabled(blocker != nil || limit == 0)
                    .accessibilityLabel(Text(title))  // A11Y-003
                    .accessibilityIdentifier(sliderID)
                PMField(text: fieldText, prompt: "0", label: "\(String(localized: title)) amount in credits", identifier: fieldID)
                    .frame(width: 84 * scale)
                    .disabled(blocker != nil || limit == 0)
                    .onSubmit(submit)
                PMButton(title: title, disabledReason: blocker?.reason ?? (amount < 1 || amount > limit ? String(localized: "Enter a valid amount.") : nil),
                         identifier: submitID, action: submit)
                    .fixedSize()
            }
            .help(blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Up to \(limit.formatted()) cr."))
            if let blocker { PMNote(text: ReasonText.text(for: blocker)) }
        }
        .onChange(of: limit) { _, new in amount = BankModel.clamp(amount, to: new) }
    }

    private var sliderValue: Binding<Double> {
        Binding(get: { Double(amount) }, set: { amount = BankModel.clamp(Int($0.rounded()), to: limit) })
    }

    private var fieldText: Binding<String> {
        Binding(get: { amount == 0 ? "" : String(amount) }, set: { amount = BankModel.clamp(Int($0.filter(\.isNumber)) ?? 0, to: limit) })
    }
}
