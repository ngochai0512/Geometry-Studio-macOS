import AppKit
import Foundation

// A normal launch opens the sketch window. A --screenshot launch draws the
// same window without taking focus, saves a PNG, and exits.
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
