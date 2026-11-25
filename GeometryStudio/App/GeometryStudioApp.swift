import SwiftUI

struct GeometryStudioApp: App {
    var body: some Scene {
        DocumentGroup { document in
            DocumentWorkspace(document: document)
        } makeDocument: { _, _ in
            let settings = AppPreferences.canvasSettings()
            let sketch: SketchDocument
            if let template = TemplateLibrary.pending {
                TemplateLibrary.pending = nil
                sketch = template.document(settings: settings)
            } else {
                sketch = SketchModel.blankDocument(settings: settings)
            }
            return SketchFileDocument(sketch: sketch)
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            SketchCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
