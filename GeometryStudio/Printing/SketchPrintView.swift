import AppKit

/// A one-page print view. The sketch is rendered once as an image sized to the
/// imageable page area, then drawn unscaled into that area.
final class SketchPrintView: NSView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SketchPrintView is created in code")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1,
                   respectFlipped: true,
                   hints: nil)
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        bounds
    }
}
