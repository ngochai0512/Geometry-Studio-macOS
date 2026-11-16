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
        panel.allowedContentTypes = [.geometryStudioSketch]
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
            markDocumentClean()
            DocumentDrafts.remove(sessionID: sessionID)
            statusMessage = "Saved to \(url.lastPathComponent)"
        } catch {
            errorAlert = SketchAlert(
                title: "Could Not Save Sketch",
                message: "Geometry Studio could not write \(url.lastPathComponent). \(error.localizedDescription)"
            )
            statusMessage = "Could not save: \(url.lastPathComponent)"
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.title = "Open Sketch"
        panel.allowedContentTypes = [.geometryStudioSketch, .json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(SketchDocument.self, from: data)
            adopt(doc, from: url)
        } catch let error as DocumentError {
            errorAlert = SketchAlert(
                title: "Could Not Open Sketch",
                message: "\(url.lastPathComponent) was saved by a newer version of Geometry Studio. \(error.localizedDescription)"
            )
            statusMessage = "That file needs a newer version of Geometry Studio"
        } catch {
            // Read again only to offer salvage; a failed read has no data.
            let data = (try? Data(contentsOf: url)) ?? Data()
            if var result = SketchDocument.salvage(from: data) {
                result.sourceURL = url
                recoveryOffer = .salvage(result)
            } else {
                errorAlert = SketchAlert(
                    title: "Could Not Open Sketch",
                    message: "\(url.lastPathComponent) is not a Geometry Studio sketch, or it is damaged. \(error.localizedDescription)"
                )
            }
            statusMessage = "That file could not be opened"
        }
    }

    private func adopt(_ doc: SketchDocument, from url: URL) {
        document = doc
        currentURL = url
        selection = []
        draft = []
        isDirty = false
        resetHistory()
        markDocumentClean()
        DocumentDrafts.remove(sessionID: sessionID)
        statusMessage = "Opened \(url.lastPathComponent)"
    }
}
