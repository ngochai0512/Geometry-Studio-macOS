import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DocumentWorkspace: View {
    var document: SketchFileDocument
    @StateObject private var model: SketchModel
    @Environment(\.documentConfiguration) private var documentConfiguration

    init(document: SketchFileDocument) {
        self.document = document
        _model = StateObject(wrappedValue: SketchModel(document: document.sketch))
    }

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 900, minHeight: 620)
            .focusedSceneValue(\.sketchModel, model)
            .onChange(of: model.document) { _, newValue in
                if document.sketch != newValue {
                    document.sketch = newValue
                }
            }
            .onChange(of: document.sketch) { _, newValue in
                if model.document != newValue {
                    model.adopt(newValue)
                }
            }
            .dismissalConfirmationDialog(
                "Do you want to save the changes made to “\(displayName)”?",
                shouldPresent: hasUnsavedChanges
            ) {
                Button("Save") {
                    saveSketch()
                }
                .keyboardShortcut(.defaultAction)
                Button("Don't Save", role: .destructive) {}
            } message: {
                Text("Your changes will be lost if you don't save them.")
            }
            .alert("Recovered Damaged Sketch",
                   isPresented: recoveryNotePresented,
                   presenting: document.recoveryNote) { _ in
                Button("OK", role: .cancel) { document.recoveryNote = nil }
            } message: { note in
                Text(note)
            }
    }

    private var hasUnsavedChanges: Bool {
        model.document != document.lastSavedSketch
    }

    private var displayName: String {
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        let title = model.document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "this sketch" : title
    }

    private var defaultFileName: String {
        let title = model.document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(cleaned.isEmpty ? "Sketch" : cleaned).gsp"
    }

    private var fileURL: URL? {
        documentConfiguration?.fileURL ?? document.fileURL
    }

    /// The dialog dismisses the window after this runs, as the modifier's
    /// contract requires, so it saves directly instead of asking the document
    /// architecture for a save it cannot perform synchronously.
    private func saveSketch() {
        guard let data = try? SketchSnapshot(sketch: model.document).encodedData() else {
            presentSaveError("Could not prepare the sketch for saving.")
            return
        }
        if let url = fileURL {
            write(data, to: url)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.geometryStudioSketch]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        write(data, to: url)
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            document.fileURL = url
            document.markSaved(model.document)
        } catch {
            presentSaveError("Could not save “\(url.lastPathComponent)”.")
        }
    }

    private func presentSaveError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = "The sketch may not have been saved."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private var recoveryNotePresented: Binding<Bool> {
        Binding(
            get: { document.recoveryNote != nil },
            set: { value in
                if !value {
                    document.recoveryNote = nil
                }
            }
        )
    }
}

#Preview("Document") {
    DocumentWorkspace(document: SketchFileDocument(sketch: SketchModel.sample().document))
        .frame(width: 1100, height: 760)
}
