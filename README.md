# Geometry Studio

A native macOS dynamic geometry sketchpad, rebuilt in **Swift and SwiftUI** for Apple silicon.

The original is the reference application 5.06 (2013), a a legacy build application. It
cannot run on Apple silicon; this is a new implementation of the same idea: construct points,
lines, circles and polygons, then drag a free point and watch every dependent object update.

## Build and run

A Swift package: no Xcode project, no package dependencies.

```sh
swift build
swift run GeometryStudio
```

Release build:

```sh
swift build -c release
./.build/release/GeometryStudio
```

The package targets macOS 13 or newer and builds `arm64` on Apple silicon. `swift test` runs the
geometry and document suites.

## Screenshot mode

```sh
./.build/release/GeometryStudio --screenshot /tmp/geometry-studio.png
```

This opens a borderless window without activating the app, draws for 120 frames, writes the
window as a PNG and exits.

## Core features

- **Tools** — select/drag, point, segment, ray, line, circle, polygon, angle marker and text.
- **Constructions** — midpoint, perpendicular, parallel, angle bisector, intersection, segment,
  circle by centre + point, polygon interior, point on object and locus.
- **Measurements** — distance, length, perimeter, circumference, angle, area, radius, ratio,
  coordinates, equation, slope and calculations.
- **Units and precision** — cm, inches or pixels; plain degrees, directed degrees or radians;
  0–5 decimal places, as the original's Units preferences offer.
- **Transforms** — reflect, rotate, dilate and translate. Images keep their source and update.
- **Graph** — grid, axes, snapping and function plots.
- **Animation and tracing** — animate a point along its constraint, trace moving objects, and
  construct a locus from a driver point and the point it drives.
- **Inspector** — object browser, label, colour, line width, dash, point shape and size,
  visibility, fill, units, angle unit and decimal precision.
- **Documents** — new, open, save and save as (`.gsp`, JSON document format), a revision stamp
  in the document, named undo/redo with an undo history menu, and an autosaved draft offered for
  recovery after a crash.
- **Preferences** — default length unit, angle unit, precision, grid, axes, snapping and labels
  for new sketches.
- **Welcome sketch** — a triangle, its perpendicular bisectors, circumcentre, circumcircle,
  length measurement, coordinates and angle. Drag A, B or C to see the construction move.

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

`⌘Z` / `⇧⌘Z` undo and redo, `⌘A` select all, Delete removes the selection. Scroll to pan,
pinch or `⌘`-scroll to zoom. Return closes a polygon; Escape cancels a draft.

## What is new versus the original

- The original's geometry engine is C (`the object record` plus C functions such as the constraint
  checker); this rebuild writes the same model and rules in Swift. See `MECHANICS.md` for the
  evidence, the addresses and the values.
- The document format is this app's own JSON-based `.gsp`, not the original binary format.
- Custom tools/scripts, action buttons, iterations, tables, pictures, printing, export and
  multiple pages are not included in this version.

## Evidence

The original was inspected statically (nothing from it was run). Key evidence ids:
`evidence` (x86 Mach-O),
`evidence` (C object struct),
`evidence` (C constraint checker),
`evidence` (`.c` source path),
`evidence` (C++ exports).
