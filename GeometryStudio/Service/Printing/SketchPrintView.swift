import AppKit

/// A one-page print view.
///
/// The sketch is rendered once as an image for the page the print panel opens
/// with. Page Setup and the print panel can change paper or orientation after
/// that, so the view asks the running operation for the page it is actually
/// printing and centres the image inside it instead of stretching it.
final class SketchPrintView: NSView {
    private let image: NSImage
    private var pageRect: NSRect

    init(image: NSImage, paperSize: CGSize) {
        self.image = image
        // The frame has to cover any page the panel may settle on; the longest
        // paper edge doubled keeps A4/Letter flips and one size up in bounds.
        let longest = max(paperSize.width, paperSize.height,
                          image.size.width, image.size.height)
        let side = max(longest * 2, 612)
        pageRect = NSRect(x: 0, y: 0, width: side, height: side)
        super.init(frame: pageRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SketchPrintView is created in code")
    }

    override var isFlipped: Bool {
        true
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let info = NSPrintOperation.current?.printInfo ?? NSPrintInfo.shared
        let size = info.imageablePageBounds.size
        if size.width > 1, size.height > 1 {
            pageRect = NSRect(origin: .zero, size: size)
        }
        return pageRect
    }

    override func draw(_ dirtyRect: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else {
            return
        }
        let target = pageRect.width > 1 && pageRect.height > 1 ? pageRect : bounds
        let ratio = min(target.width / image.size.width,
                        target.height / image.size.height)
        let drawn = NSSize(width: image.size.width * ratio,
                           height: image.size.height * ratio)
        let rect = NSRect(x: target.midX - drawn.width / 2,
                          y: target.midY - drawn.height / 2,
                          width: drawn.width,
                          height: drawn.height)
        image.draw(in: rect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1,
                   respectFlipped: true,
                   hints: nil)
    }
}
