# Geometry Studio

A native macOS dynamic geometry sketchpad, rebuilt in **Swift and SwiftUI** for Apple silicon.

The original is the reference application 5.06 (2013), a a legacy build application. It
cannot run on Apple silicon; this is a new implementation of the same idea: construct points,
lines, circles and polygons, then drag a free point and watch every dependent object update.

## Build and run

Two build descriptions share one source tree. `Package.swift` drives the SwiftPM targets and
tests; `project.yml` generates the Xcode app that carries `Info.plist`, the exported `gsp`
document type and the icon.

App bundle:

```sh
xcodegen generate
open GeometryStudio.xcodeproj
```

Choose the `GeometryStudio` scheme and Run. The checked-in project is built as it is: Xcode
writes its upgrade settings into that file, so regenerate from `project.yml` only after a
deliberate spec change, and expect to re-apply Xcode's upgrade prompts. XcodeGen is the only
extra tool (`brew install xcodegen`).

Package targets, for a fast edit/run loop and for tests:

```sh
swift build
swift run GeometryStudio
swift test
```

Release build:

```sh
swift build -c release
./.build/release/GeometryStudio
```

Both target macOS 27 or newer and build `arm64` on Apple silicon. `swift test` runs the
geometry, document and undo suites.

CI runs the package build, the tests and the app target on every push and pull request. Tagged
releases archive the checked-in project and publish an arm64 zip and `.dmg` to GitHub Releases:
signed and notarized when the five secrets are configured, otherwise clearly marked unsigned;
see `RELEASING.md` for the secrets and the release steps.

## Screenshot mode

```sh
./.build/release/GeometryStudio --screenshot /tmp/geometry-studio.png
```

This opens a borderless window without activating the app, draws for 120 frames, writes the
window as a PNG and exits. The app-bundle binary accepts the same flag.

## Core features

- **Tools** — select/drag, hand/pan, point, segment, ray, line, circle, polygon, angle marker and text.
- **Constructions** — midpoint, perpendicular, parallel, angle bisector, intersection, segment,
  circle by centre + point, circle by centre + radius, arc on a circle, arc through three points,
  polygon interior, point on object and locus.
- **Measurements** — distance, length, perimeter, circumference, angle, area, radius, ratio,
  coordinates, abscissa/ordinate, polar distance/direction, arc angle/length, equation,
  slope and calculations.
- **Units and precision** — cm, inches or pixels; plain degrees, directed degrees or radians;
  0–5 decimal places, as the original's Units preferences offer.
- **Transforms** — reflect, rotate, dilate and translate. Images keep their source and update.
- **Graph** — grid, axes, snapping and function plots.
- **Animation and tracing** — animate a point along its constraint, trace moving objects, and
  construct a locus from a driver point and the point it drives.
- **Inspector** — object browser, label, definition, colour, line width, dash, point shape and
  size, visibility, fill, arc fill (sector or segment), units, angle unit and decimal precision.
- **Construction protocol** — a sheet listing every construction step in order.
- **Documents** — a document-based app: new, open, save and save as (`.gsp`, JSON document format),
  autosave, Versions, Open Recent, multiple windows and tabs, a revision stamp in the document,
  named undo/redo, automatic recovery of readable objects from a
  damaged file, and a save prompt when a window with unsaved changes closes or the app quits.
- **Printing** — File > Print (⌘P) fits the sketch to one page and uses the standard macOS print
  panel and preview; Page Setup controls paper size, orientation and margins.
- **Export** — File > Export writes a vector PDF, an SVG or a 2× PNG, fitted to a 3:2 canvas
  and drawn on a white page.
- **Preferences** — default length unit, angle unit, precision, grid, axes, snapping and labels
  for new sketches.
- **New documents** — a new sketch starts blank, with only the grid and axes from your
  preferences.

## Keyboard

| Key | Tool |
| --- | --- |
| V | Select |
| P | Point |
| S | Segment |
| R | Ray |
| L | Line |
| C | Circle |
| G | Polygon |
| A | Angle |
| T | Text |

`⌘Z` / `⇧⌘Z` undo and redo, `⌘A` select all, `⌘P` prints the sketch, Delete removes the
selection. Scroll to pan, pinch or `⌘`-scroll to zoom. Return closes a polygon; Escape cancels a
draft.

## What is new versus the original

- The original's geometry engine is C (`the object record` plus C functions such as the constraint
  checker); this rebuild writes the same model and rules in Swift. See `MECHANICS.md` for the
  evidence, the addresses and the values.
- The document format is this app's own JSON-based `.gsp`, not the original binary format.
- Custom tools/scripts, action buttons, iterations, tables, pictures, export and
  multiple pages are not included in this version.

## Evidence

The original was inspected statically (nothing from it was run). Key evidence ids:
`evidence` (x86 Mach-O),
`evidence` (C object struct),
`evidence` (C constraint checker),
`evidence` (`.c` source path),
`evidence` (C++ exports).
