import SwiftUI

struct GeometryStudioApp: App {
    var body: some Scene {
        DocumentGroup(
            newDocument: SketchFileDocument(
                sketch: SketchModel.welcomeDocument(settings: AppPreferences.canvasSettings())
            )
        ) { configuration in
            DocumentWorkspace(configuration: configuration)
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
