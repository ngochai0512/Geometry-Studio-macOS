This sheet records the behavior this build implements and the values it uses. Values marked
**estimated** were chosen for usability rather than measured.

## Object and command model

- Every object has kind, genus (family), layer, alpha, colour, line width/stroke or point style,
  label state, visibility and up to four parents. Genus is the family used by commands and by the
  constraint checker.
- Object families: point, midpoint, line, ray, segment, polygon, circle, circle interior, arc,
  arc interior/sector/segment, text, measurement, caption, action button, coordinate
  system/axis, locus, function plot, parametric plot, transformed image, plotted point, table,
  parameter and picture.
- Construct commands: perpendicular, parallel, midpoint, circle by centre+point, circle by
  centre+radius, angle bisector, segment, interior, intersection, point on object, arc on circle,
  arc through 3 points, locus, translate, rotate, dilate, reflect, and the mark commands (mirror,
  centre, angle, ratio, vector).
- Measure commands: length, distance, perimeter, circumference, angle, arc angle, arc length,
  area, geometric slope, radius, ratio, calculate, coordinates, abscissa/ordinate, polar
  distance/direction, coordinate distance, equation.
- Measurements use the prefixes `m` for a measured segment (e.g. `m AB`), `m∠` for angles,
  `Area`, `Radius` and `Length`.

## Units, precision and styles

| Setting | Choices | Note |
| --- | --- | --- |
| Distance units | cm, inches, pixels | pixels are 72-ppi points, not CSS pixels |
| Angle units | degrees, directed degrees, radians | plain degrees are 0–180°; directed degrees −180…180°; radians −π…π |
| Precision | units, tenths, hundredths, thousandths, ten-thousandths, hundred-thousandths | 0–5 decimal places; display only |
| Point styles | Dot, Small, Medium, Large | |
| Line styles | solid, dashed, dotted (plus width) | |
| Toolbox | selection arrows, point, compass, straightedge, polygon, text, marker, information, custom tools | |
| Grid | show/hide on a coordinate system; snap points to integer coordinates | |

Defaults are inches, hundredths and degrees. The distance factor table is `[1, 72/2.54, 72]`,
read as pixels, centimetres and inches.

## Values used by this rebuild

| Setting | Value | Note |
| --- | --- | --- |
| Distance unit | inches by default; cm, inches, pixels offered | factor table `[1, 72/2.54, 72]`, whose third entry is points per inch |
| Angle unit | degrees by default; degrees, directed degrees, radians offered | |
| Plain angle range | 0–180°, undirected | |
| Directed angle range | −180…180° (radians −π…π) | |
| Measurement decimals | 2 (hundredths), choices 0–5 | |
| Grid spacing | 1 selected distance unit | snapping to integer coordinates; the grid follows the chosen unit |
| Canvas scale at 100% | 28.35 points per cm (72 points per inch) | |
| Point sizes | Dot 3, Small 4.5, Medium 6, Large 8 px | **estimated** |
| Line width | 1.5 px default; hairline…heavy presets 0.8–3.2 | **estimated** |
| Selection highlight | system accent ring | **estimated** |
| Minimum polygon vertices | 3 | polygon interior definition |
| Undo history | 80 states | **estimated** |

## Geometry rules implemented

These are standard constructions, implemented in Swift. Their rules line up with the command list
above.

- Midpoint: `M = (A + B) / 2`.
- Circle: centre `C`, point `P`, radius `r = |P − C|`.
- Perpendicular through `P` to line `AB`: direction `(−(B−A).y, (B−A).x)`.
- Parallel through `P`: direction `B − A`.
- Angle bisector at `V`: direction `normalize(normalize(A−V) + normalize(C−V))`; when the two
  directions cancel, use a perpendicular.
- Distance: Euclidean `√(dx² + dy²)`.
- Plain angle at `V` between `A` and `C`: `acos(dot(normalize(A−V), normalize(C−V)))`, 0–180°.
- Directed angle: `atan2(cross(u, v), dot(u, v))`, −180…180° (or −π…π).
- Line/line intersection: solve `A + t(B−A) = C + u(D−C)`; enforce segment/ray bounds.
- Line/circle intersection: quadratic in `t`; roots sorted, then bounds enforced.
- Circle/circle intersection: radical-line construction, zero/one/two answers.
- Polygon area: shoelace formula, absolute value; perimeter: sum of side lengths.
- Reflection in line `AB`: project `P` onto the line to get `F`, answer `2F − P`.
- Rotation about `C` by θ: `C + R(θ)(P − C)`.
- Dilation about `C` by k: `C + k(P − C)`.
- Translation by vector `B−A`: `P + (B−A)`.
- Point on object: the point stores a natural parameter (0–1 on a segment, angle on a circle,
  perimeter fraction on a polygon) and is recomputed when its parent changes.
- Intersection, midpoint, transform and measurement objects keep parent IDs; every canvas
  redraw evaluates parents first, so dragging a free point updates the whole construction.

## What this rebuild has

- Native Swift 5.9 / SwiftUI app for macOS 27+, built for Apple silicon (`arm64`).
- Tools: select/drag, point, segment, ray, line, circle, polygon, angle, text.
- Constructions: midpoint, perpendicular, parallel, angle bisector, intersection, segment,
  circle by centre+point, polygon interior, point on object, and locus from a point on a path
  plus the point it drives.
- Measurements: distance, length, perimeter, circumference, angle, area, radius, ratio,
  coordinates, equation, slope, and a calculation sheet.
- Transforms: reflect, rotate, dilate, translate (copies recompute from their source).
- Graph: grid, axes, snapping, function plots with an expression parser.
- Animation and tracing: a point on a path can be animated to the 60 Hz canvas clock, traced
  objects leave a sampled trail, and traces can be erased.
- Inspector for objects, labels, colour, line weight, dash, point shape and size, visibility,
  units, angle unit and decimal precision.
- Preferences for the units, precision and canvas defaults used by new sketches.
- Printing through the standard macOS print panel: the canvas is rendered at 2× to the imageable
  page area, with Page Setup controlling paper size, orientation and margins.
- Export to vector PDF, SVG and PNG at 2× from File > Export; the sketch is fitted to a 3:2
  canvas on a white page.
- Undo/redo with named steps, drag coalescing, an 80-step history and a history menu;
  hide/show and select all.
- Documents carry a schema revision; decoding tolerates missing newer keys, refuses a document
  from a newer build, and salvages the readable objects from a damaged file. Open/save, autosave,
  Versions, Open Recent, multiple windows and tabs come from SwiftUI's document architecture.
  Closing a window with unsaved changes, or quitting, asks whether to save first.
- A welcome sample that demonstrates a live circumcircle construction.
- `--screenshot <file.png>` renders the window for 120 frames without activating the app and
  writes a PNG.

## Not implemented, and why

- Sketches are saved as JSON in a `.gsp` file; a binary document format is not read or written.
- Custom tools/scripts, action buttons, iterations, tables, pictures and multiple pages are not in
  this version. Each is a separate subsystem.
