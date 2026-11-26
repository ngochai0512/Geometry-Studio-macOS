# Geometry Studio

A native macOS dynamic geometry sketchpad, written in **Swift and SwiftUI** for Apple silicon.

It is an independent implementation: construct points, lines, circles and polygons, then drag a
free point and watch every dependent object update.

This app is insprired by Geometer's Sketchpad 5, which was first released in 2009.

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
./.build/debug/GeometryStudio --screenshot /tmp/geometry-studio.png
```

This debug-only path opens a borderless window without activating the app, draws for 120 frames,
writes the window as a PNG and exits. Release builds compile the screenshot runner out, so the
app-bundle binary does not carry it.

## Core features

- **Tools** — click to select, hold to drag, hand/pan, point, segment, ray, line, circle, polygon, angle marker and text.
- **Constructions** — midpoint, perpendicular, parallel, angle bisector, perpendicular bisector,
  intersection, segment, circle by centre + point, circle by centre + radius, arc on a circle,
  arc through three points, polygon interior, point on object, tangents, radical axis, vector,
  vector sum/difference, parameters, coordinate systems and locus.
- **Measurements** — distance, length, perimeter, circumference, angle, area, radius, ratio,
  coordinates, abscissa/ordinate, polar distance/direction, coordinate distance, arc angle/length,
  equation, slope, measure-all and calculations.
- **Units and precision** — cm, inches or pixels; plain degrees, directed degrees or radians;
  0–5 decimal places, with centimetres, hundredths and degrees as the defaults.
- **Transforms** — mark a mirror, center, angle, ratio or vector, then reflect, rotate, dilate or translate. Images keep their source and update.
- **Graph** — orthogonal (standard or dense), triangular and polar grids with a selectable colour and bold style, a custom canvas background, axes with optional numbers and bold/italic/serif labels, snapping with haptic feedback, function plots, derivative plots, integral shading, tangents, value tables and root/intersection solvers.
- **Rendering** — optional Metal rendering for fills, paths, vectors, angle markers, traces and ticks, with the SwiftUI Canvas as the default and fallback.
- **Animation and tracing** — animate a point along its constraint, trace moving objects, and
  construct a locus from a driver point and the point it drives.
- **Inspector** — object browser, label, definition, colour, line width, dash, tick marks, angle marker, point shape and size, fill, arc fill, parameters, coordinate systems, units, angle unit and decimal precision.
- **Construction protocol** — a sheet listing every construction step in order.
- **Documents** — a document-based app: new, open, save and save as (`.gsp`, JSON document format),
  autosave, Versions, Open Recent, multiple windows and tabs, a revision stamp in the document,
  named undo/redo, automatic recovery of readable objects from a
  damaged file, and a save prompt when a window with unsaved changes closes or the app quits.
- **Printing** — File > Print (⌘P) fits the sketch to one page and uses the standard macOS print
  panel and preview; Page Setup controls paper size, orientation and margins.
- **Export** — File > Export writes a vector PDF, an SVG or a 2× PNG, fitted to a 3:2 canvas
  and drawn on a white page.
- **Preferences** — General, Appearance, Units, Canvas, Update and About panes, covering start
  at login, default object colours, GPU rendering, and the default length unit, angle unit,
  precision, grid, axes, snapping and labels for new sketches.
- **Drawing aids** — smart guides that snap to points, midpoints, intersections, parallel and
  perpendicular lines; selectable angle increments (5°, 15°, 30°, 45°, 90°); square, dense,
  triangular, polar and isometric grids. The toolbar grid menu switches visibility, style, colour,
  axes, labels, snapping and angle increments in one place.
- **Editing** — object browser with search, kind filter, lock and front/back layer order;
  in-place label editing; drag any construction by its free points; on-canvas scale and rotate
  handles; duplicate (⌘D), copy and paste across documents, and paste in place.
- **Discovery** — a one-time welcome with tips and a built-in triangle sample, a ⌘K command
  palette and an undo history panel.
- **Live feedback** — a readout of a dragged point's position and dependent measurements, plus
  area and perimeter for the current selection in the status bar. Haptics accompany snap
  alignment and rotation detents on Force Touch trackpads.
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

`⌘K` opens the command palette, `⌘D` duplicates the selection, `⌥⌘C` / `⌥⌘X` / `⌥⌘V` copy,
cut and paste objects across documents, `⌃⌘V` pastes in place, and `⌥⌘Z` opens the undo
history. Double-click a label to edit it in place.

## Design notes

- The geometry engine is written in Swift; the rules it implements and the values it uses are
  listed in `MECHANICS.md`.
- The document format is this app's own JSON-based `.gsp`.
- Custom tools/scripts, action buttons, iterations, tables, pictures and multiple pages are not
  included in this version.
