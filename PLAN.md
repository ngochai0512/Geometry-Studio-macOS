# PLAN — Feature Backlog

Feature plan for Geometry Studio, written 2026-11-16. Effort is rough: **S** ≤ 1 day, **M** 1–3 days, **L** 1–2 weeks. Nothing here is committed to a date.

Anyone adding a new **object family** (arc, mark, vector, table, picture, button) must land it in all four places: `ObjectKind` (`Model/Objects/ObjectModel.swift`), `GeometryEval` (`Model/Evaluation/GeometryEval.swift`), drawing plus hit-testing (`View/Canvas/CanvasDrawing.swift`, `Model/Sketch/SketchModel_Geometry.swift`), and the inspector/measure UI (`View/Inspector/InspectorView.swift`, `View/Workspace/ContentView.swift`). See AGENTS.md §3.

## Status snapshot

Implemented today: 10 tools, construction and measurement commands, 4 transforms, graph with function plots and snapping, a persistent inspector (layers, style, definitions, editable coordinates, radius, length and angle), labels and captions, animation, tracing, locus, calculations, named undo/redo with history menu (80 deep) and an undo history panel, versioned JSON `.gsp` save/open, document-based windows with autosave, Versions, Open Recent and tabs, preferences for new sketches, printing with page setup, export to vector PDF, SVG and PNG, an XcodeGen-built app bundle with exported `gsp` type and icon, CI plus tagged GitHub releases, `--screenshot` mode, arc fills, circle by radius, a hand/pan tool, a construction protocol, smart guides, angle snapping, an isometric grid, a persistent layer list with search/filter/lock/order, in-place label editing, on-canvas transform handles, duplicate and cross-document copy/paste, onboarding tips with a built-in triangle sample, a command palette, live drag and creation readouts and selection area/perimeter, a share sheet for PDF and PNG, canvas themes with an automatic dark mode and custom tints, math label markup, VoiceOver object descriptions with keyboard nudging and space-panning, and a presentation mode.

Missing outright: tables, iterations, custom tools, scripts, action buttons, pictures, pages, parametric plots, hot text.

## Tier 1 — Foundations (unblocks everything else)

| # | Feature | Why it matters | Where it lands | Effort | Done |
| --- | --- | --- | --- | --- | --- |
| 1 | Document schema version + migration | `SketchDocument` is unversioned; one new non-optional field breaks every saved sketch, because synthesized `Decodable` requires keys even when the property has a default | `Model/Document.swift` | S | [x] |
| 2 | Real document app: `DocumentGroup`, autosave, Versions, Open Recent, multiple windows and tabs | A single `WindowGroup` with hand-rolled `NSOpenPanel` gave no autosave, Versions, recents or window tabs | `App/GeometryStudioApp.swift`, `View/Workspace/DocumentWorkspace.swift` | M | [x] |
| 3 | App bundle, Info.plist, exported `gsp` UTType, icon | Without it `UTType(filenameExtension: "gsp")` returns `nil`, so panels filter as JSON; no Dock identity | `project.yml`, `App/` | S | [x] |
| 4 | Preferences window: default units, precision, angle unit, canvas defaults | Preferences were hidden inside the inspector, and every new sketch reset to the same defaults | new `Settings` scene | S | [x] |
| 5 | Printing: `NSPrintOperation`, page setup, print preview | Printing was not implemented at all | `Service/Printing/` | M | [x] |
| 6 | Export: PDF (vector), SVG, PNG @2x| A geometry tool's output goes into papers and slides; currently there is no way to get a picture out | new `Service/Export/` | M | [x] |
| 7 | Undo polish: coalesce drags into one step, name actions, history menu | Every `checkpoint()` was one opaque step, and a click without movement pushed a no-op | `Model/Sketch/SketchModel.swift` | S | [x] |
| 8 | Error handling: alerts for failed open/save, corrupt-file recovery | Errors only reached `statusMessage` and were easy to miss | `Model/SketchFileDocument.swift` | S | [x] |
| 9 | CI and release: build/test on push, signed and notarized `arm64` `.app` to GitHub Releases | Nothing existed; blocks distributing at all. Sparkle updates need an EdDSA keypair and appcast, deferred | `.github/workflows/` | M | [x] |
| 10 | Docs truth pass: README/MECHANICS claimed animation, tracing and loci were absent — they had shipped | Misleading for users and for future agents | `README.md`, `MECHANICS.md` | S | [x] |

