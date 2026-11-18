import AppKit

/// Drives File ▸ Export: one save panel per format, then writes the file.
@MainActor
enum SketchExporter {

    static func export(_ format: SketchExportFormat, model: SketchModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(fileName(for: model)).\(format.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = data(for: format, model: model) else {
            model.statusMessage = "Could not prepare the \(format.title) export"
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            model.statusMessage = "Exported \(url.lastPathComponent)"
        } catch {
            // The panel already validated the path; a failure here is a write
            // error, and the status line is the app's only non-modal channel.
            model.statusMessage = "Could not save \(url.lastPathComponent)"
        }
    }

    private static func data(for format: SketchExportFormat, model: SketchModel) -> Data? {
        let size = SketchExportMetrics.size
        switch format {
        case .pdf:
            return SketchRenderOutput.pdf(for: model.document, fitting: size)
        case .png:
            return SketchRenderOutput.png(for: model.document, fitting: size)
        case .svg:
            let snapshot = SketchRenderOutput.snapshot(of: model.document, fitting: size)
            let svg = SVGExporter(objects: snapshot.objects,
                                  settings: snapshot.settings,
                                  size: size,
                                  title: model.document.title).svg()
            return svg.data(using: .utf8)
        }
    }

    private static func fileName(for model: SketchModel) -> String {
        let title = model.document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Sketch" : cleaned
    }
}
