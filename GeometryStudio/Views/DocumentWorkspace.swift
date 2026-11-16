import SwiftUI

struct DocumentWorkspace: View {
    @Binding var document: SketchFileDocument
    let fileURL: URL?
    @StateObject private var model: SketchModel
    @State private var recoveryNote: String?

    init(configuration: FileDocumentConfiguration<SketchFileDocument>) {
        _document = configuration.$document
        fileURL = configuration.fileURL
        _model = StateObject(wrappedValue: SketchModel(document: configuration.document.sketch))
        _recoveryNote = State(initialValue: configuration.document.recoveryNote)
    }

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 900, minHeight: 620)
            .focusedSceneValue(\.sketchModel, model)
            .onAppear {
                if document.sketch != model.document {
                    document.sketch = model.document
                }
            }
            .onChange(of: model.document) { newValue in
                if document.sketch != newValue {
                    document.sketch = newValue
                }
            }
            .onChange(of: document.sketch) { newValue in
                if model.document != newValue {
                    model.adopt(newValue)
                }
            }
            .onChange(of: fileURL) { newValue in
                if let newValue {
                    model.setDocumentTitle(newValue.deletingPathExtension().lastPathComponent)
                }
            }
            .alert("Recovered Damaged Sketch",
                   isPresented: recoveryNotePresented,
                   presenting: recoveryNote) { _ in
                Button("OK", role: .cancel) { recoveryNote = nil }
            } message: { note in
                Text(note)
            }
    }

    private var recoveryNotePresented: Binding<Bool> {
        Binding(
            get: { recoveryNote != nil },
            set: { if !$0 { recoveryNote = nil } }
        )
    }
}