Deferred within Tier 1: window appearance moved to #45, where the canvas theme lives; the Preferences window covers units, precision, angle unit and new-sketch canvas defaults. Sparkle updates remain a follow-up to #9 until an EdDSA keypair and appcast URL exist.

## Tier 2 — Geometry parity

| # | Feature | Where it lands | Effort | Done |
| --- | --- | --- | --- | --- |
| 11 | Arcs: arc on circle, arc through 3 points | four places | M | [x] |
| 12 | Arc interior, sector and segment fills | four places | M | [x] |
| 13 | Arc angle and arc length measurements | `MeasureKind`, `GeometryEval` | S | [x] |
| 14 | Persistent marks: mirror, center, angle, ratio, vector (replacing modal dialogs) | `ObjectKind` + inspector | M | [x] |
| 15 | Circle by center + numeric radius | `SketchModel_Construction` | S | [x] |
| 16 | Parameter / slider objects | `ObjectKind` | S | [x] |
| 17 | Tangents (point→circle, circle→circle), perpendicular bisector, radical axis | `GeometryEval`, `SketchModel_Construction` | S/M | [x] |
| 18 | Polar distance/direction, abscissa/ordinate, coordinate distance | `MeasureKind` | S | [x] |
| 19 | Vector objects, vector sum and difference | `ObjectKind`, canvas arrows | S | [x] |
| 20 | Tick marks, angle-marker styles, richer point shapes and sizes | `Model/Geometry/Style.swift`, `CanvasDrawing` | S | [x] |
| 21 | Construction protocol: ordered list of every construction step | `View/Sheets/SketchSheets.swift` (ProtocolSheet) | S | [x] |
| 22 | Describe / Information tool: click an object, read its definition | `Model/Evaluation/GeometryEval_Definition.swift` + inspector | S | [x] |
| 23 | Measure-all, and label placement rules | `GeometryEval.measurement` | S | [x] |
| 24 | Coordinate systems as objects: multiple axes, polar grid, per-graph units | `ObjectKind` + `CanvasDrawing` | M | [x] |
| 25 | Graph extras: derivative and integral shading, tangent at x, root/intersection solver, value table | `Model/Geometry/Expression`, model extensions | M | [x] |

Item 18: abscissa, ordinate, polar distance/direction and coordinate distance are implemented. Coordinate distance uses the origin and unit of a selected coordinate-system object when one is in the selection; otherwise it uses the document axes and unit.

Item 12 ships as two fill modes on the arc object: Sector (centre wedge) and Segment (chord cap). The three command strings do not map to three distinct regions here.

## Tier 3 — Signature features

