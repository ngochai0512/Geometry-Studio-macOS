import SwiftUI
import AppKit

struct GeometryStudioApp: App {
    @StateObject private var model: SketchModel

    init() {
        _model = StateObject(wrappedValue: SketchModel.sample())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SketchCommands(model: model)
        }
    }
}
