// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UniformTypeIdentifiers

/// The saved-game file type (SAV-030), declared in `Config/Info.plist` as an exported type.
nonisolated enum SaveFileType {
    static let identifier = "io.github.megatih.parsecmerchant.save"
    static let fileExtension = "parsecsave"
    static let utType = UTType(exportedAs: identifier, conformingTo: .json)
}

nonisolated extension UTType {
    static let parsecSave = SaveFileType.utType
}

/// The bytes of an exported save, for `fileExporter`.
nonisolated struct SaveFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.parsecSave]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// An export waiting for its file panel: the bytes and the default name.
struct PendingExport: Identifiable {
    let id = UUID()
    var document: SaveFileDocument
    var defaultName: String
}

/// Hosts File › Import… and File › Export… for the main window (SAV-030, UI-SHELL-092/093).
struct FileTransferHost: ViewModifier {
    @Environment(GameSession.self) private var session
    @State private var pendingExport: PendingExport?

    func body(content: Content) -> some View {
        @Bindable var session = session
        content
            .fileImporter(isPresented: $session.isImporterPresented, allowedContentTypes: [.parsecSave]) { result in
                switch result {
                case let .success(url): session.importFile(at: url)
                case let .failure(error): session.present(SlotText.openFailedAlert(error).presentation)
                }
            }
            .background {
                Color.clear
                    .fileExporter(isPresented: exportBinding, document: pendingExport?.document, contentType: .parsecSave,
                                  defaultFilename: pendingExport?.defaultName) { result in
                        if case let .failure(error) = result {
                            session.present(.systemAlert(.saveFailed(reason: SlotText.saveFailure(error))))
                        }
                        pendingExport = nil
                    }
            }
            .onChange(of: session.isExporterPresented) { _, requested in
                guard requested else { return }
                pendingExport = session.makeCurrentExport()
                if pendingExport == nil { session.isExporterPresented = false }
            }
    }

    private var exportBinding: Binding<Bool> {
        Binding {
            session.isExporterPresented && pendingExport != nil
        } set: { shown in
            if !shown {
                session.isExporterPresented = false
            }
        }
    }
}

extension SystemAlert {
    var presentation: Presentation { .systemAlert(self) }
}