| # | Feature | Where it lands | Effort | Done |
| --- | --- | --- | --- | --- |
| 26 | Custom tools: save a construction as a reusable tool, toolbox of user tools, persisted in the document | new `Model/CustomTool.swift` | L | [ ] |
| 27 | Script View: textual script of a construction, copy/print script, run script | new `Model/Script.swift` | M/L | [ ] |
| 28 | Iterations: iterate a construction to depth, iterated images, increase/decrease depth, final-orbit view | new `Model/Iteration.swift` | L | [ ] |
| 29 | Tables: tabulate measurements as a driver moves | `ObjectKind` + new view | M | [ ] |
| 30 | Action buttons: hide/show, move, animate, hyperlink, presentation slideshow | new `Model/ActionButton.swift` | M | [ ] |
| 31 | Hot text: measurements embedded in prose, live-updating | text object model | M | [ ] |
| 32 | Pictures: embed PNG/JPEG, move, scale, rotate, transform | `ObjectKind` + asset storage (needs #1) | M | [ ] |
| 33 | Multiple pages per document, page thumbnails | `SketchDocument`, document UI | M | [ ] |
| 34 | Parametric plots and plotted points | `EvalPath`, `Expression` | M | [ ] |
| 35 | Motion controller: play/pause, speed, direction, animate along a path | `SketchModel_Animation` | S/M | [ ] |
| 36 | Locus upgrades: adaptive sampling, gooseneck handling, trace fade and length | `SketchModel_Animation` | S/M | [ ] |
| 37 | Hot links and hyperlinks inside text | text object | S | [ ] |

## Tier 4 — Modern macOS

| # | Feature | Effort | Done |
| --- | --- | --- | --- |
| 38 | iCloud Drive sync (ubiquitous container) | M | [ ] |
| 39 | Shortcuts and App Intents: New sketch, Open sketch, Export PNG | S | [ ] |
| 40 | Share sheet (`ShareLink`) for PNG and PDF | S | [x] |
| 41 | Services menu, and drag and drop in/out (drop an image becomes a picture object) | S | [ ] |
| 42 | AppleScript / JXA dictionary (`sdef`) | M | [ ] |
| 43 | Quick Look preview for `.gsp` (`QLPreviewProvider`) | M | [ ] |
| 44 | Spotlight indexing of sketch titles | S | [ ] |
| 45 | Dark-mode-aware canvas, theme presets, custom paper tints | S | [x] |
| 46 | Full localization via String Catalog; RTL canvas mirroring | M | [ ] |
| 47 | Accessibility: VoiceOver object descriptions, keyboard-only construction, high contrast | M | [ ] |
| 48 | Window state restore, tabs, Stage Manager behaviour | S | [ ] |
| 49 | Math labels: superscripts, subscripts, Greek, overline, arc notation | M | [x] |
| 50 | Presentation mode: hide chrome, full screen, page through | S | [x] |

Item 47 is partial: VoiceOver object descriptions and the Escape/arrow/Space keyboard support are in; high contrast and full keyboard-only construction are not.

## Tier 5 — Editing and UX depth

| # | Feature | Effort | Done |
| --- | --- | --- | --- |
| 51 | Smart guides: snap to midpoints, intersections, parallels, perpendiculars while drawing | M | [x] |
| 52 | Angle snapping increments, adjustable grid types (square, polar, isometric) | S | [x] |
| 53 | Object browser: search, filter by kind, groups, lock, layer reorder | M | [x] |
| 54 | In-place label editing with drag handles | S | [x] |
| 55 | On-canvas transform handles (rotate, scale) instead of dialogs | M | [x] |
| 56 | Duplicate (⌘D), copy/paste across documents, paste in place | S | [x] |
| 57 | Templates and New Document gallery: blank, grid, polar, triangle demo | S | [ ] |
| 58 | Onboarding, tips, sample gallery | M | [x] |
| 59 | Command palette (⌘K) for constructions and measurements | S | [x] |
| 60 | Undo history panel | S | [x] |
| 61 | Live measurement HUD while dragging | S | [x] |
| 62 | Selection info bar: area and perimeter of the current selection | S | [x] |

Item 55 collects the free-point ancestors of the selection, so a selected polygon, circle or measurement also shows handles; derived geometry follows those points. Item 53 provides front/back layer order rather than free drag-reordering. Item 60 lists named steps and travels through them with the existing undo/redo stack. Item 57's gallery was removed at request; the welcome sheet still offers one built-in triangle sample.

## Tier 6 — Performance and robustness

| # | Feature | Effort | Done |
| --- | --- | --- | --- |
| 63 | Spatial index for hit-testing (currently a linear scan on every drag) | S/M | [ ] |
| 64 | Incremental evaluation cache keyed by object revision (currently recomputed per redraw) | M | [ ] |
| 65 | Stress harness: 10k objects, drag latency budget | M | [ ] |
| 66 | Fuzz tests for `Expression` and `EvalPath` | S | [ ] |
| 67 | Golden-image rendering tests (the screenshot path already exists) | M | [ ] |
| 68 | Crash-safe autosave and reopen-last-document | S | [ ] |

## Deliberately not building

- **DRM, activation, purchase licensing.** Zero product value for a sketchpad.
- **Java applet export.** Superseded by the vector and SVG export in #6.
- **A binary `.gsp` format.** This app reads and writes its own JSON document.
- **A legacy AppKit bridge.** SwiftUI covers the same surface.
- **Real-time multi-user editing.** Cost far exceeds the value for a sketchpad.

## Recommended sequence

1. **Phase A — shippable (Tier 1, ~2 weeks).** Versioning → document app → bundle and UTType → preferences → printing → export → undo/error handling. Everything else depends on these.
2. **Phase B — parity (items 11–20, ~2 weeks).** Arcs and their fills, marks, tangents, vectors, missing measurements. Closes the gap in the geometry vocabulary.
3. **Phase C — signature (items 26–33, ~4 weeks).** Custom tools, scripts, tables, action buttons, pictures, pages. This is what makes it a sketchpad rather than a geometry editor.
4. **Phase D — differentiators (items 34–50).** iCloud, Shortcuts, Quick Look, accessibility, localization, presentation mode.

## Best value per day of work

#1 versioning · #3 bundle and UTType · #21 construction protocol · #22 describe tool · #26 custom tools · #39 App Intents · #51 smart guides · #56 duplicate and paste · #63 spatial index.
