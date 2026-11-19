import AppKit
import SwiftUI

enum ScreenshotRunner {
    @MainActor
    static func run(outputPath: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let width: CGFloat = 1280
        let height: CGFloat = 820
        let model = SketchModel.sample()
        let content = ContentView(model: model)
            .frame(width: width, height: height)
            .environment(\.colorScheme, .light)

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.wantsLayer = true

        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.level = .normal
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderFrontRegardless()

        var frames = 0
        var finished = false
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { timer in
            // The timer is scheduled on RunLoop.main, so this is already the main
            // thread; assumeIsolated states that for the main-actor work below.
            MainActor.assumeIsolated {
                frames += 1
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
                if frames >= 120 && !finished {
                    finished = true
                    timer.invalidate()
                    let saved = capture(window: window, hosting: hosting, fallbackContent: content,
                                        width: width, height: height, path: outputPath)
                    if !saved {
                        fputs("Could not save the screenshot to \(outputPath)\n", stderr)
                    }
                    app.terminate(nil)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        app.run()
    }

    @MainActor
    private static func capture(window: NSWindow, hosting: NSView,
                                fallbackContent: some View, width: CGFloat, height: CGFloat,
                                path: String) -> Bool {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            rep.size = hosting.bounds.size
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if !isBlank(rep), let data = rep.representation(using: .png, properties: [:]) {
                return write(data, to: path)
            }
        }

        // A borderless, unfocused window can decline to draw on some systems.
        // Rendering the same SwiftUI content offscreen keeps the check reliable.
        let renderer = ImageRenderer(content: fallbackContent)
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.scale = 1
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            return write(data, to: path)
        }
        return false
    }

    private static func write(_ data: Data, to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            fputs("Screenshot write failed: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    private static func isBlank(_ rep: NSBitmapImageRep) -> Bool {
        guard let data = rep.bitmapData else {
            return false
        }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 10, height > 10 else {
            return true
        }
        let samplesX = 40
        let samplesY = 30
        var nonWhite = 0
        var total = 0
        for y in stride(from: 2, to: height - 2, by: max(1, height / samplesY)) {
            for x in stride(from: 2, to: width - 2, by: max(1, width / samplesX)) {
                let offset = y * rep.bytesPerRow + x * 4
                guard offset + 3 < rep.bytesPerRow * height else {
                    continue
                }
                let r = data[offset], g = data[offset + 1], b = data[offset + 2], a = data[offset + 3]
                total += 1
                if a > 8 && (r < 244 || g < 244 || b < 244) {
                    nonWhite += 1
                }
            }
        }
        return total == 0 || Double(nonWhite) / Double(total) < 0.004
    }
}
