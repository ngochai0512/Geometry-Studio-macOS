import SwiftUI

struct GeometryStudioApp: App {
    var body: some Scene {
        DocumentGroup { document in
            DocumentWorkspace(document: document)
        } makeDocument: { configuration, _ in
            let document = SketchFileDocument(
                sketch: SketchModel.blankDocument(settings: AppPreferences.canvasSettings())
            )
            document.fileURL = configuration.fileURL
            return document
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
