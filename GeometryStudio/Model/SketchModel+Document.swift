import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension SketchModel {

    // MARK: save & open

    func save() {
        if let url = currentURL {
            write(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.title = "Save Sketch"
        panel.nameFieldStringValue = document.title.hasSuffix(".gsp") ? document.title : "\(document.title).gsp"
        panel.allowedContentTypes = [UTType(filenameExtension: "gsp") ?? .json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            write(to: url)
        }
    }

    private func write(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var doc = document
            doc.title = url.deletingPathExtension().lastPathComponent
            let data = try encoder.encode(doc)
            try data.write(to: url, options: .atomic)
            document.title = doc.title
            currentURL = url
            isDirty = false
            statusMessage = "Saved to \(url.lastPathComponent)"
        } catch {
            statusMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.title = "Open Sketch"
        panel.allowedContentTypes = [UTType(filenameExtension: "gsp") ?? .json, .json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(SketchDocument.self, from: data)
            checkpoint()
            document = doc
            currentURL = url
            selection = []
            draft = []
            isDirty = false
            statusMessage = "Opened \(url.lastPathComponent)"
        } catch {
            statusMessage = "That file could not be opened: \(error.localizedDescription)"
        }
    }
}
