import SwiftUI

struct GeometryStudioApp: App {
    var body: some Scene {
        DocumentGroup { document in
            DocumentWorkspace(document: document)
        } makeDocument: { _, _ in
            SketchFileDocument(
                sketch: SketchModel.blankDocument(settings: AppPreferences.canvasSettings())
            )
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
