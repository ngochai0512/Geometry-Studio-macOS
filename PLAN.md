# PLAN — Feature Backlog

Feature plan for Geometry Studio, written 2026-11-16. Effort is rough: **S** ≤ 1 day, **M** 1–3 days, **L** 1–2 weeks. Nothing here is committed to a date.

Evidence references like `0,44` or `1,224` are rows in the original application's localizable string tables — they show the feature existed in the original, so it is parity work rather than invention. See `MECHANICS.md` for what those tables are.

Anyone adding a new **object family** (arc, mark, vector, table, picture, button) must land it in all four places: `ObjectKind` (`Model/ObjectModel.swift`), `GeometryEval` (`Model/GeometryEval.swift`), drawing plus hit-testing (`Views/CanvasDrawing.swift`, `Model/SketchModel+Geometry.swift`), and the inspector/measure UI (`Views/InspectorView.swift`, `Views/ContentView.swift`). See AGENTS.md §3.

## Status snapshot

Implemented today: 9 tools, 13 constructions, 17 measurements, 4 transforms, graph with function plots and snapping, inspector (style, definition, units, precision), labels and captions, animation, tracing, locus, calculations, named undo/redo with history menu (80 deep), versioned JSON `.gsp` save/open, document-based windows with autosave, Versions, Open Recent and tabs, preferences for new sketches, printing with page setup, export to vector PDF, SVG and PNG, an XcodeGen-built app bundle with exported `gsp` type and icon, CI plus tagged GitHub releases, `--screenshot` mode, arc fills, circle by radius, and a construction protocol.

Missing outright: clipboard, duplicate, persistent marks, tables, iterations, custom tools, scripts, action buttons, pictures, pages, parametric plots, hot text, coordinate systems.

## Tier 1 — Foundations (unblocks everything else)

| # | Feature | Why it matters | Where it lands | Effort | Done |
| --- | --- | --- | --- | --- | --- |
| 1 | Document schema version + migration | `SketchDocument` is unversioned; one new non-optional field breaks every saved sketch, because synthesized `Decodable` requires keys even when the property has a default | `Model/Document.swift` | S | [x] |
| 2 | Real document app: `DocumentGroup`, autosave, Versions, Open Recent, multiple windows and tabs | A single `WindowGroup` with hand-rolled `NSOpenPanel` gave no autosave, Versions, recents or window tabs | `App/GeometryStudioApp.swift`, `Views/DocumentWorkspace.swift` | M | [x] |
| 3 | App bundle, Info.plist, exported `gsp` UTType, icon | Without it `UTType(filenameExtension: "gsp")` returns `nil`, so panels filter as JSON; no Dock identity | `project.yml`, `App/` | S | [x] |
| 4 | Preferences window: default units, precision, angle unit, canvas defaults | The original had a Preferences dialog; ours hid these inside the inspector, and every new sketch reset to the same defaults | new `Settings` scene | S | [x] |
| 5 | Printing: `NSPrintOperation`, page setup, print preview | The original shipped full print support; we have none | `Printing/` | M | [x] |
| 6 | Export: PDF (vector), SVG, PNG @2x| A geometry tool's output goes into papers and slides; currently there is no way to get a picture out | new `Export/` | M | [x] |
| 7 | Undo polish: coalesce drags into one step, name actions, history menu | Every `checkpoint()` was one opaque step, and a click without movement pushed a no-op | `Model/SketchModel.swift` | S | [x] |
| 8 | Error handling: alerts for failed open/save, corrupt-file recovery | Errors only reached `statusMessage` and were easy to miss | `Model/SketchFileDocument.swift` | S | [x] |
| 9 | CI and release: build/test on push, signed and notarized `arm64` `.app` to GitHub Releases | Nothing existed; blocks distributing at all. Sparkle updates need an EdDSA keypair and appcast, deferred | `.github/workflows/` | M | [x] |
| 10 | Docs truth pass: README/MECHANICS claim animation, tracing and loci are absent — they shipped | Misleading for users and for future agents | `README.md`, `MECHANICS.md` | S | [x] |

Deferred within Tier 1: window appearance moved to #45, where the canvas theme lives; the Preferences window covers units, precision, angle unit and new-sketch canvas defaults. Sparkle updates remain a follow-up to #9 until an EdDSA keypair and appcast URL exist.

