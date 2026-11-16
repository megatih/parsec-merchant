// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecPersistence
import SwiftUI

/// The rows of the Open sheet and what each button may do (UI-SHELL-088, SAV-047). Pure over the slot list.
struct OpenSavedModel: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String
        var slot: SlotInfo
        /// SAV-047: the loaded Ironman game's own slot can't be opened again.
        var canOpen: Bool
    }

    var rows: [Row]

    static func make(slots: [SlotInfo], ironmanSlotID: String?) -> OpenSavedModel {
        OpenSavedModel(rows: slots.map { Row(id: $0.id, slot: $0, canOpen: $0.id != ironmanSlotID) })
    }

    func row(_ id: String?) -> Row? { rows.first { $0.id == id } }
    func canOpen(_ id: String?) -> Bool { row(id)?.canOpen ?? false }
    func canExportOrDelete(_ id: String?) -> Bool { row(id) != nil }
}

/// File › Open Saved Game… (UI-SHELL-088): slots with Open, Export…, Delete… and Cancel.
struct OpenSavedGameSheet: View {
    @Environment(GameSession.self) private var session
    @State private var model = OpenSavedModel(rows: [])
    @State private var selection: String?
    @State private var pendingDelete: String?
    @State private var pendingExport: PendingExport?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open Saved Game")
                .font(.title2.bold())
            if model.rows.isEmpty {
                Text("No saved games yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .accessibilityIdentifier(AXID.Files.list)
            } else {
                List(model.rows, selection: $selection) { row in
                    RecentSlotRow(slot: row.slot)
                        .opacity(row.canOpen ? 1 : 0.5)
                        .help(row.canOpen ? Text(verbatim: "") : Text("This Ironman game is already loaded."))
                        .accessibilityIdentifier(AXID.Files.row(row.id))
                }
                .contextMenu(forSelectionType: String.self) { _ in
                    EmptyView()
                } primaryAction: { ids in
                    if let id = ids.first, model.canOpen(id) { open(id) }
                }
                .frame(minHeight: 240)
                .accessibilityIdentifier(AXID.Files.list)
            }
            HStack {
                Button("Export…") { exportSelection() }
                    .disabled(!model.canExportOrDelete(selection))
                    .accessibilityIdentifier(AXID.Files.export)
                Button("Delete…", role: .destructive) { pendingDelete = selection }
                    .disabled(!model.canExportOrDelete(selection))
                    .accessibilityIdentifier(AXID.Files.delete)
                Spacer()
                Button("Cancel", role: .cancel) { session.dismissPresentation() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.Files.cancel)
                Button("Open") { if let selection { open(selection) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canOpen(selection))
                    .accessibilityIdentifier(AXID.Files.open)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: reload)
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible) {
            Button(deleteContent.confirmLabel, role: .destructive) {
                if let id = pendingDelete { session.deleteSlot(id) }
                pendingDelete = nil
                reload()
            }
            .accessibilityIdentifier(AXID.Dialog.appConfirmationConfirm)
            Button("Cancel", role: .cancel) { pendingDelete = nil }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AXID.Dialog.appConfirmationCancel)
        } message: {
            Text(verbatim: deleteContent.message)
        }
        .fileExporter(isPresented: exportBinding, document: pendingExport?.document, contentType: .parsecSave,
                      defaultFilename: pendingExport?.defaultName) { result in
            if case let .failure(error) = result {
                session.present(.systemAlert(.saveFailed(reason: SlotText.saveFailure(error))))
            }
            pendingExport = nil
        }
    }

    private var deleteContent: ConfirmationContent {
        AppConfirmationText.content(for: .deleteSlot(pendingDelete ?? ""), session: session)
    }

    private var deleteTitle: Text { Text(verbatim: deleteContent.title) }

    private var deleteBinding: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
    }

    private var exportBinding: Binding<Bool> {
        Binding { pendingExport != nil } set: { if !$0 { pendingExport = nil } }
    }

    private func reload() {
        let ironman = session.state?.ironman == true ? session.gameID : nil
        model = OpenSavedModel.make(slots: session.listSlots(), ironmanSlotID: ironman)
        if model.row(selection) == nil { selection = model.rows.first(where: \.canOpen)?.id }
    }

    private func open(_ id: String) {
        session.dismissPresentation()
        session.requestOpen(slotID: id)
    }

    private func exportSelection() {
        guard let row = model.row(selection) else { return }
        pendingExport = session.makeSlotExport(row.slot)
    }
}
