import SwiftUI

struct GeometryStudioApp: App {
    var body: some Scene {
        DocumentGroup { document in
            DocumentWorkspace(document: document)
        } makeDocument: { _, _ in
            SketchFileDocument(
                sketch: SketchModel.welcomeDocument(settings: AppPreferences.canvasSettings())
            )
        }
        .defaultSize(width: 1320, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SketchCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
