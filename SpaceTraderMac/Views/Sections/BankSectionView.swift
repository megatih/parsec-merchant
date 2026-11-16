// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Bank section (⌘6): loan, insurance, daily costs and the debt banner (UI-SHELL-082…084).
struct BankSectionView: View {
    @Environment(GameSession.self) private var session
    @State private var borrowAmount = 0
    @State private var repayAmount = 0

    var body: some View {
        ScrollView {
            if let engine = session.engine {
                let model = BankModel.make(engine: engine)
                VStack(alignment: .leading, spacing: 20) {
                    if model.debtWarning { debtBanner }
                    loan(model)
                    insurance(model)
                    costs(model.dailyCosts)
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
        .accessibilityIdentifier(AXID.SectionRoot.root(.bank))
    }

    // MARK: Debt warning (UI-SHELL-084)

    private var debtBanner: some View {
        Label {
            Text("Your debt is very high. At \(BankModel.debtLimit.formatted()) cr. you can no longer trade or travel.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.Bank.debtWarning)
    }

    // MARK: Loan (UI-SHELL-082)

    private func loan(_ m: BankModel) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Debt") { Text("\(m.preview.debt.formatted()) cr.").monospacedDigit() }
                LabeledContent("Maximum loan") { Text(m.loanReason.text) }
                Text("Each warp costs 10% interest: \(m.interestPerWarp.formatted()) cr.")
                    .foregroundStyle(.secondary)
                Divider()
                AmountRow(title: "Borrow", amount: $borrowAmount, limit: m.preview.availableToBorrow, blocker: m.borrowBlocker,
                          fieldID: AXID.Bank.borrowAmount, sliderID: AXID.Bank.borrowSlider, submitID: AXID.Bank.borrowSubmit) {
                    if let c = m.borrowCommand(amount: borrowAmount) { send(c) }
                }
                AmountRow(title: "Repay", amount: $repayAmount, limit: m.preview.maxRepay, blocker: m.repayBlocker,
                          fieldID: AXID.Bank.repayAmount, sliderID: AXID.Bank.repaySlider, submitID: AXID.Bank.repaySubmit) {
                    if let c = m.repayCommand(amount: repayAmount) { send(c) }
                }
                HStack {
                    Spacer()
                    Button("Repay All (\(m.preview.repayAllAmount.formatted()) cr.)") {
                        if let c = m.repayAllCommand { send(c) }
                    }
                    .disabled(m.repayAllCommand == nil)
                    .help(m.repayBlocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Pay back as much of the debt as you can."))
                    .accessibilityIdentifier(AXID.Bank.repayAll)
                }
            }
            .padding(4)
        } label: {
            Text("Loan").font(.headline)
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
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Ship value") { Text("\(m.shipValue.formatted()) cr.").monospacedDigit() }
                LabeledContent("No-claim discount") {
                    HStack {
                        Gauge(value: m.noClaimFraction) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .frame(width: 140)
                        if m.preview.noClaimAtMaximum {
                            Text("\(m.preview.noClaim)% (max)").monospacedDigit()
                        } else {
                            Text("\(m.preview.noClaim)%").monospacedDigit()
                        }
                    }
                }
                .help(Text("Each day without a claim adds 1% discount, up to 90%."))
                LabeledContent(m.preview.insured ? "Daily premium" : "Daily premium if insured") {
                    Text("\(m.premium.formatted()) cr.").monospacedDigit()
                }
                HStack {
                    if m.preview.insured {
                        Text("Your ship is insured.")
                        Spacer()
                        Button("Stop Insurance", role: .destructive) { session.send(.stopInsurance) }
                            .disabled(m.stopInsuranceBlocker != nil)
                            .help(m.stopInsuranceBlocker.map { Text(ReasonText.text(for: $0)) }
                                ?? Text("Stopping resets your no-claim discount."))
                            .accessibilityIdentifier(AXID.Bank.insuranceStop)
                    } else {
                        if let blocker = m.buyInsuranceBlocker {
                            Text(ReasonText.text(for: blocker)).foregroundStyle(.secondary)
                        }
                        if !m.hasEscapePod {
                            Button("Buy an escape pod at the Shipyard") { session.selectedSection = .shipyard }
                                .buttonStyle(.link)
                                .accessibilityIdentifier(AXID.Bank.shipyardLink)
                        }
                        Spacer()
                        Button("Buy Insurance") { session.send(.buyInsurance) }
                            .disabled(!m.preview.canBuyInsurance)
                            .help(m.buyInsuranceBlocker.map { Text(ReasonText.text(for: $0)) }
                                ?? Text("Insurance pays out your ship's value if you escape in your pod."))
                            .accessibilityIdentifier(AXID.Bank.insuranceBuy)
                    }
                }
            }
            .padding(4)
        } label: {
            Text("Insurance").font(.headline)
        }
    }

    // MARK: Daily costs (BNK-061)

    private func costs(_ c: DailyCosts) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Mercenaries") { Text("\(c.mercenaries.formatted()) cr.").monospacedDigit() }
                LabeledContent("Insurance") { Text("\(c.insurance.formatted()) cr.").monospacedDigit() }
                LabeledContent("Interest") { Text("\(c.interest.formatted()) cr.").monospacedDigit() }
                LabeledContent("Wormhole tax") { Text("\(c.wormholeTax.formatted()) cr.").monospacedDigit() }
                LabeledContent("Total") { Text("\(c.total.formatted()) cr.").monospacedDigit().bold() }
            }
            .padding(4)
        } label: {
            Text("Costs of the Next Warp").font(.headline)
        }
        .help(Text("What the next warp to your target will cost."))
    }
}

/// A slider and a field bounded by `0…limit`, with a submit button (Borrow, Repay).
private struct AmountRow: View {
    let title: LocalizedStringResource
    @Binding var amount: Int
    let limit: Int
    let blocker: CommandError?
    let fieldID: String
    let sliderID: String
    let submitID: String
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Slider(value: sliderValue, in: 0...Double(max(1, limit)), step: 1) { Text(title) }
                    .disabled(blocker != nil || limit == 0)
                    .accessibilityIdentifier(sliderID)
                TextField(value: fieldValue, format: .number) { Text(title) }
                    .labelsHidden()
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .disabled(blocker != nil || limit == 0)
                    .accessibilityIdentifier(fieldID)
                    .onSubmit(submit)
                Button { submit() } label: { Text(title) }
                    .disabled(blocker != nil || amount < 1 || amount > limit)
                    .accessibilityIdentifier(submitID)
            }
            .help(blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Up to \(limit.formatted()) cr."))
            if let blocker {
                Text(ReasonText.text(for: blocker)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: limit) { _, new in amount = BankModel.clamp(amount, to: new) }
    }

    private var sliderValue: Binding<Double> {
        Binding(get: { Double(amount) }, set: { amount = BankModel.clamp(Int($0.rounded()), to: limit) })
    }

    private var fieldValue: Binding<Int> {
        Binding(get: { amount }, set: { amount = BankModel.clamp($0, to: limit) })
    }
}
