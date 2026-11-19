import AppKit
import SwiftUI

/// Renders a sketch for paper and for export.
///
/// Printing and exporting both work from a fitted snapshot, so the screen,
/// the printed page and every exported file frame the sketch the same way.
/// A snapshot drops editing state: no selection ring, draft, hover or traces.
@MainActor
enum SketchRenderOutput {

    static func snapshot(of document: SketchDocument, fitting size: CGSize) -> SketchModel {
        let snapshot = SketchModel(document: document)
        snapshot.selection = []
        snapshot.draft = []
        snapshot.hoverWorld = nil
        snapshot.tracedIDs = []
        snapshot.tracePaths = [:]
        snapshot.inspectorVisible = false
        snapshot.fitCanvas(size: size)
        return snapshot
    }

    /// The white-page rendering shared by print, PDF and PNG. The canvas tint
    /// and the editing chrome are intentionally absent.
    static func canvas(for document: SketchDocument, fitting size: CGSize) -> some View {
        let snapshot = snapshot(of: document, fitting: size)
        return SketchCanvas(model: snapshot, onTextAt: { _ in }, printing: true)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
    }

    static func cgImage(for document: SketchDocument, fitting size: CGSize,
                        scale: CGFloat = SketchExportMetrics.rasterScale) -> CGImage? {
        let renderer = ImageRenderer(content: canvas(for: document, fitting: size))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        return renderer.cgImage
    }

    static func image(for document: SketchDocument, fitting size: CGSize,
                      scale: CGFloat = SketchExportMetrics.rasterScale) -> NSImage? {
        guard let cgImage = cgImage(for: document, fitting: size, scale: scale) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: size)
    }

    /// True vector PDF: `ImageRenderer.render` replays the SwiftUI drawing into
    /// the PDF context instead of rasterising it first.
    static func pdf(for document: SketchDocument, fitting size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: canvas(for: document, fitting: size))
        renderer.proposedSize = ProposedViewSize(size)
        var data: Data?
        renderer.render { _, draw in
            let output = NSMutableData()
            guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
                return
            }
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                return
            }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            data = output as Data
        }
        return data
    }

    static func png(for document: SketchDocument, fitting size: CGSize,
                    scale: CGFloat = SketchExportMetrics.rasterScale) -> Data? {
        guard let cgImage = cgImage(for: document, fitting: size, scale: scale) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
