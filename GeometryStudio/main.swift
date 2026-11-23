import AppKit
import Foundation

// A normal launch opens the sketch window. In a debug build only, a
// --screenshot launch draws the same window without taking focus, saves a PNG,
// and exits; release builds do not carry the screenshot path.
#if DEBUG
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--screenshot"),
   arguments.index(after: flag) < arguments.endIndex {
    let output = arguments[arguments.index(after: flag)]
    MainActor.assumeIsolated {
        ScreenshotRunner.run(outputPath: output)
    }
} else {
    GeometryStudioApp.main()
}
#else
GeometryStudioApp.main()
#endif