## Tier 2 — Parity with the original

| # | Feature | Original evidence | Where it lands | Effort | Done |
| --- | --- | --- | --- | --- | --- |
| 11 | Arcs: arc on circle, arc through 3 points | `0,44`–`0,47` | four places | M | [x] |
| 12 | Arc interior, sector and segment fills | `0,48`–`0,53`, `1,17` | four places | M | [x] |
| 13 | Arc angle and arc length measurements | `1,100`–`1,103` | `MeasureKind`, `GeometryEval` | S | [x] |
| 14 | Persistent marks: mirror, center, angle, ratio, vector (replacing modal dialogs) | `1,33`–`1,45` | `ObjectKind` + inspector | M | [ ] |
| 15 | Circle by center + numeric radius | construct table | `SketchModel+Construction` | S | [x] |
| 16 | Parameter / slider objects | `0,151` (parametric plots need them) | `ObjectKind` | S | [ ] |
| 17 | Tangents (point→circle, circle→circle), perpendicular bisector, radical axis | construct table | `GeometryEval`, `SketchModel+Construction` | S/M | [ ] |
| 18 | Polar distance/direction, abscissa/ordinate, coordinate distance | `1,109`, `1,110` | `MeasureKind` | S | [ ] |
| 19 | Vector objects, vector sum and difference | `1,40` | `ObjectKind`, canvas arrows | S | [ ] |
| 20 | Tick marks, angle-marker styles, richer point shapes and sizes | `0,144`–`0,149` | `Geometry/Style.swift`, `CanvasDrawing` | S | [ ] |
| 21 | Construction protocol: ordered list of every construction step | original list view | `Views/SketchSheets.swift` (ProtocolSheet) | S | [x] |
| 22 | Describe / Information tool: click an object, read its definition | `15,18` "Click objects to describe their definitions" | `Model/GeometryEval+Definition.swift` + inspector | S | [x] |
| 23 | Measure-all, and label placement rules | `1,88`–`1,115` | `GeometryEval.measurement` | S | [ ] |
| 24 | Coordinate systems as objects: multiple axes, polar grid, per-graph units | `0,67` | `ObjectKind` + `CanvasDrawing` | M | [ ] |
| 25 | Graph extras: derivative and integral shading, tangent at x, root/intersection solver, value table | `0,112`–`0,115` | `Geometry/Expression`, model extensions | M | [ ] |

