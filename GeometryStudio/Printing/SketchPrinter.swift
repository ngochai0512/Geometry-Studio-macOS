import AppKit

/// Renders the canvas for printing and drives the standard print panel.
@MainActor
enum SketchPrinter {
    static func printSketch(_ model: SketchModel) {
        // Render for the page the panel opens with; SketchPrintView refits the
        // image if the panel changes paper or orientation.
        let page = imageableSize()
        guard let image = SketchRenderOutput.image(for: model.document, fitting: page) else {
            model.statusMessage = "Could not prepare the sketch for printing"
            return
        }

        let printInfo = NSPrintInfo.shared
        let view = SketchPrintView(image: image, paperSize: printInfo.paperSize)
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

    /// The page area inside the margins, so one page holds the whole sketch.
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
}
