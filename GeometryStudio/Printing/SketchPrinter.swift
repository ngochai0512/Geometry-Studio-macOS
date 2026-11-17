import SwiftUI
import AppKit

/// Renders the canvas for printing and drives the standard print panel.
@MainActor
enum SketchPrinter {
    static func printSketch(_ model: SketchModel) {
        guard let image = renderImage(for: model) else {
            model.statusMessage = "Could not prepare the sketch for printing"
            return
        }

        let view = SketchPrintView(image: image)
        let printInfo = NSPrintInfo.shared
        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.jobTitle = model.document.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true

        let printed = operation.run()
        model.statusMessage = printed
            ? "Printed \(model.document.title)"
            : "Printing cancelled"
    }

    static func runPageSetup() {
        _ = NSPageLayout().runModal(with: NSPrintInfo.shared)
    }

    /// Printing is a single page scaled to the imageable area, so the paper
    /// size and orientation from Page Setup are honoured without tiling.
    private static func renderImage(for model: SketchModel) -> NSImage? {
        let pageSize = imageableSize()
        let snapshot = makeSnapshot(of: model, fitting: pageSize)

        let content = SketchCanvas(model: snapshot, onTextAt: { _ in }, printing: true)
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: pageSize.height)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: pageSize)
    }

    private static func imageableSize() -> CGSize {
        let info = NSPrintInfo.shared
        let imageable = info.imageablePageBounds.size
        if imageable.width >= 100, imageable.height >= 100 {
            return imageable
        }
        // Some print backends report an empty imageable area until a printer is
        // chosen; fall back to the paper size minus the configured margins.
        let paper = info.paperSize
        let width = paper.width - info.leftMargin - info.rightMargin
        let height = paper.height - info.topMargin - info.bottomMargin
        return CGSize(width: max(width, 200), height: max(height, 200))
    }

    /// A copy without editing state: no selection ring, draft, hover or traces.
    private static func makeSnapshot(of model: SketchModel, fitting size: CGSize) -> SketchModel {
        let snapshot = SketchModel(document: model.document)
        snapshot.selection = []
        snapshot.draft = []
        snapshot.hoverWorld = nil
        snapshot.tracedIDs = []
        snapshot.tracePaths = [:]
        snapshot.inspectorVisible = false
        snapshot.fitCanvas(size: size)
        return snapshot
    }
}