Item 18 is partially shipped: abscissa, ordinate, polar distance and polar direction are implemented. Coordinate distance waits on coordinate systems (#24) so "coordinate" has a defined axis.

Item 12 ships as two fill modes on the arc object: Sector (centre wedge) and Segment (chord cap). The original's three command strings do not map to three distinct regions here.

## Tier 3 — The original's signature features

| # | Feature | Original evidence | Where it lands | Effort | Done |
| --- | --- | --- | --- | --- | --- |
| 26 | Custom tools: save a construction as a reusable tool, toolbox of user tools, persisted in the document | `8,165`, `8,2` | new `Model/CustomTool.swift` | L | [ ] |
| 27 | Script View: textual script of a construction, copy/print script, run script | `3,7`, `12,162`, `16,35` | new `Model/Script.swift` | M/L | [ ] |
| 28 | Iterations: iterate a construction to depth, iterated images, increase/decrease depth, final-orbit view | `1,224`–`1,229`, `0,100`–`0,103` | new `Model/Iteration.swift` | L | [ ] |
| 29 | Tables: tabulate measurements as a driver moves | `1,251`, `3,39`, `0,132`–`0,137` | `ObjectKind` + new view | M | [ ] |
| 30 | Action buttons: hide/show, move, animate, hyperlink, presentation slideshow | `1,224`–`1,255`, `0,38` | new `Model/ActionButton.swift` | M | [ ] |
| 31 | Hot text: measurements embedded in prose, live-updating | `10,80`, `30,4`–`30,6` | text object model | M | [ ] |
| 32 | Pictures: embed PNG/JPEG, move, scale, rotate, transform | `0,122`, `0,143` | `ObjectKind` + asset storage (needs #1) | M | [ ] |
| 33 | Multiple pages per document, page thumbnails | page tables | `SketchDocument`, document UI | M | [ ] |
| 34 | Parametric plots and plotted points | `0,151` | `EvalPath`, `Expression` | M | [ ] |
| 35 | Motion controller: play/pause, speed, direction, animate along a path | `16,14`, `1,203` | `SketchModel+Animation` | S/M | [ ] |
| 36 | Locus upgrades: adaptive sampling, gooseneck handling, trace fade and length | locus exists, fixed sample count | `SketchModel+Animation` | S/M | [ ] |
| 37 | Hot links and hyperlinks inside text | page/URL strings | text object | S | [ ] |

## Tier 4 — Modern macOS

| # | Feature | Effort | Done |
| --- | --- | --- | --- |
| 38 | iCloud Drive sync (ubiquitous container) | M | [ ] |
| 39 | Shortcuts and App Intents: New sketch, Open sketch, Export PNG | S | [ ] |
| 40 | Share sheet (`ShareLink`) for PNG and PDF | S | [ ] |
| 41 | Services menu, and drag and drop in/out (drop an image becomes a picture object) | S | [ ] |
| 42 | AppleScript / JXA dictionary (`sdef`) | M | [ ] |
| 43 | Quick Look preview for `.gsp` (`QLPreviewProvider`) | M | [ ] |
| 44 | Spotlight indexing of sketch titles | S | [ ] |
| 45 | Dark-mode-aware canvas, theme presets, custom paper tints | S | [ ] |
| 46 | Full localization via String Catalog; RTL canvas mirroring | M | [ ] |
| 47 | Accessibility: VoiceOver object descriptions, keyboard-only construction, high contrast | M | [ ] |
| 48 | Window state restore, tabs, Stage Manager behaviour | S | [ ] |
| 49 | Math labels: superscripts, subscripts, Greek, overline, arc notation | M | [ ] |
| 50 | Presentation mode: hide chrome, full screen, page through | S | [ ] |

## Tier 5 — Editing and UX depth

| # | Feature | Effort | Done |
| --- | --- | --- | --- |
| 51 | Smart guides: snap to midpoints, intersections, parallels, perpendiculars while drawing | M | [ ] |
| 52 | Angle snapping increments, adjustable grid types (square, polar, isometric) | S | [ ] |
| 53 | Object browser: search, filter by kind, groups, lock, layer reorder | M | [ ] |
| 54 | In-place label editing with drag handles | S | [ ] |
| 55 | On-canvas transform handles (rotate, scale) instead of dialogs | M | [ ] |
| 56 | Duplicate (⌘D), copy/paste across documents, paste in place | S | [ ] |
| 57 | Templates and New Document gallery: blank, grid, polar, triangle demo | S | [ ] |
| 58 | Onboarding, tips, sample gallery | M | [ ] |
| 59 | Command palette (⌘K) for constructions and measurements | S | [ ] |
| 60 | Undo history panel | S | [ ] |
| 61 | Live measurement HUD while dragging | S | [ ] |
| 62 | Selection info bar: area and perimeter of the current selection | S | [ ] |

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

- **DRM, activation, purchase licensing.** The original had `-license register`, a licence server and expiring site licences. Zero product value; the server is dead.
- **Java applet / applet export export.** Superseded by the vector and SVG export in #6.
- **Binary `.gsp` compatibility.** The format is undocumented and the original cannot run to verify against.
- **the legacy framework and Objective-C UI bridge.** Replaced by SwiftUI.
- **Real-time multi-user editing.** Cost far exceeds the value for a sketchpad.

## Recommended sequence

1. **Phase A — shippable (Tier 1, ~2 weeks).** Versioning → document app → bundle and UTType → preferences → printing → export → undo/error handling. Everything else depends on these.
2. **Phase B — parity (items 11–20, ~2 weeks).** Arcs and their fills, marks, tangents, vectors, missing measurements. Closes the gap to the original's geometry vocabulary.
3. **Phase C — signature (items 26–33, ~4 weeks).** Custom tools, scripts, tables, action buttons, pictures, pages. This is what makes it *that* app rather than a geometry editor.
4. **Phase D — differentiators (items 34–50).** iCloud, Shortcuts, Quick Look, accessibility, localization, presentation mode.

## Best value per day of work

#1 versioning · #3 bundle and UTType · #21 construction protocol · #22 describe tool · #26 custom tools · #39 App Intents · #51 smart guides · #56 duplicate and paste · #63 spatial index.
