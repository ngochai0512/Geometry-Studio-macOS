import AppKit
import CoreTransferable
import UniformTypeIdentifiers

/// Drives File ▸ Export: one save panel per format, then writes the file.
/// The last directory and format are remembered, and the result is posted so
/// the window can show a toast with Show in Finder instead of a status line.
@MainActor
enum SketchExporter {
    private static let directoryKey = "export.lastDirectory"
    private static let formatKey = "export.lastFormat"

    static func export(_ format: SketchExportFormat, model: SketchModel) {
        run(format, model: model)
    }

    /// Repeats the last format so a second export needs one panel, not a menu
    /// choice as well.
    static func exportAgain(model: SketchModel) {
        let raw = UserDefaults.standard.string(forKey: formatKey)
        let format = raw.flatMap(SketchExportFormat.init(rawValue:)) ?? .pdf
        run(format, model: model)
    }

    private static func run(_ format: SketchExportFormat, model: SketchModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(suggestedName(for: model)).\(format.fileExtension)"
        if let directory = UserDefaults.standard.url(forKey: directoryKey) {
            panel.directoryURL = directory
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard let data = data(for: format, model: model) else {
            let message = "Could not prepare the \(format.title) export"
            model.statusMessage = message
            post(model: model, message: message)
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            model.statusMessage = "Exported \(url.lastPathComponent)"
            UserDefaults.standard.set(url.deletingLastPathComponent(), forKey: directoryKey)
            UserDefaults.standard.set(format.rawValue, forKey: formatKey)
            NotificationCenter.default.post(name: .exportFinished, object: model,
                                            userInfo: ["url": url])
        } catch {
            // The panel already validated the path; a failure here is a write
            // error, and the toast is the app's non-modal channel.
            let message = "Could not save \(url.lastPathComponent)"
            model.statusMessage = message
            post(model: model, message: message)
        }
    }

    private static func post(model: SketchModel, message: String) {
        NotificationCenter.default.post(name: .exportFinished, object: model,
                                        userInfo: ["message": message])
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

    static func suggestedName(for model: SketchModel) -> String {
        let title = model.document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Sketch" : cleaned
    }
}

/// Lazily rendered exports for ShareLink. Building one is cheap; the PDF or PNG
/// is rendered and written to a temporary file only when the share sheet asks.
enum SketchShareError: Error {
    case renderFailed
    case writeFailed
}

struct SketchPDFShare: Transferable {
    let document: SketchDocument
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            let url = try await writeTemporaryExport(named: item.name,
                                                     pathExtension: "pdf") {
                SketchRenderOutput.pdf(for: item.document,
                                       fitting: SketchExportMetrics.size)
            }
            return SentTransferredFile(url)
        }
    }
}

struct SketchPNGShare: Transferable {
    let document: SketchDocument
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            let url = try await writeTemporaryExport(named: item.name,
                                                     pathExtension: "png") {
                SketchRenderOutput.png(for: item.document,
                                       fitting: SketchExportMetrics.size)
            }
            return SentTransferredFile(url)
        }
    }
}

private func writeTemporaryExport(
    named name: String,
    pathExtension: String,
    data: @escaping @MainActor () -> Data?
) async throws -> URL {
    let rendered = await MainActor.run { data() }
    guard let rendered else {
        throw SketchShareError.renderFailed
    }
    let base = name.isEmpty ? "Sketch" : name
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GeometryStudioShare-\(UUID().uuidString)", isDirectory: true)
    let url = directory.appendingPathComponent("\(base).\(pathExtension)")
    do {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try rendered.write(to: url, options: .atomic)
    } catch {
        throw SketchShareError.writeFailed
    }
    return url
}
