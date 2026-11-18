import SwiftUI

struct DocumentWorkspace: View {
    var document: SketchFileDocument
    @StateObject private var model: SketchModel

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
            .alert("Recovered Damaged Sketch",
                   isPresented: recoveryNotePresented,
                   presenting: document.recoveryNote) { _ in
                Button("OK", role: .cancel) { document.recoveryNote = nil }
            } message: { note in
                Text(note)
            }
    }

    private var recoveryNotePresented: Binding<Bool> {
        Binding(
            get: { document.recoveryNote != nil },
            set: { if !$0 { document.recoveryNote = nil } }
        )
    }
}

#Preview("Document") {
    DocumentWorkspace(document: SketchFileDocument(sketch: SketchModel.sample().document))
        .frame(width: 1100, height: 760)
}
